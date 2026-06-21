// PartiesCache unit tests — covers per-shop + per-type keying.

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/parties/parties_cache.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';

const _ahmed = PartySearchResult(
  id: 'cust-1',
  name: 'Ahmed',
  phone: '+252612345678',
  typeCode: 'customer',
  receivable: 40,
  payable: 0,
);

const _hassan = PartySearchResult(
  id: 'sup-1',
  name: 'Hassan',
  phone: null,
  typeCode: 'supplier',
  receivable: 0,
  payable: 120,
);

void main() {
  test('get returns null when nothing cached', () async {
    expect(await PartiesCache.get('shop-1', 'customer'), isNull);
  });

  test('put + get round-trips the values', () async {
    await PartiesCache.put('shop-1', 'customer', [_ahmed]);
    final got = await PartiesCache.get('shop-1', 'customer');
    expect(got, isNotNull);
    expect(got!.first.id, _ahmed.id);
    expect(got.first.receivable, _ahmed.receivable);
    expect(got.first.phone, _ahmed.phone);
  });

  test('customer and supplier are keyed separately', () async {
    await PartiesCache.put('shop-1', 'customer', [_ahmed]);
    await PartiesCache.put('shop-1', 'supplier', [_hassan]);
    final customers = await PartiesCache.get('shop-1', 'customer');
    final suppliers = await PartiesCache.get('shop-1', 'supplier');
    expect(customers!.single.id, 'cust-1');
    expect(suppliers!.single.id, 'sup-1');
  });

  test('invalidateAll drops both customer + supplier caches', () async {
    await PartiesCache.put('shop-1', 'customer', [_ahmed]);
    await PartiesCache.put('shop-1', 'supplier', [_hassan]);
    await PartiesCache.invalidateAll('shop-1');
    expect(await PartiesCache.get('shop-1', 'customer'), isNull);
    expect(await PartiesCache.get('shop-1', 'supplier'), isNull);
  });

  test('corrupt JSON drops the row and returns null', () async {
    final dao = CacheDao(AppDatabase.instance());
    await dao.put('parties:shop-1:customer', 'not a json array');
    expect(await PartiesCache.get('shop-1', 'customer'), isNull);
  });
}
