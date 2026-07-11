// Sync engine for the offline-first architecture (#373).
//
// State machine:
//   cold_no_local  → fullSync → live
//   cold_has_local → deltaSync (background) → live
//
// In `live`:
//   * realtime events arrive via `notifyEvent` and are
//     batched with a 200ms debounce window then applied as one
//     sqflite transaction;
//   * a periodic 5-min delta sync runs as a fallback for
//     missed realtime events;
//   * self-echo events (the mobile app's own writes coming
//     back via realtime) are filtered by checking the row's
//     `client_op_id` against the queue's known entries.
//
// Phase 1 (#373) ships the engine + entry points; the realtime
// subscription wiring + screen integration land in #374.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/storage/pending_post_dao.dart';
import 'package:dukan/sync/local_repository.dart';

/// Resource keys used in `local_sync_state` and the per-resource
/// delta RPC dispatch. Single source of truth.
class SyncResource {
  static const items = 'items';
  static const parties = 'parties';
  static const categories = 'categories';
  static const transactions = 'transactions';
  // #391: outstanding invoices cache backing the Payment allocation
  // sheet's offline read path.
  static const unpaidInvoices = 'unpaid_invoices';
  static const all = [
    items,
    parties,
    categories,
    transactions,
    unpaidInvoices,
  ];
}

/// Sync engine state. Exposed to consumers so a future first-sync
/// banner widget can render the right thing.
enum SyncEngineState {
  idle,
  fullSync,
  deltaSync,
  live,
  errored,
}

/// One realtime row change. Tables: 'shop_item', 'shop_item_unit',
/// 'party', 'txn'. `newRow`/`oldRow` are the WAL payloads as
/// Postgres JSON.
class RealtimeEvent {
  const RealtimeEvent({
    required this.table,
    required this.eventType,
    required this.newRow,
    required this.oldRow,
  });

  final String table;
  final String eventType; // 'INSERT' | 'UPDATE' | 'DELETE'
  final Map<String, dynamic>? newRow;
  final Map<String, dynamic>? oldRow;
}

