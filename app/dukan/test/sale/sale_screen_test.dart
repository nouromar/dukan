import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/sale/sale_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pumpSale(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        SaleScreen(shop: shop),
        authController: auth,
        shopApi: api,
      ),
    );
  }

  testWidgets('shows favorites returned by the sale-screen search', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, screen) async {
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
    api.onSearchItems = (_, _, _, _) async => [
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
    api.onSearchItems = (_, _, _, _) async => [
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
    api.onSearchItems = (_, _, _, _) async => [
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
    api.onSearchItems = (_, _, _, _) async => [
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
    api.onSearchItems = (_, _, _, _) async => [
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
}
