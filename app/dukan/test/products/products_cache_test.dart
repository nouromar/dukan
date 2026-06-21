// ProductsCache unit tests — mirror today_summary_cache_test
// shape. flutter_test_config seeds a fresh in-memory AppDatabase
// per test so the static cache talks to real sqflite via the
// singleton.

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/products/products_cache.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';

ShopItemSummary _rice = const ShopItemSummary(
  shopItemId: 'si-1',
  itemId: 'item-1',
  displayName: 'Bariis',
  categoryName: 'Staples',
  baseUnitCode: 'kg',
  baseUnitLabel: 'Kg',
  currentStock: 12.5,
  reorderThreshold: 5,
  unitCount: 2,
  isActive: true,
  defaultSalePrice: 1.50,
  anyPriceSet: true,
);

void main() {
  test('get returns null when nothing cached for the shop', () async {
    expect(await ProductsCache.get('shop-1'), isNull);
  });

  test('put then get round-trips the values', () async {
    await ProductsCache.put('shop-1', [_rice]);
    final got = await ProductsCache.get('shop-1');
    expect(got, isNotNull);
    expect(got!.length, 1);
    expect(got.first.shopItemId, _rice.shopItemId);
    expect(got.first.displayName, _rice.displayName);
    expect(got.first.currentStock, _rice.currentStock);
    expect(got.first.defaultSalePrice, _rice.defaultSalePrice);
    expect(got.first.anyPriceSet, _rice.anyPriceSet);
  });

  test('cache is per-shop', () async {
    await ProductsCache.put('shop-1', [_rice]);
    await ProductsCache.put('shop-2', const <ShopItemSummary>[]);
    expect((await ProductsCache.get('shop-1'))!.length, 1);
    expect((await ProductsCache.get('shop-2'))!.length, 0);
  });

  test('invalidate removes the cached entry', () async {
    await ProductsCache.put('shop-1', [_rice]);
    expect(await ProductsCache.get('shop-1'), isNotNull);
    await ProductsCache.invalidate('shop-1');
    expect(await ProductsCache.get('shop-1'), isNull);
  });

  test('corrupt JSON drops the row and returns null', () async {
    final dao = CacheDao(AppDatabase.instance());
    await dao.put('products:shop-1', 'not a json array');
    expect(await ProductsCache.get('shop-1'), isNull);
    // Subsequent reads also return null — corrupt row was removed.
    expect(await ProductsCache.get('shop-1'), isNull);
  });
}
