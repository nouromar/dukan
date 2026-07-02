// In-memory state + retry scheduling for the offline posting queue.
// Backed by PendingPostDao (sqflite) for durable, row-level
// persistence — every mutation hits a single row, not a re-encoded
// blob.
//
// Retry policy — SILENT, NEVER-EXPIRING, FAILURE-TYPE-AWARE. A queued
// post retries forever until it lands; nothing is ever silently
// abandoned. The drain classifies each failure (see the constructor
// callbacks):
//   * auth/token (401)  -> refresh the session, retry, DON'T count it.
//   * permanent reject  -> park quietly (failed_permanent) + log; a
//                          poison post that would fail identically
//                          forever is the only thing that stops.
//   * transient (net /   -> keep the post at the head and retry FOREVER
//     timeout / offline)    on exponential backoff (5s→15s→60s→5m→30m cap).
//
// The drain loop processes head-first and stops on the first transient
// failure to avoid hammering a backlog; the next backoff — or an
// immediate drainNow() on a reconnect edge — re-attempts. Server-enforced
// idempotency via client_op_id ensures retried posts never duplicate.
//
// Connectivity: no in-loop polling. Offline, the head fails fast (~1s)
// and re-arms on backoff; the app wires drainNow() to the OS
// offline→online edge + resume so a returning connection drains at once.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/storage/pending_post_dao.dart';
import 'package:dukan/storage/storage_defaults.dart';
import 'package:dukan/sync/use_local_db.dart';

typedef PostExecutorFn = Future<void> Function(PendingPost post);

/// Fires when a `pending` post is dropped to make room for a new
/// enqueue (size cap reached). The UI subscribes to this to show
/// the one-time "Some old unsynced data was dropped" toast.
typedef DroppedListener = void Function(PendingPost dropped);

/// Fires when a post transitions to the terminal `failed_permanent`
/// state after exhausting [kQueueMaxAttempts] drain attempts.
typedef FailedPermanentListener = void Function(PendingPost failed);

class OfflineQueueController extends ChangeNotifier {
  OfflineQueueController({
    required this.dao,
    required this.executor,
    this.configResolver,
    this.onProjectionCleanup,
    this.isAuthError,
    this.refreshSession,
    this.isPermanentError,
    Duration Function(int attempts)? backoff,
    DateTime Function()? clock,
    int? maxPending,
  })  : _explicitBackoff = backoff,
        _clock = clock ?? DateTime.now,
        _explicitMaxPending = maxPending;

  final PendingPostDao dao;
  final PostExecutorFn executor;

  /// Classifies a drain error as an auth/token failure (e.g. expired
  /// access token → 401). When it returns true the drain refreshes the
  /// session and retries WITHOUT consuming a retry attempt, so a token
  /// outage can never strand a post. Null (unit tests / not wired) → no
  /// error is treated as auth.
  final bool Function(Object error)? isAuthError;

  /// Best-effort session refresh, invoked when [isAuthError] flags a
  /// drain error. Null → skip the refresh; either way the auth failure
  /// doesn't consume an attempt.
  final Future<void> Function()? refreshSession;

  /// Classifies a drain error as a PERMANENT/non-retryable failure — a
  /// genuine server reject (business rule, constraint) that will fail
  /// identically no matter how often we retry. Only such errors park a
  /// post (quietly, logged); everything else (network, timeout, offline,
  /// unknown) retries FOREVER — the queue never expires. Null → nothing
  /// is permanent, so every failure retries indefinitely.
  final bool Function(Object error)? isPermanentError;

  /// Called when a queue entry leaves the pending state — either
  /// drained successfully or transitioned to failed_permanent. Used
  /// by the offline-first wiring (#374) to clear
  /// `local_stock_projection` rows associated with the post id,
  /// so the on-screen stock reverts (failed) or reconciles with
  /// the server's new value (success). Optional — set to null in
  /// `light` offline mode where projections don't exist.
  final Future<void> Function(String pendingPostId)? onProjectionCleanup;

