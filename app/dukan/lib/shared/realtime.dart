// Subscribe a screen to Supabase realtime events on one or more
// tables, debounced so a transaction that touches N rows fires one
// refetch instead of N. RLS scopes events to the caller's shop, so
// we only need column-level filters where they materially reduce
// noise (e.g., a single shop_item id on the detail screen).
//
// Use case: an owner edits a price on the shop admin portal, and
// within seconds the cashier's open Product detail or Products list
// re-fetches and renders the new price — without polling and without
// the cashier needing to pull-to-refresh.
//
// Test ergonomics: RealtimeWatcher.tryCreate returns null when Supabase
// isn't initialised (i.e., in widget tests that mount a screen without
// the SDK). Screens treat the watcher as optional, so the realtime
// path is invisible to tests that don't care about it.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RealtimeSubscription {
  const RealtimeSubscription({required this.table, this.filter});

  /// `public.<table>` to subscribe to. Schema is always `public`; if
  /// we ever need to subscribe to non-public schemas, add a `schema`
  /// field here and thread it through.
  final String table;

  /// Optional equality / range filter. When null, the subscription
  /// fires on every change to the table that RLS permits.
  final PostgresChangeFilter? filter;
}

class RealtimeWatcher {
  RealtimeWatcher._({
    required SupabaseClient client,
    required String channelName,
    required List<RealtimeSubscription> subscriptions,
    required VoidCallback onChange,
    required Duration debounce,
  }) : _client = client,
       _onChange = onChange,
       _debounce = debounce {
    var channel = _client.channel(channelName);
    for (final sub in subscriptions) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: sub.table,
        filter: sub.filter,
        callback: (_) => _scheduleChange(),
      );
    }
    _channel = channel..subscribe();
  }

  /// Returns null when Supabase hasn't been initialised — keeps the
  /// realtime path inert in widget tests and prototype mode without
  /// every caller having to guard with its own try/catch.
  static RealtimeWatcher? tryCreate({
    required String channelName,
    required List<RealtimeSubscription> subscriptions,
    required VoidCallback onChange,
    Duration debounce = const Duration(milliseconds: 250),
  }) {
    final SupabaseClient client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      // Supabase.instance throws AssertionError when initialize hasn't
      // run — common in test harnesses and the prototype path.
      return null;
    }
    return RealtimeWatcher._(
      client: client,
      channelName: channelName,
      subscriptions: subscriptions,
      onChange: onChange,
      debounce: debounce,
    );
  }

  final SupabaseClient _client;
  final VoidCallback _onChange;
  final Duration _debounce;
  late final RealtimeChannel _channel;
  Timer? _timer;
  bool _disposed = false;

  void _scheduleChange() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (_disposed) return;
      _onChange();
    });
  }

  /// Synchronous — matches `State.dispose()`'s contract so callers in
  /// `dispose()` don't have to await. The server-side channel removal
  /// is async, but firing it without await is safe: the local timer
  /// + disposed flag are already cleared so no further `_onChange`
  /// will fire, and an in-flight `removeChannel` cannot reattach.
  /// Errors from the removal go to FlutterError instead of being
  /// silently dropped.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    unawaited(_client.removeChannel(_channel).then<String>(
      (s) => s,
      onError: (Object error, StackTrace stack) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'dukan realtime',
          context: ErrorDescription('removeChannel'),
        ));
        return 'ok';
      },
    ));
  }
}

/// Equality filter on a shop-scoped column. Most realtime
/// subscriptions in this app filter by shop_id or a specific entity
/// id; this helper keeps the call sites readable.
PostgresChangeFilter realtimeEq(String column, Object value) =>
    PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: column,
      value: value,
    );
