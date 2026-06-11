// Verifies the optimistic SAVE contract on the Sale screen: the cart
// clears synchronously before postSale resolves, and on failure the
// snapshot is restored so the cashier can retry.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/sale/cart_controller.dart';
import 'package:dukan/sale/sale_screen.dart';

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
    'cart clears synchronously before postSale completes',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-rice',
          itemId: 'item-rice',
          defaultShopItemUnitId: 'siu-rice',
          displayName: 'Bariis Basmati',
          defaultUnitSalePrice: 1.5,
        ),
      ];
      // Stall postSale so we can observe the cart state mid-flight.
      final postCompleter = Completer<String>();
      api.onPostSale = (_, _, _, _, _, _, _) => postCompleter.future;

      await pumpSale(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bariis Basmati'));
      await tester.pumpAndSettle();
      expect(cart.isNotEmpty, isTrue,
          reason: 'sanity check: tap should have added a line');

      // Tap SAVE — postSale is still pending, but the cart must already
      // be empty because the optimistic clear runs synchronously.
      await tester.tap(find.text(en.saleSaveButton));
      await tester.pump();
      expect(cart.isEmpty, isTrue,
          reason: 'cart must clear before postSale resolves');

      // Let postSale complete so the test can teardown cleanly.
      postCompleter.complete('txn-1');
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'failed postSale restores the snapshot to the cart',
    (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (_) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-rice',
          itemId: 'item-rice',
          defaultShopItemUnitId: 'siu-rice',
          displayName: 'Bariis Basmati',
          defaultUnitSalePrice: 1.5,
        ),
      ];
      api.onPostSale =
          (_, _, _, _, _, _, _) async => throw StateError('network down');

      await pumpSale(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bariis Basmati'));
      await tester.pumpAndSettle();
      expect(cart.lines, hasLength(1));

      await tester.tap(find.text(en.saleSaveButton));
      await tester.pumpAndSettle();

      // Snapshot restored: the line is back in the cart.
      expect(cart.lines, hasLength(1));
      expect(cart.lines.values.first.shopItemUnitId, 'siu-rice');
      expect(find.text(en.salePostFailedMessage), findsOneWidget);
    },
  );
}