  /// Optional — when wired, the controller reads `queueMaxPending` /
  /// `queueMaxAttempts` / `queueRetry*` from the hierarchical config
  /// (defaults → org → shop → device). Tests pass an explicit value
  /// via the constructor and skip the resolver entirely.
  final ConfigResolver? configResolver;

  final Duration Function(int)? _explicitBackoff;
  final DateTime Function() _clock;
  final int? _explicitMaxPending;

  int get _maxPending {
    if (_explicitMaxPending != null) return _explicitMaxPending;
    final r = configResolver;
    if (r != null) return r.resolve(ConfigKeys.queueMaxPending);
    return kQueueMaxPending;
  }

  Duration _backoff(int attempts) {
    if (_explicitBackoff != null) return _explicitBackoff(attempts);
    final r = configResolver;
    if (r != null) {
      final initialMs = r.resolve(ConfigKeys.queueRetryInitialMs);
      final maxMs = r.resolve(ConfigKeys.queueRetryMaxMs);
      final multiplier = r.resolve(ConfigKeys.queueRetryMultiplier);
      // attempts=0 → initial; attempts=1 → initial*mult; capped.
      var ms = initialMs;
      for (var i = 0; i < attempts; i++) {
        ms *= multiplier;
        if (ms >= maxMs) {
          ms = maxMs;
          break;
        }
      }
      return Duration(milliseconds: ms);
    }
    return _defaultBackoff(attempts);
  }

  List<PendingPost> _pending = const <PendingPost>[];
  Timer? _retryTimer;
  bool _draining = false;
  bool _started = false;
  bool _disposed = false;

  /// Wall-clock time of the last successful drain attempt — i.e. the
  /// most recent moment we definitely had network connectivity. The
  /// Storage & sync screen derives "Connected" vs "Offline" from
  /// this (within 60s + queue empty → Connected). Null until the
  /// first successful drain in this process.
  DateTime? _lastDrainSuccessAt;
  DateTime? get lastDrainSuccessAt => _lastDrainSuccessAt;

  /// Listeners notified when posts are dropped (size cap) or
  /// promoted to failed_permanent. UI surfaces wire these to toasts
  /// / badges. Multiple listeners supported so different screens
  /// can react independently.
  final List<DroppedListener> _droppedListeners = <DroppedListener>[];
  final List<FailedPermanentListener> _failedListeners =
      <FailedPermanentListener>[];

  void addDroppedListener(DroppedListener l) => _droppedListeners.add(l);
  void removeDroppedListener(DroppedListener l) =>
      _droppedListeners.remove(l);

  void addFailedPermanentListener(FailedPermanentListener l) =>
      _failedListeners.add(l);
  void removeFailedPermanentListener(FailedPermanentListener l) =>
      _failedListeners.remove(l);

  /// Pending posts (most-recent appended last).
  List<PendingPost> get pending => List<PendingPost>.unmodifiable(_pending);

  int get pendingCount => _pending.length;

  /// Count of posts PARKED in the terminal `failed_permanent` state
  /// because the server rejected them on retry (permanent/non-retryable
  /// — see [isPermanentError]). Transient failures never land here; they
  /// retry forever. Parked posts are NOT in [_pending] (load() filters
  /// to state='pending'), so this count is what keeps them visible in
  /// the quiet status indicator (and manually retryable via
  /// [retryFailed]) instead of vanishing. Refreshed on [start], on each
  /// park, and after [retryFailed].
  int _failedCount = 0;
  int get failedCount => _failedCount;

  bool get isDraining => _draining;

