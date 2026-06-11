import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/shared/realtime.dart';

void main() {
  group('RealtimeWatcher.tryCreate', () {
    // Tests run without Supabase.initialize — the wrapper must return
    // null so screens can mount unaffected. The contract is "the
    // realtime path is invisible when the SDK isn't ready," which is
    // what every widget test depends on.
    test('returns null when Supabase is not initialised', () {
      var fired = false;
      final watcher = RealtimeWatcher.tryCreate(
        channelName: 'noop',
        subscriptions: const [RealtimeSubscription(table: 'shop_item')],
        onChange: () => fired = true,
      );
      expect(watcher, isNull);
      expect(fired, isFalse);
    });

    test('tryCreate is idempotent — repeat calls still return null', () {
      final a = RealtimeWatcher.tryCreate(
        channelName: 'a',
        subscriptions: const [RealtimeSubscription(table: 'party')],
        onChange: () {},
      );
      final b = RealtimeWatcher.tryCreate(
        channelName: 'b',
        subscriptions: const [RealtimeSubscription(table: 'party')],
        onChange: () {},
      );
      expect(a, isNull);
      expect(b, isNull);
    });
  });

  group('realtimeEq', () {
    test('builds an eq filter on (column, value)', () {
      final filter = realtimeEq('shop_id', 'shop-abc');
      expect(filter.column, 'shop_id');
      expect(filter.value, 'shop-abc');
    });
  });
}
