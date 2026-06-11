import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/shared/favorites_cache.dart';

import 'fakes.dart';

ItemSearchResult _item(String id) => fakeActivatedItem(
      shopItemId: id,
      itemId: id,
      defaultShopItemUnitId: '$id-unit',
      displayName: 'Item $id',
      defaultUnitSalePrice: 1,
    );

void main() {
  setUp(() {
    FavoritesCache.clear();
    FavoritesCache.nowForTesting = null;
  });

  test('get returns null when nothing cached', () {
    expect(FavoritesCache.get('s1', 'sale'), isNull);
    expect(FavoritesCache.isStale('s1', 'sale'), isTrue);
  });

  test('put then get returns the same list', () {
    FavoritesCache.put('s1', 'sale', [_item('a'), _item('b')]);
    final got = FavoritesCache.get('s1', 'sale');
    expect(got, isNotNull);
    expect(got!.map((i) => i.shopItemId).toList(), ['a', 'b']);
  });

  test('fresh entries are not stale', () {
    FavoritesCache.put('s1', 'sale', [_item('a')]);
    expect(FavoritesCache.isStale('s1', 'sale'), isFalse);
  });

  test('entries older than 30s are stale (but still readable)', () {
    DateTime now = DateTime(2026, 6, 11, 12, 0, 0);
    FavoritesCache.nowForTesting = () => now;
    FavoritesCache.put('s1', 'sale', [_item('a')]);
    now = now.add(const Duration(seconds: 45));
    expect(FavoritesCache.isStale('s1', 'sale'), isTrue);
    expect(FavoritesCache.get('s1', 'sale'), isNotNull,
        reason: 'stale entries should still be readable for instant-render');
  });

  test('cache is scoped per (shop, screen)', () {
    FavoritesCache.put('s1', 'sale', [_item('a')]);
    FavoritesCache.put('s1', 'receive', [_item('b')]);
    FavoritesCache.put('s2', 'sale', [_item('c')]);
    expect(FavoritesCache.get('s1', 'sale')!.first.shopItemId, 'a');
    expect(FavoritesCache.get('s1', 'receive')!.first.shopItemId, 'b');
    expect(FavoritesCache.get('s2', 'sale')!.first.shopItemId, 'c');
  });

  test('clear empties everything', () {
    FavoritesCache.put('s1', 'sale', [_item('a')]);
    FavoritesCache.put('s2', 'receive', [_item('b')]);
    FavoritesCache.clear();
    expect(FavoritesCache.get('s1', 'sale'), isNull);
    expect(FavoritesCache.get('s2', 'receive'), isNull);
  });
}
