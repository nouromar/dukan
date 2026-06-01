import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/receive/receive_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

PartySearchResult _hassan() => const PartySearchResult(
  id: 'sup-1',
  name: 'Hassan',
  phone: null,
  typeCode: 'supplier',
  receivable: 0,
  payable: 0,
);

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late ReceiveController receive;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    receive = ReceiveController()..setSupplier(_hassan());
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pumpReceive(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        ReceiveScreen(shop: shop),
        authController: auth,
        shopApi: api,
        receiveController: receive,
      ),
    );
  }

  testWidgets('search_items is called with screen=receive + supplier party_id', (
    tester,
  ) async {
    String? capturedScreen;
    String? capturedParty;
    api.onSearchItems = (_, _, _, screen, _, partyId) async {
      capturedScreen = screen;
      capturedParty = partyId;
      return [];
    };

    await pumpReceive(tester);
    await tester.pumpAndSettle();

    expect(capturedScreen, 'receive');
    expect(capturedParty, 'sup-1');
  });

  testWidgets('tapping a tile fills the line form with qty=1 and pre-filled cost', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(
        itemId: 'i1',
        name: 'Bariis',
        baseUnitCode: 'kg',
        baseUnitLabel: 'Kg',
        lastCost: 4.5,
      ),
    ];

    await pumpReceive(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis'));
    await tester.pumpAndSettle();

    // Quantity defaulted to 1.
    expect(find.text('1'), findsWidgets);
    // Cost pre-filled from item.lastCost.
    expect(find.text('4.5'), findsOneWidget);
    // ADD LINE present.
    expect(find.text(en.receiveAddLineButton), findsOneWidget);
  });

  testWidgets('ADD LINE adds to the controller and clears the form', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(itemId: 'i1', name: 'Bariis', lastCost: 4),
    ];

    await pumpReceive(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis'));
    await tester.pumpAndSettle();

    // Edit qty to 5.
    await tester.enterText(
      find.widgetWithText(TextField, '1').first,
      '5',
    );
    await tester.pump();
    await tester.tap(find.text(en.receiveAddLineButton));
    await tester.pumpAndSettle();

    expect(receive.lineCount, 1);
    expect(receive.lines['i1']!.quantity, 5);
    expect(receive.lines['i1']!.unitCost, 4);
    // Form closes after ADD.
    expect(find.text(en.receiveAddLineButton), findsNothing);
  });

  testWidgets('SAVE calls postReceive with party + lines + paid', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(
        itemId: 'i1',
        name: 'Bariis',
        baseUnitCode: 'kg',
        lastCost: 4,
      ),
    ];
    Map<String, dynamic>? captured;
    api.onPostReceive = (
      shopId,
      partyId,
      lines,
      paidAmount,
      paymentMethod,
      documentId,
      clientOpId,
      notes,
    ) async {
      captured = {
        'shopId': shopId,
        'partyId': partyId,
        'lines': lines,
        'paidAmount': paidAmount,
        'paymentMethod': paymentMethod,
        'documentId': documentId,
        'clientOpId': clientOpId,
      };
      return 'fake-receive';
    };

    await pumpReceive(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.receiveAddLineButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.receiveSaveButton));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!['shopId'], shop.id);
    expect(captured!['partyId'], 'sup-1');
    final lines = captured!['lines'] as List<ReceiveLinePayload>;
    expect(lines, hasLength(1));
    expect(lines.first.itemId, 'i1');
    expect(lines.first.quantity, 1);
    expect(lines.first.unitCost, 4);
    // No paid_amount typed → 0.
    expect(captured!['paidAmount'], 0);
    expect(captured!['paymentMethod'], isNull);
  });

  testWidgets('SAVE is disabled with no lines', (tester) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(itemId: 'i1', name: 'Bariis'),
    ];

    await pumpReceive(tester);
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, en.receiveSaveButton),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets(
    'Clear all wipes lines but keeps the supplier',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(itemId: 'i1', name: 'Bariis', lastCost: 4),
        fakeActivatedItem(itemId: 'i2', name: 'Sonkor', lastCost: 2),
      ];

      await pumpReceive(tester);
      await tester.pumpAndSettle();

      // Add two lines.
      await tester.tap(find.text('Bariis'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.receiveAddLineButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sonkor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.receiveAddLineButton));
      await tester.pumpAndSettle();

      // After two ADDs the strip is already auto-expanded, so Clear all
      // is visible without tapping the summary.
      await tester.tap(find.text(en.receiveLinesClearAllButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.receiveLinesClearConfirmYes));
      await tester.pumpAndSettle();

      expect(receive.isEmpty, isTrue);
      expect(receive.supplier, isNotNull);
    },
  );
}
