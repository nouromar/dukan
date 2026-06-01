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
    api.onSearchItems = (_, _, _, screen, _, _) async {
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
    api.onSearchItems = (_, _, _, _, _, _) async => [
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
    api.onSearchItems = (_, _, _, _, _, _) async => [
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
    api.onSearchItems = (_, _, _, _, _, _) async => [
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
    api.onSearchItems = (_, _, _, _, _, _) async => [
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
    api.onSearchItems = (_, _, _, _, _, _) async => [
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
    api.onSearchItems = (_, _, _, _, _, _) async => [
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
    api.onSearchItems = (_, _, _, _, _, _) async => [
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
    api.onSearchItems = (_, _, _, _, _, _) async => List.generate(
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
    api.onSearchItems = (_, _, _, _, _, _) async => const [];

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
    api.onSearchItems = (_, _, _, _, _, _) async => [
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

  // --- Line editor wiring (no-price + long-press) -----------------------

  testWidgets('tile shows — for items with no usable sale price (null)', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(name: 'Free Sample', salePrice: null),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();

    // Find the tile text that shows unit + price separator.
    expect(find.textContaining('—'), findsOneWidget);
  });

  testWidgets('tile shows — for items with sale_price = 0', (tester) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(name: 'Zero Priced', salePrice: 0),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('—'), findsOneWidget);
  });

  testWidgets('tapping a no-price item opens the editor (not fast-add)', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(name: 'Free Sample', salePrice: null),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Free Sample'));
    await tester.pumpAndSettle();

    // Editor sheet should be on screen and cart still empty.
    expect(find.text(en.lineEditorPriceRequiredHelper), findsOneWidget);
    expect(cart.isEmpty, isTrue);

    // Enter a price + confirm → line lands in the cart.
    await tester.enterText(find.byType(TextField).last, '3.5');
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, en.lineEditorDoneButton),
    );
    await tester.pumpAndSettle();

    expect(cart.itemCount, 1);
    expect(cart.lines.values.first.unitPrice, 3.5);
  });

  testWidgets('long-press on a priced tile opens the editor pre-filled', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(name: 'Bariis', salePrice: 1.5),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Bariis'));
    await tester.pumpAndSettle();

    // DONE should be enabled because the price field is pre-filled with
    // the item's own sale price.
    final done = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, en.lineEditorDoneButton),
    );
    expect(done.onPressed, isNotNull);

    // Bump qty to 3, confirm.
    await tester.tap(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, en.lineEditorDoneButton),
    );
    await tester.pumpAndSettle();

    expect(cart.itemCount, 3);
    expect(cart.lines.values.first.unitPrice, 1.5);
  });

  testWidgets(
    'SAVE persists editor-entered prices via setItemSalePrice for each editor line',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(itemId: 'i1', name: 'Bariis', salePrice: 1.5),
        // No-price item — tapping it routes through the editor.
        fakeActivatedItem(itemId: 'i2', name: 'Rooti', salePrice: 0),
      ];
      api.onPostSale = (_, _, _, _, _, _, _) async => 'fake-txn';

      await pumpSale(tester);
      await tester.pumpAndSettle();

      // Fast-path add on the priced tile.
      await tester.tap(find.text('Bariis'));
      await tester.pumpAndSettle();

      // Tap the no-price tile → editor opens; enter a price.
      await tester.tap(find.text('Rooti'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '0.25');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, en.lineEditorDoneButton),
      );
      await tester.pumpAndSettle();

      // SAVE the sale.
      await tester.tap(find.widgetWithText(FilledButton, en.saleSaveButton));
      await tester.pumpAndSettle();

      // Only the editor-entered line should trigger setItemSalePrice.
      expect(api.setItemSalePriceCalls, hasLength(1));
      expect(api.setItemSalePriceCalls.first.itemId, 'i2');
      expect(api.setItemSalePriceCalls.first.salePrice, 0.25);
    },
  );

  testWidgets(
    'SAVE swallows a setItemSalePrice failure without surfacing an error',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(itemId: 'i1', name: 'Rooti', salePrice: 0),
      ];
      api.onPostSale = (_, _, _, _, _, _, _) async => 'fake-txn';
      api.onSetItemSalePrice = (_, _, _) async {
        throw Exception('boom');
      };

      await pumpSale(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rooti'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '0.25');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, en.lineEditorDoneButton),
      );
      await tester.pumpAndSettle();

      // FlutterError will report through this zone — silence so the
      // test passes even though the SAVE flow logs the failure.
      FlutterError.onError = (_) {};

      await tester.tap(find.widgetWithText(FilledButton, en.saleSaveButton));
      await tester.pumpAndSettle();

      // The "Saved" toast is still shown — the sale was posted, the
      // failure is in the secondary price write-back which is non-fatal.
      expect(find.text(en.saleSavedToast), findsWidgets);
      expect(find.text(en.salePostFailedMessage), findsNothing);
    },
  );

  testWidgets('long-press on a cart row opens editor and updates the line', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(itemId: 'i1', name: 'Bariis', salePrice: 1.5),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis'));
    await tester.pumpAndSettle();

    // Open the drawer so the row is hittable.
    await tester.tap(find.text(en.saleCartSummary(1, '\$1.50')));
    await tester.pumpAndSettle();

    // Long-press the cart line (find the ListTile by its subtitle).
    final lineTile = find.ancestor(
      of: find.text(en.cartLineSubtotal('1', '\$1.50', '\$1.50')),
      matching: find.byType(ListTile),
    );
    await tester.longPress(lineTile);
    await tester.pumpAndSettle();

    // Change qty to 5, price stays at 1.5.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byIcon(Icons.add));
    }
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, en.lineEditorDoneButton),
    );
    await tester.pumpAndSettle();

    expect(cart.itemCount, 5);
    expect(cart.lines.values.first.unitPrice, 1.5);
  });

  testWidgets('cart state survives Navigator push/pop', (tester) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
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
