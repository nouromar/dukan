// In-memory state + retry scheduling for the offline posting queue.
// Backed by PendingPostDao (sqflite) for durable, row-level
// persistence — every mutation hits a single row, not a re-encoded
// blob.
//
// Retry policy (exponential, capped):
//   attempt 1 fail -> 5 s
//   attempt 2     -> 15 s
//   attempt 3     -> 60 s
//   attempt 4     -> 5 min
//   attempt 5+    -> 30 min  (cap)
//
// The drain loop processes the queue head-first. On the first
// failure it stops to avoid hammering the network with a backlog;
// the next backoff fires another drain. Server-enforced idempotency
// via client_op_id ensures retried posts never duplicate.
//
// Connectivity: no explicit detection. Failed posts retry on the
// timer regardless. If the network's down, the retry fails fast
// (~1 s) and re-arms; if the network's up, it succeeds.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/storage/pending_post_dao.dart';

typedef PostExecutorFn = Future<void> Function(PendingPost post);

class OfflineQueueController extends ChangeNotifier {
  OfflineQueueController({
    required this.dao,
    required this.executor,
    Duration Function(int attempts)? backoff,
    DateTime Function()? clock,
  })  : _backoff = backoff ?? _defaultBackoff,
        _clock = clock ?? DateTime.now;

  final PendingPostDao dao;
  final PostExecutorFn executor;
  final Duration Function(int) _backoff;
  final DateTime Function() _clock;

  List<PendingPost> _pending = const <PendingPost>[];
  Timer? _retryTimer;
  bool _draining = false;
  bool _started = false;
  bool _disposed = false;

  /// Pending posts (most-recent appended last).
  List<PendingPost> get pending => List<PendingPost>.unmodifiable(_pending);

  int get pendingCount => _pending.length;

  bool get isDraining => _draining;

  /// Idempotent — second call is a no-op. Loads the persisted queue
  /// and arms the retry timer if anything was queued.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _pending = await dao.load();
    notifyListeners();
    if (_pending.isNotEmpty) {
      _scheduleDrain(immediate: true);
    }
  }

  /// Append a new pending post and trigger an immediate drain. Use
  /// for posts whose immediate attempt failed (the caller has already
  /// observed the failure and is queuing for background retry).
  Future<void> enqueue(PendingPost post) async {
    await dao.insert(post);
    _pending = [..._pending, post];
    notifyListeners();
    _scheduleDrain(immediate: true);
  }

  /// Force-fire the drain loop. Exposed for tests + the "tap to
  /// retry" affordance on the status pill.
  Future<void> drainNow() async {
    _retryTimer?.cancel();
    await _drain();
  }

  void _scheduleDrain({bool immediate = false}) {
    _retryTimer?.cancel();
    if (_disposed || _pending.isEmpty) return;
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
          if (_disposed) return;
          notifyListeners();
        } catch (error) {
          final attempts = head.attempts + 1;
          final lastAttemptAt = _clock();
          final errorString = error.toString();
          await dao.updateAttempts(
            id: head.id,
            attempts: attempts,
            lastAttemptAt: lastAttemptAt,
            lastError: errorString,
          );
          final updated = head.copyWith(
            attempts: attempts,
            lastAttemptAt: lastAttemptAt,
            lastError: errorString,
          );
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
