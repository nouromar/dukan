// SaleHistoryCache unit tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/sale/sale_history_cache.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';

SaleSummary _sale(String id, {double total = 50, bool voided = false}) =>
    SaleSummary(
      txnId: id,
      occurredAt: DateTime.utc(2026, 6, 21, 12, 0, 0),
      postedAt: DateTime.utc(2026, 6, 21, 12, 0, 1),
      partyId: 'cust-1',
      partyName: 'Ahmed',
      totalAmount: total,
      paidAmount: voided ? 0 : total,
      paymentMethodCode: 'cash',
      isVoided: voided,
      reversalTxnId: voided ? 'rev-$id' : null,
      voidedAt: voided ? DateTime.utc(2026, 6, 21, 13, 0, 0) : null,
    );

void main() {
  test('get returns null when nothing cached', () async {
    expect(await SaleHistoryCache.get('shop-1'), isNull);
  });

  test('put + get round-trips the values', () async {
    await SaleHistoryCache.put('shop-1', [_sale('s1'), _sale('s2')]);
    final got = await SaleHistoryCache.get('shop-1');
    expect(got, isNotNull);
    expect(got!.length, 2);
    expect(got.first.txnId, 's1');
    expect(got.last.txnId, 's2');
    expect(got.first.totalAmount, 50);
  });

  test('voided sale round-trips with reversalTxnId + voidedAt', () async {
    await SaleHistoryCache.put('shop-1', [_sale('s1', voided: true)]);
    final got = await SaleHistoryCache.get('shop-1');
    expect(got!.single.isVoided, isTrue);
    expect(got.single.reversalTxnId, 'rev-s1');
    expect(got.single.voidedAt, isNotNull);
  });

  test('invalidate removes the entry', () async {
    await SaleHistoryCache.put('shop-1', [_sale('s1')]);
    await SaleHistoryCache.invalidate('shop-1');
    expect(await SaleHistoryCache.get('shop-1'), isNull);
  });

  test('corrupt JSON drops the row and returns null', () async {
    final dao = CacheDao(AppDatabase.instance());
    await dao.put('sale_history:shop-1', 'not a json array');
    expect(await SaleHistoryCache.get('shop-1'), isNull);
  });
}