class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required ShopApi shopApi,
    required LocalRepository localRepository,
    required PendingPostDao pendingPostDao,
    Duration realtimeDebounce = const Duration(milliseconds: 200),
    Duration deltaPollInterval = const Duration(minutes: 5),
    Duration cursorOverlap = Duration.zero,
    DateTime Function()? clock,
    void Function(Object error, StackTrace stack, String hint)? reportError,
  })  : _shopApi = shopApi,
        _local = localRepository,
        _pendingPostDao = pendingPostDao,
        _realtimeDebounce = realtimeDebounce,
        _deltaPollInterval = deltaPollInterval,
        _cursorOverlapMs = cursorOverlap.inMilliseconds,
        _clock = clock ?? DateTime.now,
        _reportError = reportError;

  final ShopApi _shopApi;
  final LocalRepository _local;
  final PendingPostDao _pendingPostDao;
  final Duration _realtimeDebounce;
  final Duration _deltaPollInterval;

  /// How far to REWIND each cursor below the server's `server_now_ms` when
  /// persisting it. The delta filter is `updated_at > cursor` and the server
  /// stamps `server_now_ms` at its transaction start — so a row whose writing
  /// transaction had set `updated_at` but not yet COMMITTED when the delta
  /// snapshotted sits at `updated_at <= server_now` yet is invisible to that
  /// read, and the next delta (`> server_now`) would skip it forever. Rewinding
  /// a couple of seconds re-fetches that boundary window; the apply* upserts
  /// are idempotent by id, so the overlap is harmless. Zero in tests (exact
  /// cursors); a few seconds in production.
  final int _cursorOverlapMs;
  final DateTime Function() _clock;
  final void Function(Object, StackTrace, String)? _reportError;

  /// Persisted-cursor value for a fetched `server_now_ms`, rewound by
  /// [_cursorOverlapMs] (never below zero). See that field for why.
  int _cursorMs(int serverNowMs) {
    if (_cursorOverlapMs <= 0) return serverNowMs;
    return serverNowMs > _cursorOverlapMs
        ? serverNowMs - _cursorOverlapMs
        : serverNowMs;
  }

  SyncEngineState _state = SyncEngineState.idle;
  SyncEngineState get state => _state;

  /// True after the first full sync has landed for the active shop.
  /// Read by the bootstrap to decide whether to show the
  /// "Connect to load your shop's data" first-sync card.
  bool _hasInitialSync = false;
  bool get hasInitialSync => _hasInitialSync;

  Object? _lastError;
  Object? get lastError => _lastError;

  /// Wallclock of the last successful sync (full or delta), used by
  /// the sync-issue banner to format "Working offline since ...".
  /// Null if no sync has ever landed.
  DateTime? _lastSyncedAt;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// Wallclock of the moment the realtime channel disconnected and
  /// could not reconnect. Null when connected (or never connected
  /// at all — light mode). Updated by [RealtimeListener].
  DateTime? _realtimeDisconnectedAt;
  DateTime? get realtimeDisconnectedAt => _realtimeDisconnectedAt;

  /// Toggled by [RealtimeListener.start] / .stop. Read by
  /// [CacheMissBoundary] to decide whether to surface a "sync issue"
  /// banner when the connection is gone.
  void markRealtimeConnected() {
    if (_realtimeDisconnectedAt == null) return;
    _realtimeDisconnectedAt = null;
    notifyListeners();
  }

  void markRealtimeDisconnected() {
    if (_realtimeDisconnectedAt != null) return;
    _realtimeDisconnectedAt = _clock();
    notifyListeners();
  }

  String? _activeShopId;
  Timer? _deltaTimer;
  Timer? _debounceTimer;
  final Queue<RealtimeEvent> _pendingEvents = Queue<RealtimeEvent>();
  bool _running = false;
  bool _disposed = false;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Start syncing for [shopId]. If no local sync state exists yet,
  /// runs a full sync (blocking). Otherwise enters live mode and
  /// fires a background delta to catch up.
  Future<void> start(String shopId) async {
    if (_disposed) return;
    _activeShopId = shopId;
    _running = true;
    final state = await _local.loadSyncState(shopId);
    final hasAny = state.values.any((s) => s.fullSyncDone);
    _hasInitialSync = hasAny;
    if (!hasAny) {
      await fullSync(shopId);
    } else {
      _setState(SyncEngineState.deltaSync);
      unawaited(deltaSync(shopId));
      _setState(SyncEngineState.live);
    }
    _scheduleNextDelta();
  }

  /// Stop all sync activity for the current shop. Used on sign-out
  /// + shop switch.
  void stop() {
    _activeShopId = null;
    _running = false;
    _deltaTimer?.cancel();
    _deltaTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingEvents.clear();
    _setState(SyncEngineState.idle);
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Full / delta sync
  // -------------------------------------------------------------------------

  /// One-shot fetch of EVERYTHING. Used on a fresh device or after
  /// `p_force=true` is requested.
  Future<void> fullSync(String shopId, {bool force = false}) async {
    _setState(SyncEngineState.fullSync);
    try {
      final payload = await _shopApi.getShopFullSync(
        shopId: shopId,
        force: force,
      );
      final serverNowMs =
          (payload['server_now_ms'] as num?)?.toInt() ?? _clock().millisecondsSinceEpoch;
      await _local.applyItemsPayload(
        _mapOrEmpty(payload['items_payload']),
      );
      await _local.applyPartiesPayload(
        _mapOrEmpty(payload['parties_payload']),
      );
      await _local.applyCategoriesPayload(
        _mapOrEmpty(payload['categories_payload']),
      );
      await _local.applyTransactionsPayload(
        _mapOrEmpty(payload['transactions_payload']),
      );
      await _local.applyUnpaidInvoicesPayload(
        _mapOrEmpty(payload['unpaid_invoices_payload']),
      );
      for (final resource in SyncResource.all) {
        await _local.writeSyncState(
          shopId: shopId,
          resource: resource,
          lastSyncedAtMs: _cursorMs(serverNowMs),
          fullSyncDone: true,
        );
      }
      _hasInitialSync = true;
      _lastError = null;
      _lastSyncedAt = _clock();
      // Successful full sync ⇒ online; clear the offline/realtime-down marker.
      _realtimeDisconnectedAt = null;
      _setState(SyncEngineState.live);
    } catch (error, stack) {
      _lastError = error;
      _setState(SyncEngineState.errored);
      _reportError?.call(error, stack, 'SyncEngine.fullSync');
      rethrow;
    }
  }

  /// Fan-out delta calls for each resource. Each resource syncs
  /// INDEPENDENTLY (its own try/catch inside [_deltaForResource]) so a
  /// failure in one — a poison payload, or a transient blip mid-sequence —
  /// can never starve the resources after it: parties, transactions, and
  /// invoices still advance even if items fails. (Previously all five shared
  /// one try/catch, so an early failure aborted the whole sequence and a
  /// persistent single-resource error froze every other resource forever.)
  Future<void> deltaSync(String shopId) async {
    if (_state != SyncEngineState.live &&
        _state != SyncEngineState.deltaSync) {
      _setState(SyncEngineState.deltaSync);
    }
    var anySucceeded = false;
    var anyFailed = false;
    for (final resource in SyncResource.all) {
      final ok = await _deltaForResource(shopId, resource);
      if (ok) {
        anySucceeded = true;
      } else {
        anyFailed = true;
      }
    }

    if (!anyFailed) _lastError = null;
    if (anySucceeded) {
      _lastSyncedAt = _clock();
      // At least one resource reached the server, so we're online — clear the
      // realtime-down marker so the "Working offline" banner dismisses on a
      // manual retry (or the next poll) instead of lingering until an app
      // restart. The realtime listener re-flags if its socket is still down.
      // When already `live` (a poll, not a deltaSync→live transition) we must
      // notify explicitly, otherwise the banner never rebuilds.
      final wasOffline = _realtimeDisconnectedAt != null;
      _realtimeDisconnectedAt = null;
      if (_state == SyncEngineState.deltaSync) {
        _setState(SyncEngineState.live);
      } else if (wasOffline) {
        notifyListeners();
      }
    } else if (_state == SyncEngineState.deltaSync) {
      // Everything failed (likely offline) — don't get stuck in deltaSync;
      // go live so cached data is usable. Leave the offline marker in place.
      _setState(SyncEngineState.live);
    }
  }

  /// Manually-triggered delta sync — same as [deltaSync] but ignores
  /// the periodic interval. Used by the sync-issue banner's "Tap to
  /// retry" affordance. Returns the count of resources whose state
  /// timestamp advanced (a rough "how many updates" surface for the
  /// success toast).
  Future<int> forceDelta(String shopId) async {
    final before = await _local.loadSyncState(shopId);
    await deltaSync(shopId);
    final after = await _local.loadSyncState(shopId);
    var advanced = 0;
    for (final key in SyncResource.all) {
      final b = before[key]?.lastSyncedAtMs ?? 0;
      final a = after[key]?.lastSyncedAtMs ?? 0;
      if (a > b) advanced++;
    }
    return advanced;
  }

  // -------------------------------------------------------------------------
  // Realtime
  // -------------------------------------------------------------------------

  /// Receive a realtime event. Buffered + debounced (200ms) so
  /// rapid bursts (e.g. CSV import) flush as one transaction.
  void notifyEvent(RealtimeEvent event) {
    if (_disposed || !_running) return;
    _pendingEvents.add(event);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_realtimeDebounce, _flushPending);
  }

  Future<void> _flushPending() async {
    if (_disposed) return;
    if (_pendingEvents.isEmpty) return;
    final events = List<RealtimeEvent>.from(_pendingEvents);
    _pendingEvents.clear();
    final ownClientOpIds = await _knownClientOpIds();
    // De-dupe affected resources so a burst of 200 CSV-imported
    // rows fires exactly one delta call per resource, not 200.
    final resourcesToRefresh = <String>{};
    var clearedAnyProjection = false;
    for (final event in events) {
      final row = event.newRow ?? event.oldRow;
      if (row == null) continue;
      final clientOpId = row['client_op_id'] as String?;
      if (clientOpId != null && ownClientOpIds.contains(clientOpId)) {
        // Our own write, looping back. Clear the projection for
        // this post — the server has now reflected the change.
        final post = await _findPendingByClientOpId(clientOpId);
        if (post != null) {
          await _local.clearProjectionsForPost(post.id);
          clearedAnyProjection = true;
        }
        // #385-fixup-2: for transactions, still schedule the
        // delta. The WAL row for a `txn` lacks `transaction_line`
        // children and the optimistic local row has
        // `serverUpdatedAtMs = 0` (which keeps `postedAt` null
        // and hides the void affordance). The delta fetches the
        // full payload with lines_summary and the dedup-by-
        // client_op_id in `applyTransactionsPayload` replaces
        // the optimistic row atomically. Other tables' WAL rows
        // ARE the new state, so skip-on-self-echo stays correct
        // for them.
        if (_resourceForTable(event.table) == SyncResource.transactions) {
          resourcesToRefresh.add(SyncResource.transactions);
        }
        continue;
      }
      final resource = _resourceForTable(event.table);
      if (resource != null) {
        resourcesToRefresh.add(resource);
      }
    }
    final shopId = _activeShopId;
    if (shopId != null) {
      for (final resource in resourcesToRefresh) {
        unawaited(_deltaForResource(shopId, resource));
      }
    }
    if (clearedAnyProjection || resourcesToRefresh.isNotEmpty) {
      notifyListeners();
    }
  }

  String? _resourceForTable(String table) {
    switch (table) {
      case 'shop_item':
      case 'shop_item_unit':
      case 'shop_item_alias':
      case 'shop_item_barcode':
        return SyncResource.items;
      case 'party':
        return SyncResource.parties;
      case 'expense_category':
      case 'category':
      case 'unit':
        return SyncResource.categories;
      case 'txn':
        return SyncResource.transactions;
      // #391: payment + payment_allocation events change the
      // `remaining` of cached unpaid invoices — schedule the
      // unpaidInvoices delta to refresh the local mirror.
      case 'payment':
      case 'payment_allocation':
        return SyncResource.unpaidInvoices;
      default:
        return null;
    }
  }

  /// Sync a single resource from its own cursor. Returns true on success,
  /// false when the fetch/apply threw (already reported) or the resource is
  /// unknown — so callers ([deltaSync]) can tell "advanced" from "stalled"
  /// without one resource's failure affecting another.
  Future<bool> _deltaForResource(String shopId, String resource) async {
    final state = await _local.loadSyncState(shopId);
    final since = _sinceFromState(state[resource]);
    try {
      Map<String, dynamic> payload;
      switch (resource) {
        case SyncResource.items:
          payload =
              await _shopApi.getShopItemsDelta(shopId: shopId, since: since);
          await _local.applyItemsPayload(payload);
          break;
        case SyncResource.parties:
          payload =
              await _shopApi.getPartiesDelta(shopId: shopId, since: since);
          await _local.applyPartiesPayload(payload);
          break;
        case SyncResource.categories:
          payload =
              await _shopApi.getCategoriesDelta(shopId: shopId, since: since);
          await _local.applyCategoriesPayload(payload);
          break;
        case SyncResource.transactions:
          payload = await _shopApi.getTransactionsDelta(
              shopId: shopId, since: since);
          await _local.applyTransactionsPayload(payload);
          break;
        case SyncResource.unpaidInvoices:
          payload = await _shopApi.getUnpaidInvoicesDelta(
              shopId: shopId, since: since);
          await _local.applyUnpaidInvoicesPayload(payload);
          break;
        default:
          return false;
      }
      await _local.writeSyncState(
        shopId: shopId,
        resource: resource,
        lastSyncedAtMs: _cursorMs(_serverNowOrLocal(payload)),
      );
      return true;
    } catch (error, stack) {
      _reportError?.call(
          error, stack, 'SyncEngine._deltaForResource[$resource]');
      return false;
    }
  }

  Future<Set<String>> _knownClientOpIds() async {
    final pending = await _pendingPostDao.load();
    final failed = await _pendingPostDao.loadFailedPermanent();
    return {
      for (final p in pending)
        if (p.clientOpId.isNotEmpty) p.clientOpId,
      for (final p in failed)
        if (p.clientOpId.isNotEmpty) p.clientOpId,
    };
  }

  Future<PendingPost?> _findPendingByClientOpId(String clientOpId) async {
    final pending = await _pendingPostDao.load();
    for (final p in pending) {
      if (p.clientOpId == clientOpId) return p;
    }
    final failed = await _pendingPostDao.loadFailedPermanent();
    for (final p in failed) {
      if (p.clientOpId == clientOpId) return p;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  void _setState(SyncEngineState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  void _scheduleNextDelta() {
    _deltaTimer?.cancel();
    if (!_running || _disposed) return;
    _deltaTimer = Timer(_deltaPollInterval, () async {
      final shopId = _activeShopId;
      if (shopId != null) {
        await deltaSync(shopId);
      }
      if (_running && !_disposed) {
        _scheduleNextDelta();
      }
    });
  }

  /// Use the server-supplied `server_now_ms` from the most recent
  /// payload if present (avoids client clock skew); otherwise fall
  /// back to local clock.
  int _serverNowOrLocal(Map<String, dynamic> payload) {
    final raw = payload['server_now_ms'];
    if (raw is num) return raw.toInt();
    return _clock().millisecondsSinceEpoch;
  }

  DateTime _sinceFromState(ResourceSyncState? state) {
    if (state == null) {
      // No state for this resource yet. Use a far-past timestamp.
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(
      state.lastSyncedAtMs,
      isUtc: true,
    );
  }

  Map<String, dynamic> _mapOrEmpty(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }
}
