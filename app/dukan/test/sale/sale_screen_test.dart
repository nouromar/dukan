import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post_store.dart';
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
        fakeActivatedItem(
          shopItemId: 'si-rice',
          itemId: 'item-rice',
          defaultShopItemUnitId: 'siu-rice',
          displayName: 'Bariis Basmati',
          defaultUnitSalePrice: 1.5,
        ),
        fakeActivatedItem(
          shopItemId: 'si-sugar',
          itemId: 'item-sugar',
          defaultShopItemUnitId: 'siu-sugar',
          displayName: 'Sonkor',
          defaultUnitSalePrice: 1.0,
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
      fakeActivatedItem(
        shopItemId: 'si-rice',
        itemId: 'item-rice',
        defaultShopItemUnitId: 'siu-rice',
        displayName: 'Bariis Basmati',
        defaultUnitSalePrice: 1.5,
      ),
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
      fakeActivatedItem(
        shopItemId: 'si-rice',
        itemId: 'item-rice',
        defaultShopItemUnitId: 'siu-rice',
        displayName: 'Bariis Basmati',
        defaultUnitSalePrice: 1.5,
      ),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bariis Basmati'));
    await tester.tap(find.text('Bariis Basmati'));
    await tester.pumpAndSettle();

    // itemCount is now line count (1) regardless of qty (2).
    expect(
      find.text(en.saleCartSummary(1, '\$3.00')),
      findsOneWidget,
    );
  });

  testWidgets('SAVE is disabled with an empty cart', (tester) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(displayName: 'Bariis Basmati'),
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
        shopItemId: 'si-rice',
        itemId: 'item-rice',
        defaultShopItemUnitId: 'siu-rice',
        displayName: 'Bariis Basmati',
        baseUnitCode: 'kg',
        defaultUnitSalePrice: 1.5,
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
    expect(lines.first.shopItemUnitId, 'siu-rice');
    expect(lines.first.quantity, 1);
    expect(lines.first.unitPrice, 1.5);
  });

  testWidgets(
    'SAVE clears the cart on success and opens the receipt sheet',
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
      api.onPostSale = (_, _, _, _, _, _, _) async => 'fake-txn';
      // The receipt sheet fetches the freshly-posted sale; stub so it
      // can render.
      api.onGetSale = (_, txnId) async => SaleSummary(
            txnId: txnId,
            occurredAt: DateTime(2026, 6, 6, 14, 0),
            postedAt: DateTime(2026, 6, 6, 14, 0),
            partyId: null,
            partyName: null,
            totalAmount: 1.5,
            paidAmount: 1.5,
            paymentMethodCode: 'cash',
            isVoided: false,
            reversalTxnId: null,
            voidedAt: null,
          );
      api.onGetSaleLines = (_, _) async => const [];

      await pumpSale(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bariis Basmati'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, en.saleSaveButton));
      // Walk through:
      //   pump 1: postFrameCallback fires → showModalBottomSheet
      //   pump 2-4: route animates in
      //   pump 5: sheet's _load microtask completes
      //   pump 6: FutureBuilder rebuilds with data
      // CircularProgressIndicator runs a ticker indefinitely, so we
      // can't pumpAndSettle here.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text(en.saleCartSummary(0, '\$0.00')), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, en.saleReceiptDoneButton),
        findsOneWidget,
      );
      expect(find.text(en.saleReceiptShareButton), findsOneWidget);
    },
  );

  // --- Cart drawer (expandable inline lines) ---------------------------------

  testWidgets('cart drawer auto-expands on add; tap summary toggles', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(
        shopItemId: 'si-rice',
        itemId: 'item-rice',
        defaultShopItemUnitId: 'siu-rice',
        displayName: 'Bariis Basmati',
        defaultUnitSalePrice: 1.5,
      ),
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
    await tester.tap(find.text('Bariis Basmati'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sonkor'));
    await tester.pumpAndSettle();

    // Auto-expanded after the first add — both line subtotals visible.
    expect(
      find.text(en.cartLineSubtotal('1', '\$1.50', '\$1.50')),
      findsOneWidget,
    );
    expect(
      find.text(en.cartLineSubtotal('1', '\$1.00', '\$1.00')),
      findsOneWidget,
    );

    // Tapping the summary collapses; tapping again re-expands.
    await tester.tap(find.text(en.saleCartSummary(2, '\$2.50')));
    await tester.pumpAndSettle();
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
  });

  testWidgets('tapping ✕ on a cart line removes it and updates the summary', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(
        shopItemId: 'si-rice',
        itemId: 'item-rice',
        defaultShopItemUnitId: 'siu-rice',
        displayName: 'Bariis Basmati',
        defaultUnitSalePrice: 1.5,
      ),
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
    await tester.tap(find.text('Bariis Basmati'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sonkor'));
    await tester.pumpAndSettle();

    // Auto-expanded after first add; no summary tap needed.

    final sonkorRemove = find.descendant(
      of: find.ancestor(
        of: find.text(en.cartLineSubtotal('1', '\$1.00', '\$1.00')),
        matching: find.byType(ListTile),
      ),
      matching: find.byIcon(Icons.close),
    );
    await tester.tap(sonkorRemove);
    await tester.pumpAndSettle();

    expect(find.text(en.saleCartSummary(1, '\$1.50')), findsOneWidget);
    expect(find.text(en.cartLineSubtotal('1', '\$1.00', '\$1.00')), findsNothing);
  });

  testWidgets('SAVE button stays visible even with many cart lines', (
    tester,
  ) async {
    // Pre-load 8 lines via the controller so we don't have to scroll
    // the 2-col grid into view for each tile tap. The drawer should
    // scroll internally while SAVE remains visible at the bottom.
    for (var i = 0; i < 8; i++) {
      cart.addItem(
        fakeActivatedItem(
          shopItemId: 'si-$i',
          itemId: 'item-$i',
          defaultShopItemUnitId: 'siu-$i',
          displayName: 'Item $i',
          defaultUnitSalePrice: 1.0,
        ),
      );
    }
    api.onSearchItems = (_, _, _, _, _, _) async => const [];

    await pumpSale(tester);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, en.saleSaveButton), findsOneWidget);
  });

  // --- Persistence + Clear all + auto-expand ---------------------------------

  testWidgets('cart auto-expands when entering Sale with a non-empty cart', (
    tester,
  ) async {
    // Simulate a previously-built cart sitting in the controller.
    cart.addItem(
      fakeActivatedItem(
        shopItemId: 'si-1',
        itemId: 'i1',
        defaultShopItemUnitId: 'siu-1',
        displayName: 'Bariis',
        defaultUnitSalePrice: 1.5,
      ),
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
      fakeActivatedItem(
        shopItemId: 'si-1',
        itemId: 'i1',
        defaultShopItemUnitId: 'siu-1',
        displayName: 'Bariis',
        defaultUnitSalePrice: 1.5,
      ),
      fakeActivatedItem(
        shopItemId: 'si-2',
        itemId: 'i2',
        defaultShopItemUnitId: 'siu-2',
        displayName: 'Sonkor',
        defaultUnitSalePrice: 1.0,
      ),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sonkor'));
    await tester.pumpAndSettle();

    // Cart auto-expanded after first add — Clear all is already rendered.

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
    expect(find.text(en.saleCartSummary(0, '\$0.00')), findsOneWidget);
  });

  // --- Line editor wiring (no-price + long-press) -----------------------

  testWidgets('tile shows — for items with no usable sale price (null)', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(displayName: 'Free Sample', defaultUnitSalePrice: null),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();

    // Find the tile text that shows unit + price separator.
    expect(find.textContaining('—'), findsOneWidget);
  });

  testWidgets('tile shows — for items with sale_price = 0', (tester) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(displayName: 'Zero Priced', defaultUnitSalePrice: 0),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('—'), findsOneWidget);
  });

  testWidgets('tapping a no-price item opens the editor (not fast-add)', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(
        shopItemId: 'si-1',
        itemId: 'i1',
        defaultShopItemUnitId: 'siu-1',
        displayName: 'Free Sample',
        defaultUnitSalePrice: null,
      ),
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
      fakeActivatedItem(
        shopItemId: 'si-1',
        itemId: 'i1',
        defaultShopItemUnitId: 'siu-1',
        displayName: 'Bariis',
        defaultUnitSalePrice: 1.5,
      ),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Bariis'));
    await tester.pumpAndSettle();

    // DONE should be enabled because the price field is pre-filled with
    // the packaging's stored sale price.
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

    expect(cart.itemCount, 1);
    expect(cart.lines.values.first.quantity, 3);
    expect(cart.lines.values.first.unitPrice, 1.5);
  });

  testWidgets(
    'SAVE persists editor-entered prices via setShopItemUnitSalePrice for each editor line',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-1',
          displayName: 'Bariis',
          defaultUnitSalePrice: 1.5,
        ),
        // No-price item — tapping it routes through the editor.
        fakeActivatedItem(
          shopItemId: 'si-2',
          itemId: 'i2',
          defaultShopItemUnitId: 'siu-2',
          displayName: 'Rooti',
          defaultUnitSalePrice: 0,
        ),
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

      // Only the editor-entered line should trigger setShopItemUnitSalePrice.
      expect(api.setShopItemUnitSalePriceCalls, hasLength(1));
      expect(api.setShopItemUnitSalePriceCalls.first.shopItemUnitId, 'siu-2');
      expect(api.setShopItemUnitSalePriceCalls.first.salePrice, 0.25);
    },
  );

  testWidgets(
    'SAVE swallows a setShopItemUnitSalePrice failure without surfacing an error',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-1',
          displayName: 'Rooti',
          defaultUnitSalePrice: 0,
        ),
      ];
      api.onPostSale = (_, _, _, _, _, _, _) async => 'fake-txn';
      api.onSetShopItemUnitSalePrice = (_, _, _) async {
        throw Exception('boom');
      };
      api.onGetSale = (_, txnId) async => SaleSummary(
            txnId: txnId,
            occurredAt: DateTime(2026, 6, 6, 14, 0),
            postedAt: DateTime(2026, 6, 6, 14, 0),
            partyId: null,
            partyName: null,
            totalAmount: 0.25,
            paidAmount: 0.25,
            paymentMethodCode: 'cash',
            isVoided: false,
            reversalTxnId: null,
            voidedAt: null,
          );
      api.onGetSaleLines = (_, _) async => const [];

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
      // Drive frames manually — receipt sheet's CPI never settles.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Sale posted (receipt sheet visible); the write-back failure
      // never surfaces a user-facing error toast.
      expect(
        find.widgetWithText(FilledButton, en.saleReceiptDoneButton),
        findsOneWidget,
      );
      expect(find.text(en.salePostFailedMessage), findsNothing);
    },
  );

  testWidgets('tap on a cart row opens editor and updates the line', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(
        shopItemId: 'si-1',
        itemId: 'i1',
        defaultShopItemUnitId: 'siu-1',
        displayName: 'Bariis',
        defaultUnitSalePrice: 1.5,
      ),
    ];

    await pumpSale(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis'));
    await tester.pumpAndSettle();

    // Cart auto-expanded; the row is hittable directly. Tap opens the
    // editor (long-press was retired — too fiddly one-handed).
    final lineTile = find.ancestor(
      of: find.text(en.cartLineSubtotal('1', '\$1.50', '\$1.50')),
      matching: find.byType(ListTile),
    );
    await tester.tap(lineTile);
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

    // qty bumped to 5; itemCount stays 1 line (line count, not qty sum).
    expect(cart.itemCount, 1);
    expect(cart.lines.values.first.quantity, 5);
    expect(cart.lines.values.first.unitPrice, 1.5);
  });

  testWidgets('cart state survives Navigator push/pop', (tester) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(
        shopItemId: 'si-1',
        itemId: 'i1',
        defaultShopItemUnitId: 'siu-1',
        displayName: 'Bariis',
        defaultUnitSalePrice: 1.5,
      ),
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

  // --- Server-reject branch (PostgrestException) -----------------------
  //
  // Sale.SAVE is optimistic: it clears the cart and posts in the
  // background. The two failure modes must diverge:
  //   - Network / transient → enqueue to OfflineQueueController.
  //   - Server validation reject (PostgrestException) → restore the
  //     cart snapshot, show an error, NEVER queue (retry would fail
  //     the same way).
  // The two tests below pin both halves of that contract.

  testWidgets(
    'PostgrestException restores the cart and does NOT enqueue',
    (tester) async {
      // Background-reported errors are part of the contract — the
      // screen calls FlutterError.reportError on its own catches.
      // Silence them here so the test asserts on observable state.
      FlutterError.onError = (_) {};

      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-rice',
          itemId: 'item-rice',
          defaultShopItemUnitId: 'siu-rice',
          displayName: 'Bariis',
          baseUnitCode: 'kg',
          defaultUnitSalePrice: 1.5,
        ),
      ];
      api.onPostSale = (_, _, _, _, _, _, _) async =>
          throw const PostgrestException(
            message: 'Negative stock',
            code: '23514',
          );

      final queue = OfflineQueueController(
        store: PendingPostStore(),
        executor: (_) async {},
        backoff: (_) => Duration.zero,
      );

      await tester.pumpWidget(
        wrapWithApp(
          SaleScreen(shop: shop),
          authController: auth,
          shopApi: api,
          cartController: cart,
          offlineQueueController: queue,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bariis'));
      await tester.pumpAndSettle();
      expect(cart.itemCount, 1);

      await tester.tap(find.widgetWithText(FilledButton, en.saleSaveButton));
      await tester.pumpAndSettle();

      // Cart restored from snapshot.
      expect(cart.itemCount, 1);
      // Error message visible.
      expect(find.text(en.salePostFailedMessage), findsOneWidget);
      // Crucially: nothing was queued. Retrying a 23514 would fail again.
      expect(queue.pendingCount, 0);
    },
  );

  testWidgets(
    'transient (non-Postgrest) exception clears the cart AND enqueues',
    (tester) async {
      FlutterError.onError = (_) {};

      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-rice',
          itemId: 'item-rice',
          defaultShopItemUnitId: 'siu-rice',
          displayName: 'Bariis',
          baseUnitCode: 'kg',
          defaultUnitSalePrice: 1.5,
        ),
      ];
      api.onPostSale = (_, _, _, _, _, _, _) async =>
          throw Exception('connection reset');

      // Capture-and-succeed executor: the drain finishes cleanly (no
      // leaked retry timer) and we observe that the post DID flow
      // through the queue.
      final drainedPosts = <Object>[];
      final queue = OfflineQueueController(
        store: PendingPostStore(),
        executor: (post) async => drainedPosts.add(post),
        backoff: (_) => Duration.zero,
      );

      await tester.pumpWidget(
        wrapWithApp(
          SaleScreen(shop: shop),
          authController: auth,
          shopApi: api,
          cartController: cart,
          offlineQueueController: queue,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bariis'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, en.saleSaveButton));
      await tester.pumpAndSettle();

      // Cart stayed cleared (the queue owns the work now).
      expect(cart.itemCount, 0);
      // Exactly one post flowed through the queue's executor.
      expect(drainedPosts, hasLength(1));
    },
  );

}
