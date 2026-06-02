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

  testWidgets('tapping a tile pre-fills qty=1, per-unit, and total from last_cost', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(
        itemId: 'i1',
        name: 'Bariis',
        baseUnitCode: 'kg',
        baseUnitLabel: 'Kg',
        receiveUnitCode: 'bag',
        receiveUnitLabel: 'Bag',
        lastCost: 24,
      ),
    ];

    await pumpReceive(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis'));
    await tester.pumpAndSettle();

    // Per-unit and Total both pre-filled with 24 (qty=1 × $24/bag).
    expect(find.widgetWithText(TextField, '24'), findsNWidgets(2));
    // Receive unit shown next to qty.
    expect(find.text('Bag'), findsWidgets);
    // ADD LINE enabled because per-unit > 0.
    final addButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, en.receiveAddLineButton),
    );
    expect(addButton.onPressed, isNotNull);
  });

  testWidgets(
    'changing qty auto-multiplies total when per-unit was last typed',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          itemId: 'i1',
          name: 'Bariis',
          receiveUnitCode: 'bag',
          receiveUnitLabel: 'Bag',
          lastCost: 24,
        ),
      ];

      await pumpReceive(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bariis'));
      await tester.pumpAndSettle();

      // Change qty to 5 — should auto-update total to 120.
      await tester.enterText(find.widgetWithText(TextField, '1'), '5');
      await tester.pump();

      expect(find.widgetWithText(TextField, '120'), findsOneWidget);
      // Per-unit stays at 24.
      expect(find.widgetWithText(TextField, '24'), findsOneWidget);
    },
  );

  testWidgets('typing into Total recomputes Per-unit and locks it on qty change', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(
        itemId: 'i1',
        name: 'Bariis',
        receiveUnitCode: 'bag',
        receiveUnitLabel: 'Bag',
        lastCost: 24,
      ),
    ];

    await pumpReceive(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis'));
    await tester.pumpAndSettle();

    // Override total to $100 → per-unit recomputes to $100/qty=1 = $100.
    await tester.enterText(
      find.widgetWithText(TextField, '24').last,
      '100',
    );
    await tester.pump();
    expect(find.widgetWithText(TextField, '100'), findsNWidgets(2));

    // Now change qty to 5 → since total was the last-typed money field,
    // per-unit recomputes to 100/5 = 20.
    await tester.enterText(find.widgetWithText(TextField, '1'), '5');
    await tester.pump();
    expect(find.widgetWithText(TextField, '20'), findsOneWidget);
    expect(find.widgetWithText(TextField, '100'), findsOneWidget);
  });

  testWidgets('SAVE sends line_total + receive unit_id, paid=0, no payment method', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(
        itemId: 'i1',
        name: 'Bariis',
        baseUnitCode: 'kg',
        baseUnitLabel: 'Kg',
        receiveUnitCode: 'bag',
        receiveUnitLabel: 'Bag',
        lastCost: 24,
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
      };
      return 'fake-receive';
    };

    await pumpReceive(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bariis'));
    await tester.pumpAndSettle();
    // Change qty to 5; total auto = $120.
    await tester.enterText(find.widgetWithText(TextField, '1'), '5');
    await tester.pump();
    await tester.tap(find.text(en.receiveAddLineButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.receiveSaveButton));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    final lines = captured!['lines'] as List<ReceiveLinePayload>;
    expect(lines, hasLength(1));
    expect(lines.first.itemId, 'i1');
    expect(lines.first.quantity, 5);
    expect(lines.first.lineTotal, 120);
    // Critical bug fix: unit_id is the RECEIVE unit's id (bag), not base (kg).
    expect(lines.first.unitId, 'unit-bag');
    // Always fully credit.
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
    'unit picker: switching unit clears costs and sends the new unit_id on SAVE',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          itemId: 'i1',
          name: 'Bariis',
          baseUnitCode: 'kg',
          baseUnitLabel: 'Kg',
          receiveUnitCode: 'bag',
          receiveUnitLabel: 'Bag',
          lastCost: 24,
        ),
      ];
      api.onListItemUnits = (_, _, _, _) async => const [
        ReceiveUnitOption(
          unitId: 'unit-kg',
          unitCode: 'kg',
          unitLabel: 'Kg',
          conversionToBase: 1,
          isDefault: false,
        ),
        ReceiveUnitOption(
          unitId: 'unit-bag',
          unitCode: 'bag',
          unitLabel: 'Bag',
          conversionToBase: 25,
          isDefault: true,
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
        captured = {'lines': lines};
        return 'fake-receive';
      };

      await pumpReceive(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bariis'));
      await tester.pumpAndSettle();

      // Form pre-fills with $24/Bag (default unit).
      expect(find.widgetWithText(TextField, '24'), findsNWidgets(2));

      // Tap the unit label (shows the ▾ arrow) to open the picker.
      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      await tester.pumpAndSettle();
      // Pick Kg.
      await tester.tap(find.text('Kg'));
      await tester.pumpAndSettle();

      // Cost fields cleared (per-bag pre-fill no longer applies).
      expect(find.widgetWithText(TextField, '24'), findsNothing);

      // Type new cost in kg: $1/kg, qty 5 = $5.
      await tester.enterText(find.widgetWithText(TextField, '1'), '5');
      await tester.pump();
      final perUnitField = find.byWidgetPredicate(
        (w) => w is TextField &&
            w.decoration?.labelText ==
                en.receiveLinePerUnitLabel('\$', 'Kg'),
      );
      await tester.enterText(perUnitField, '1');
      await tester.pump();

      await tester.tap(find.text(en.receiveAddLineButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.receiveSaveButton));
      await tester.pumpAndSettle();

      // post_receive received the KG unit_id, not BAG.
      final lines = captured!['lines'] as List<ReceiveLinePayload>;
      expect(lines.first.unitId, 'unit-kg');
      expect(lines.first.quantity, 5);
      expect(lines.first.lineTotal, 5);
    },
  );

  testWidgets('Clear all wipes lines but keeps the supplier', (tester) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(itemId: 'i1', name: 'Bariis', lastCost: 4),
      fakeActivatedItem(itemId: 'i2', name: 'Sonkor', lastCost: 2),
    ];

    await pumpReceive(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bariis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.receiveAddLineButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sonkor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.receiveAddLineButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.receiveLinesClearAllButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.receiveLinesClearConfirmYes));
    await tester.pumpAndSettle();

    expect(receive.isEmpty, isTrue);
    expect(receive.supplier, isNotNull);
  });
}
