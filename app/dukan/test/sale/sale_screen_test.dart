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

  testWidgets('shows favorites returned by the sale-screen search', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, screen, _) async {
      expect(screen, 'sale');
      return [
        fakeActivatedItem(name: 'Bariis Basmati', salePrice: 1.5),
        fakeActivatedItem(
          itemId: 'item-sugar',
          name: 'Sonkor',
          salePrice: 1.0,
        ),
      ];
    };

    await pumpSale(tester);
    await tester.pumpAndSettle();

    expect(find.text('Bariis Basmati'), findsOneWidget);
    expect(find.text('Sonkor'), findsOneWidget);
  });

  testWidgets('tapping an item adds it to the cart and updates the summary', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _) async => [
      fakeActivatedItem(name: 'Bariis Basmati', salePrice: 1.5),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bariis Basmati'));
    await tester.pumpAndSettle();

    expect(
      find.text(en.saleCartSummary(1, '\$1.50')),
      findsOneWidget,
    );
  });

  testWidgets('tapping the same item twice increments quantity', (tester) async {
    api.onSearchItems = (_, _, _, _, _) async => [
      fakeActivatedItem(name: 'Bariis Basmati', salePrice: 1.5),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bariis Basmati'));
    await tester.tap(find.text('Bariis Basmati'));
    await tester.pumpAndSettle();

    expect(
      find.text(en.saleCartSummary(2, '\$3')),
      findsOneWidget,
    );
  });

  testWidgets('SAVE is disabled with an empty cart', (tester) async {
    api.onSearchItems = (_, _, _, _, _) async => [
      fakeActivatedItem(name: 'Bariis Basmati'),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, en.saleSaveButton),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('cash sale calls post_sale with the cart and no party', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _) async => [
      fakeActivatedItem(
        itemId: 'item-rice',
        name: 'Bariis Basmati',
        baseUnitCode: 'kg',
        salePrice: 1.5,
      ),
    ];
    Map<String, dynamic>? capturedCall;
    api.onPostSale = (
      shopId,
      lines,
      paidAmount,
      partyId,
      paymentMethod,
      clientOpId,
      notes,
    ) async {
      capturedCall = {
        'shopId': shopId,
        'lines': lines,
        'paidAmount': paidAmount,
        'partyId': partyId,
        'paymentMethod': paymentMethod,
        'clientOpId': clientOpId,
      };
      return 'fake-txn';
    };

    await pumpSale(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis Basmati'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, en.saleSaveButton));
    await tester.pumpAndSettle();

    expect(capturedCall, isNotNull);
    expect(capturedCall!['shopId'], shop.id);
    expect(capturedCall!['partyId'], isNull);
    expect(capturedCall!['paymentMethod'], 'cash');
    expect(capturedCall!['paidAmount'], 1.5);
    final lines = capturedCall!['lines'] as List<SaleLine>;
    expect(lines, hasLength(1));
    expect(lines.first.itemId, 'item-rice');
    expect(lines.first.quantity, 1);
    expect(lines.first.unitPrice, 1.5);
    expect(lines.first.unitId, isNotEmpty);
  });

  testWidgets('SAVE clears the cart optimistically and shows the toast', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _) async => [
      fakeActivatedItem(name: 'Bariis Basmati', salePrice: 1.5),
    ];
    api.onPostSale = (_, _, _, _, _, _, _) async => 'fake-txn';

    await pumpSale(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis Basmati'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, en.saleSaveButton));
    await tester.pump(); // optimistic clear + SnackBar enqueued
    await tester.pumpAndSettle();

    expect(find.text(en.saleSavedToast), findsWidgets);
    expect(find.text(en.saleCartSummary(0, '\$0')), findsOneWidget);
  });

  // --- Cart drawer (expandable inline lines) ---------------------------------

  testWidgets('cart drawer is collapsed by default; tap summary expands it', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _) async => [
      fakeActivatedItem(itemId: 'item-rice', name: 'Bariis Basmati', salePrice: 1.5),
      fakeActivatedItem(itemId: 'item-sugar', name: 'Sonkor', salePrice: 1.0),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis Basmati'));
    await tester.tap(find.text('Sonkor'));
    await tester.pumpAndSettle();

    // Collapsed: the line subtotals aren't rendered yet.
    expect(
      find.text(en.cartLineSubtotal('1', '\$1.50', '\$1.50')),
      findsNothing,
    );

    await tester.tap(find.text(en.saleCartSummary(2, '\$2.50')));
    await tester.pumpAndSettle();

    expect(
      find.text(en.cartLineSubtotal('1', '\$1.50', '\$1.50')),
      findsOneWidget,
    );
    expect(
      find.text(en.cartLineSubtotal('1', '\$1', '\$1')),
      findsOneWidget,
    );
  });

  testWidgets('tapping ✕ on a cart line removes it and updates the summary', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _) async => [
      fakeActivatedItem(itemId: 'item-rice', name: 'Bariis Basmati', salePrice: 1.5),
      fakeActivatedItem(itemId: 'item-sugar', name: 'Sonkor', salePrice: 1.0),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis Basmati'));
    await tester.tap(find.text('Sonkor'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.saleCartSummary(2, '\$2.50')));
    await tester.pumpAndSettle();

    final sonkorRemove = find.descendant(
      of: find.ancestor(
        of: find.text(en.cartLineSubtotal('1', '\$1', '\$1')),
        matching: find.byType(ListTile),
      ),
      matching: find.byIcon(Icons.close),
    );
    await tester.tap(sonkorRemove);
    await tester.pumpAndSettle();

    expect(find.text(en.saleCartSummary(1, '\$1.50')), findsOneWidget);
    expect(find.text(en.cartLineSubtotal('1', '\$1', '\$1')), findsNothing);
  });

  testWidgets('SAVE button stays visible even with many cart lines', (
    tester,
  ) async {
    // Eight items to stress the cart list — the drawer should scroll
    // internally while SAVE remains visible at the bottom.
    api.onSearchItems = (_, _, _, _, _) async => List.generate(
      8,
      (i) => fakeActivatedItem(
        itemId: 'item-$i',
        name: 'Item $i',
        salePrice: 1.0,
      ),
    );

    await pumpSale(tester);
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.text('Item $i'));
    }
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.saleCartSummary(8, '\$8')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, en.saleSaveButton), findsOneWidget);
  });

  // --- Persistence + Clear all + auto-expand ---------------------------------

  testWidgets('cart auto-expands when entering Sale with a non-empty cart', (
    tester,
  ) async {
    // Simulate a previously-built cart sitting in the controller.
    cart.addItem(
      fakeActivatedItem(itemId: 'i1', name: 'Bariis', salePrice: 1.5),
    );
    api.onSearchItems = (_, _, _, _, _) async => const [];

    await pumpSale(tester);
    await tester.pumpAndSettle();

    // Drawer should be expanded — the line subtotal is visible without
    // any tap on the summary row.
    expect(
      find.text(en.cartLineSubtotal('1', '\$1.50', '\$1.50')),
      findsOneWidget,
    );
  });

  testWidgets('Clear all button confirms and wipes the cart', (tester) async {
    api.onSearchItems = (_, _, _, _, _) async => [
      fakeActivatedItem(itemId: 'i1', name: 'Bariis', salePrice: 1.5),
      fakeActivatedItem(itemId: 'i2', name: 'Sonkor', salePrice: 1.0),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis'));
    await tester.tap(find.text('Sonkor'));
    await tester.pumpAndSettle();

    // Open the drawer so Clear all is rendered.
    await tester.tap(find.text(en.saleCartSummary(2, '\$2.50')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.cartClearAllButton));
    await tester.pumpAndSettle();

    // Confirmation dialog appears with the right item count.
    expect(find.text(en.cartClearConfirmTitle(2)), findsOneWidget);

    // Cancel keeps the cart.
    await tester.tap(find.text(en.cartClearConfirmNo));
    await tester.pumpAndSettle();
    expect(cart.itemCount, 2);

    // Try again and confirm.
    await tester.tap(find.text(en.cartClearAllButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.cartClearConfirmYes));
    await tester.pumpAndSettle();

    expect(cart.isEmpty, isTrue);
    expect(find.text(en.saleCartSummary(0, '\$0')), findsOneWidget);
  });

  testWidgets('cart state survives Navigator push/pop', (tester) async {
    api.onSearchItems = (_, _, _, _, _) async => [
      fakeActivatedItem(itemId: 'i1', name: 'Bariis', salePrice: 1.5),
    ];

    // Stand-in host that pushes the Sale screen on tap.
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute(builder: (_) => SaleScreen(shop: shop)),
                ),
                child: const Text('open sale'),
              ),
            ),
          ),
        ),
        authController: auth,
        shopApi: api,
        cartController: cart,
      ),
    );

    // First entry: add an item.
    await tester.tap(find.text('open sale'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis'));
    await tester.pumpAndSettle();
    expect(cart.itemCount, 1);

    // Back to host.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('open sale'), findsOneWidget);

    // Re-enter: cart still has the item, drawer auto-expanded.
    await tester.tap(find.text('open sale'));
    await tester.pumpAndSettle();
    expect(cart.itemCount, 1);
    expect(
      find.text(en.cartLineSubtotal('1', '\$1.50', '\$1.50')),
      findsOneWidget,
    );
  });
}
