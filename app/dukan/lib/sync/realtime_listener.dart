// Realtime listener — subscribes to Supabase `postgres_changes`
// on the 4 most-changing tables (shop_item, shop_item_unit,
// party, transaction) filtered by the active shop_id, and
// pumps every row change into `SyncEngine.notifyEvent` (which
// already handles 200ms debounce + self-echo dedup via
// client_op_id; see sync_engine.dart #373).
//
// Activated only when `offline_mode = full` (per architecture
// doc); in `light` mode the listener stays inert.
//
// Reconnect strategy: Supabase's channel reconnects
// automatically. While disconnected, the 5-min periodic delta
// sync in SyncEngine covers gaps.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/sync/sync_engine.dart';

class RealtimeListener {
  RealtimeListener({
    required SupabaseClient client,
    required SyncEngine syncEngine,
    void Function(Object error, StackTrace stack, String hint)? reportError,
  })  : _client = client,
        _engine = syncEngine,
        _reportError = reportError;

  final SupabaseClient _client;
  final SyncEngine _engine;
  final void Function(Object, StackTrace, String)? _reportError;

  RealtimeChannel? _channel;
  String? _activeShopId;
  bool _disposed = false;

  /// Tables we subscribe to. Aligned with the architecture doc.
  /// Key = Postgres table name (passed to `onPostgresChanges`);
  /// value = SyncEngine resource key. The Postgres table is `txn`
  /// (not `transaction` — see migration 0009); the local mirror
  /// stores it under `local_transaction`. #385-fixup-2: was
  /// silently subscribing to a non-existent `transaction` table.
  static const _subscribedTables = <String, String>{
    'shop_item': 'shop_item',
    'shop_item_unit': 'shop_item_unit',
    'party': 'party',
    'txn': 'txn',
  };

  /// Begin listening for [shopId]. Idempotent — calling with the
  /// same shopId is a no-op; calling with a different shopId tears
  /// down the previous subscription and resubscribes.
  Future<void> start(String shopId) async {
    if (_disposed) return;
    if (_activeShopId == shopId && _channel != null) return;
    await stop();
    _activeShopId = shopId;
    try {
      final channel = _client.channel('shop-sync-$shopId');
      for (final entry in _subscribedTables.entries) {
        final pgTable = entry.key;
        final tableKey = entry.value;
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: pgTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'shop_id',
            value: shopId,
          ),
          callback: (payload) {
            _forward(tableKey, payload);
          },
        );
      }
      channel.subscribe((status, [_]) {
        // Supabase v2 surfaces channel lifecycle via subscribe's
        // optional callback. SUBSCRIBED → channel open;
        // CHANNEL_ERROR / TIMED_OUT / CLOSED → cannot reconnect.
        // We forward these to the SyncEngine which exposes
        // `realtimeDisconnectedAt` for CacheMissBoundary.
        switch (status) {
          case RealtimeSubscribeStatus.subscribed:
            _engine.markRealtimeConnected();
            break;
          case RealtimeSubscribeStatus.channelError:
          case RealtimeSubscribeStatus.timedOut:
          case RealtimeSubscribeStatus.closed:
            _engine.markRealtimeDisconnected();
            break;
        }
      });
      _channel = channel;
    } catch (error, stackTrace) {
      _engine.markRealtimeDisconnected();
      _reportError?.call(error, stackTrace, 'RealtimeListener.start');
      _channel = null;
    }
  }

  Future<void> stop() async {
    final ch = _channel;
    _channel = null;
    _activeShopId = null;
    if (ch != null) {
      try {
        await _client.removeChannel(ch);
      } catch (_) {
        // Best-effort — the channel might already be torn down.
      }
    }
  }

  void _forward(String tableKey, PostgresChangePayload payload) {
    try {
      final type = switch (payload.eventType) {
        PostgresChangeEvent.insert => 'INSERT',
        PostgresChangeEvent.update => 'UPDATE',
        PostgresChangeEvent.delete => 'DELETE',
        _ => 'UPDATE',
      };
      final event = RealtimeEvent(
        table: tableKey,
        eventType: type,
        newRow: payload.newRecord.isEmpty
            ? null
            : Map<String, dynamic>.from(payload.newRecord),
        oldRow: payload.oldRecord.isEmpty
            ? null
            : Map<String, dynamic>.from(payload.oldRecord),
      );
      _engine.notifyEvent(event);
    } catch (error, stackTrace) {
      _reportError?.call(error, stackTrace, 'RealtimeListener.forward');
    }
  }

  @visibleForTesting
  bool get isSubscribed => _channel != null;

  @visibleForTesting
  String? get activeShopId => _activeShopId;

  Future<void> dispose() async {
    _disposed = true;
    await stop();
  }
}
