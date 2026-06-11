// Confirms the cache-fast-path: when FavoritesCache is warm for the
// blank query, the Sale screen renders the cached rows BEFORE
// searchItems resolves. Mirrors the production flow: Home prefetches,
// cashier taps Sale, tiles render instantly.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/sale/cart_controller.dart';
import 'package:dukan/sale/sale_screen.dart';
import 'package:dukan/shared/favorites_cache.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late CartController cart;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    cart = CartController();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
    FavoritesCache.clear();
    FavoritesCache.nowForTesting = null;
  });

  tearDown(() {
    FavoritesCache.clear();
    FavoritesCache.nowForTesting = null;
  });

  Future<void> pumpSale(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        SaleScreen(shop: shop),
        authController: auth,
        shopApi: api,
        cartController: cart,
      ),
    );
  }

  testWidgets(
    'warm cache renders favorites before searchItems resolves',
    (tester) async {
      // Pre-warm the cache as if Home had already prefetched.
      FavoritesCache.put(shop.id, 'sale', [
        fakeActivatedItem(
          shopItemId: 'si-rice',
          itemId: 'item-rice',
          defaultShopItemUnitId: 'siu-rice',
          displayName: 'Bariis Basmati',
          defaultUnitSalePrice: 1.5,
        ),
      ]);
      // Stall any real searchItems call so we can prove the render
      // came from the cache, not the network.
      final neverResolves = Completer<List<ItemSearchResult>>();
      api.onSearchItems =
          (_, _, _, _, _, _) => neverResolves.future;

      await pumpSale(tester);
      // Just one pump — no settle. The cache fast-path resolves
      // synchronously, so the tile should already be findable.
      await tester.pump();

      expect(find.text('Bariis Basmati'), findsOneWidget,
          reason: 'cached favorite must render without awaiting the RPC');

      // Cleanly teardown the stalled future.
      neverResolves.complete(const <ItemSearchResult>[]);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'cold cache falls back to network and caches the result',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-sugar',
          itemId: 'item-sugar',
          defaultShopItemUnitId: 'siu-sugar',
          displayName: 'Sonkor',
          defaultUnitSalePrice: 1.0,
        ),
      ];

      await pumpSale(tester);
      await tester.pumpAndSettle();

      expect(find.text('Sonkor'), findsOneWidget);
      final cached = FavoritesCache.get(shop.id, 'sale');
      expect(cached, isNotNull);
      expect(cached!.single.shopItemId, 'si-sugar');
      // Defeat unused-local warning while keeping setUp readable.
      expect(en.saleSaveButton, isNotEmpty);
    },
  );
}
