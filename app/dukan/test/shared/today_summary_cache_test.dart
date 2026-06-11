import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/shared/today_summary_cache.dart';

const _sample = TodaySummary(
  salesToday: 123.45,
  receivablesTotal: 50,
  payablesTotal: 75,
  lowStockCount: 4,
);

void main() {
  test('get returns null when nothing cached for the shop', () async {
    expect(await TodaySummaryCache.get('shop-1'), isNull);
  });

  test('put then get round-trips the values', () async {
    await TodaySummaryCache.put('shop-1', _sample);
    final got = await TodaySummaryCache.get('shop-1');
    expect(got, isNotNull);
    expect(got!.salesToday, _sample.salesToday);
    expect(got.receivablesTotal, _sample.receivablesTotal);
    expect(got.payablesTotal, _sample.payablesTotal);
    expect(got.lowStockCount, _sample.lowStockCount);
  });

  test('cache is per-shop', () async {
    await TodaySummaryCache.put('shop-1', _sample);
    await TodaySummaryCache.put(
      'shop-2',
      const TodaySummary(
        salesToday: 99,
        receivablesTotal: 0,
        payablesTotal: 0,
        lowStockCount: 0,
      ),
    );
    final a = await TodaySummaryCache.get('shop-1');
    final b = await TodaySummaryCache.get('shop-2');
    expect(a!.salesToday, 123.45);
    expect(b!.salesToday, 99);
  });

  test('corrupt JSON is dropped silently and returns null', () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'today_summary:shop-1': 'not json'},
    );
    expect(await TodaySummaryCache.get('shop-1'), isNull);
    // Subsequent reads also return null (the cache entry was removed).
    expect(await TodaySummaryCache.get('shop-1'), isNull);
  });
}
