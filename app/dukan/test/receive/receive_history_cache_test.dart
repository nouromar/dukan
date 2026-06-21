// ReceiveHistoryCache unit tests. ReceiveSummary is a typedef
// alias for SaleSummary so the round-trip shape is identical.

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/receive/receive_history_cache.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';

ReceiveSummary _receive(String id, {double total = 80}) => ReceiveSummary(
      txnId: id,
      occurredAt: DateTime.utc(2026, 6, 21, 10, 0, 0),
      postedAt: DateTime.utc(2026, 6, 21, 10, 0, 1),
      partyId: 'sup-1',
      partyName: 'Hassan',
      totalAmount: total,
      paidAmount: total,
      paymentMethodCode: 'cash',
      isVoided: false,
      reversalTxnId: null,
      voidedAt: null,
    );

void main() {
  test('get returns null when nothing cached', () async {
    expect(await ReceiveHistoryCache.get('shop-1'), isNull);
  });

  test('put + get round-trips the values', () async {
    await ReceiveHistoryCache.put('shop-1', [_receive('r1'), _receive('r2')]);
    final got = await ReceiveHistoryCache.get('shop-1');
    expect(got, isNotNull);
    expect(got!.length, 2);
    expect(got.first.txnId, 'r1');
    expect(got.first.partyName, 'Hassan');
  });

  test('cache is per-shop', () async {
    await ReceiveHistoryCache.put('shop-1', [_receive('r1')]);
    await ReceiveHistoryCache.put('shop-2', const <ReceiveSummary>[]);
    expect((await ReceiveHistoryCache.get('shop-1'))!.length, 1);
    expect((await ReceiveHistoryCache.get('shop-2'))!.length, 0);
  });

  test('invalidate removes the entry', () async {
    await ReceiveHistoryCache.put('shop-1', [_receive('r1')]);
    await ReceiveHistoryCache.invalidate('shop-1');
    expect(await ReceiveHistoryCache.get('shop-1'), isNull);
  });

  test('corrupt JSON drops the row and returns null', () async {
    final dao = CacheDao(AppDatabase.instance());
    await dao.put('receive_history:shop-1', 'not a json array');
    expect(await ReceiveHistoryCache.get('shop-1'), isNull);
  });
}