  /// Idempotent — second call is a no-op. Loads the persisted queue
  /// and arms the retry timer if anything was queued.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _pending = await dao.load();
    _failedCount = await dao.countFailedPermanent();
    notifyListeners();
    if (_pending.isNotEmpty) {
      _scheduleDrain(immediate: true);
    }
  }

  /// Reset every parked `failed_permanent` post back to `pending` and
  /// drain immediately. Wired to the status indicator's tap: the manual
  /// escape hatch for a post the server rejected on retry. Idempotent
  /// when there's nothing to retry.
  Future<void> retryFailed() async {
    final failed = await dao.loadFailedPermanent();
    if (failed.isEmpty) {
      if (_failedCount != 0) {
        _failedCount = 0;
        notifyListeners();
      }
      return;
    }
    for (final p in failed) {
      await dao.resetToPending(p.id);
    }
    _pending = await dao.load();
    _failedCount = await dao.countFailedPermanent();
    notifyListeners();
    await drainNow();
  }

  /// Append a new pending post and trigger an immediate drain. Use
  /// for posts whose immediate attempt failed (the caller has already
  /// observed the failure and is queuing for background retry).
  ///
  /// Enforces the size cap [_maxPending]: if already at cap, drops
  /// the oldest pending post first, logs the dropped payload to
  /// Sentry, and fires registered [DroppedListener]s so UI can show
  /// the cashier a one-time warning.
  Future<void> enqueue(PendingPost post) async {
    if (_pending.length >= _maxPending) {
      final dropped = await dao.dropOldestPending();
      if (dropped != null) {
        _pending = _pending.where((p) => p.id != dropped.id).toList();
        FlutterError.reportError(FlutterErrorDetails(
          exception: StateError(
            'queue size cap ($_maxPending) reached — dropped oldest '
            'pending post ${dropped.id} (rpc=${dropped.rpc}, '
            'shop=${dropped.shopId}, queued_at=${dropped.queuedAt})',
          ),
          library: 'dukan queue',
          context: ErrorDescription('OfflineQueueController.enqueue'),
        ));
        for (final l in _droppedListeners) {
          l(dropped);
        }
      }
    }
    await dao.insert(post);
    _pending = [..._pending, post];
    notifyListeners();
    _scheduleDrain(immediate: true);
  }

  /// Force-fire the drain loop with a hard timeout. Used by the
  /// sign-out flow which can't block indefinitely on a slow
  /// network. Returns when either the drain completes or the
  /// timeout elapses — whichever comes first. Drain itself
  /// continues in the background if it didn't finish.
  Future<void> drainWithTimeout(Duration timeout) async {
    await Future.any<void>([
      drainNow(),
      Future<void>.delayed(timeout),
    ]);
  }

  /// Force-fire the drain loop. Exposed for tests + the "tap to
  /// retry" affordance on the status pill.
  Future<void> drainNow() async {
    _retryTimer?.cancel();
    await _drain();
  }

  /// #383: When `useLocalDb` is false the app behaves as a thin
  /// client — every post must go directly to the server with no
  /// queue fallback. The drain timer is suppressed in that mode so
  /// that any pre-existing pending rows (from a prior ON session)
  /// stay frozen until either the user flips back to ON or
  /// auth_bootstrap explicitly calls `drainNow()` at startup.
  /// Tests without a ConfigResolver in scope keep the legacy
  /// behavior (timer always armed).
  bool get _drainTimerAllowed {
    final r = configResolver;
    if (r == null) return true;
    return resolveUseLocalDb(r);
  }

  void _scheduleDrain({bool immediate = false}) {
    _retryTimer?.cancel();
    if (_disposed || _pending.isEmpty) return;
    if (!_drainTimerAllowed) return;
    if (immediate) {
      _retryTimer = Timer(Duration.zero, _drain);
      return;
    }
    // Backoff uses the head item's attempt count so a stuck item
    // gets the longest wait; newer items still get their first try
    // quickly since they're behind the head.
    final delay = _backoff(_pending.first.attempts);
    _retryTimer = Timer(delay, _drain);
  }

  Future<void> _drain() async {
    if (_disposed || _draining || _pending.isEmpty) return;
    _draining = true;
    notifyListeners();
    try {
      // Process head-to-tail; stop on first failure so we don't
      // beat on a broken connection.
      while (_pending.isNotEmpty) {
        final head = _pending.first;
        try {
          await executor(head);
          await dao.remove(head.id);
          _pending = _pending.sublist(1);
          _lastDrainSuccessAt = _clock();
          // #374: server now owns the canonical stock after this
          // post succeeded; the local projection is no longer
          // needed (delta sync / realtime will deliver the real
          // numbers).
          await _safeCleanupProjection(head.id);
          if (_disposed) return;
          notifyListeners();
        } catch (error) {
          final now = _clock();
          // (1) Auth/token failure (e.g. expired access token → 401):
          // refresh the session and retry WITHOUT consuming an attempt,
          // so a token outage can never strand a post. This was the
          // likely original data-loss trigger.
          if (isAuthError?.call(error) ?? false) {
            final refresh = refreshSession;
            if (refresh != null) {
              try {
                await refresh();
              } catch (_) {
                // Refresh failed (truly signed out) — still don't burn
                // the attempt; we'll try again on the next drain.
              }
            }
            if (_disposed) return;
            await dao.updateAttempts(
              id: head.id,
              attempts: head.attempts,
              lastAttemptAt: now,
              lastError: 'auth: $error',
            );
            _pending = [
              head.copyWith(lastAttemptAt: now, lastError: 'auth: $error'),
              ..._pending.sublist(1),
            ];
            if (_disposed) return;
            notifyListeners();
            break;
          }
          final attempts = head.attempts + 1;
          final errorString = error.toString();
          await dao.updateAttempts(
            id: head.id,
            attempts: attempts,
            lastAttemptAt: now,
            lastError: errorString,
          );
          final updated = head.copyWith(
            attempts: attempts,
            lastAttemptAt: now,
            lastError: errorString,
          );
          // (2) Permanent/non-retryable failure — a genuine server reject
          // that will fail identically forever. Park it QUIETLY (no
          // alert) and log, so a poison post can't spin indefinitely.
          // Rare: most rejects are caught inline and never queue.
          if (isPermanentError?.call(error) ?? false) {
            await dao.markFailedPermanent(head.id);
            _pending = _pending.sublist(1);
            _failedCount += 1;
            // #374: clear projection so on-screen stock reverts.
            await _safeCleanupProjection(head.id);
            // Notify listeners (production wires one to CrashReporter so
            // a parked post is logged; kept out of the controller so the
            // park path stays log-free and test-quiet).
            for (final l in _failedListeners) {
              l(updated);
            }
            if (_disposed) return;
            notifyListeners();
            // Keep draining the rest — other posts may still succeed.
            continue;
          }
          // (3) Transient (network / timeout / offline / unknown): keep
          // the post at the head and retry FOREVER. The queue never
          // expires; a reconnect (drainNow) or the backoff timer will
          // re-attempt it.
          _pending = [updated, ..._pending.sublist(1)];
          if (_disposed) return;
          notifyListeners();
          break;
        }
      }
    } finally {
      _draining = false;
      if (!_disposed) {
        notifyListeners();
        _scheduleDrain();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    super.dispose();
  }

  /// Best-effort projection cleanup. Never blocks the queue on a
  /// failure (queue's job is to drain posts; projection rows are a
  /// UI nicety).
  Future<void> _safeCleanupProjection(String pendingPostId) async {
    final cb = onProjectionCleanup;
    if (cb == null) return;
    try {
      await cb(pendingPostId);
    } catch (_) {
      // Swallow — UI will reconcile on next delta sync.
    }
  }
}

Duration _defaultBackoff(int attempts) {
  switch (attempts) {
    case 0:
    case 1:
      return const Duration(seconds: 5);
    case 2:
      return const Duration(seconds: 15);
    case 3:
      return const Duration(seconds: 60);
    case 4:
      return const Duration(minutes: 5);
    default:
      return const Duration(minutes: 30);
  }
}
