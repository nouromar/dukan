import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/receive/receive_screen.dart';
import 'package:dukan/shared/bono_image_picker.dart';
import 'package:dukan/shared/quantity_chips.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/pending_post_dao.dart';

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

  Future<void> pumpReceive(
    WidgetTester tester, {
    BonoImagePicker? bonoPicker,
  }) async {
    await tester.pumpWidget(
      wrapWithApp(
        ReceiveScreen(shop: shop, bonoPicker: bonoPicker),
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

  testWidgets(
    'tapping a tile pre-fills qty=1 + total from last_cost; derived'
    ' per-packaging caption renders below',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-bag',
          displayName: 'Bariis',
          baseUnitCode: 'kg',
          baseUnitLabel: 'Kg',
          defaultUnitCode: 'bag',
          defaultUnitLabel: 'Bag',
          defaultUnitConversionToBase: 25,
          packagingLabel: '25 Kg Bag',
          defaultUnitLastCost: 24,
        ),
      ];

      await pumpReceive(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bariis'));
      await tester.pumpAndSettle();

      // Total pre-filled with 24 (qty=1 × $24/bag). The $/packaging
      // field is gone — total is the only money input.
      expect(find.widgetWithText(TextField, '24'), findsOneWidget);
      // Packaging label shown next to qty.
      expect(find.text('25 Kg Bag'), findsWidgets);
      // Derived caption ("= $24 per 25 Kg Bag") rendered below.
      expect(
        find.text(en.receiveLineDerivedPerUnit('\$24.00', '25 Kg Bag')),
        findsOneWidget,
      );
      // ADD LINE enabled because total > 0.
      final addButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.receiveAddLineButton),
      );
      expect(addButton.onPressed, isNotNull);
    },
  );

  testWidgets(
    'focusing search hides the line-entry form so the results grid is not '
    'covered (matches Sale basket/keyboard behaviour)',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-bag',
          displayName: 'Bariis',
          baseUnitCode: 'kg',
          baseUnitLabel: 'Kg',
          defaultUnitCode: 'bag',
          defaultUnitLabel: 'Bag',
          defaultUnitConversionToBase: 25,
          packagingLabel: '25 Kg Bag',
          defaultUnitLastCost: 24,
        ),
      ];

      await pumpReceive(tester);
      await tester.pumpAndSettle();

      // Tap a tile → line-entry form appears (tapping drops search focus).
      await tester.tap(find.text('Bariis'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, en.receiveAddLineButton),
        findsOneWidget,
      );

      // Re-focus search (cashier types another query) → the form hides so
      // the results grid keeps the full height above the keyboard.
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, en.receiveAddLineButton),
        findsNothing,
      );
      // The results tile is still there (grid not covered).
      expect(find.text('Bariis'), findsWidgets);
    },
  );

  testWidgets(
    'results grid dismisses the keyboard on scroll; line form has no '
    'quantity chips (trimmed for screen space)',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-bag',
          displayName: 'Bariis',
          baseUnitCode: 'kg',
          baseUnitLabel: 'Kg',
          defaultUnitCode: 'bag',
          defaultUnitLabel: 'Bag',
          defaultUnitConversionToBase: 25,
          packagingLabel: '25 Kg Bag',
          defaultUnitLastCost: 24,
        ),
      ];

      await pumpReceive(tester);
      await tester.pumpAndSettle();

      // Dragging the results grid dismisses the keyboard (reclaims space).
      expect(
        tester.widget<GridView>(find.byType(GridView)).keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );

      // Tap a tile → line-entry form, which no longer renders quantity chips.
      await tester.tap(find.text('Bariis'));
      await tester.pumpAndSettle();
      expect(find.byType(QuantityChips), findsNothing);
      // Qty + total + ADD LINE all still present after the trim.
      expect(find.widgetWithText(TextField, '24'), findsOneWidget); // total
      expect(
        find.widgetWithText(FilledButton, en.receiveAddLineButton),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'lines drawer: expand icon toggles normal <-> full review, no overflow',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-bag',
          displayName: 'Bariis',
          baseUnitCode: 'kg',
          baseUnitLabel: 'Kg',
          defaultUnitCode: 'bag',
          defaultUnitLabel: 'Bag',
          defaultUnitConversionToBase: 25,
          packagingLabel: '25 Kg Bag',
          defaultUnitLastCost: 24,
        ),
      ];

      await pumpReceive(tester);
      await tester.pumpAndSettle();
      // Add a line: tap tile (total pre-fills), then ADD LINE.
      await tester.tap(find.text('Bariis'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.receiveAddLineButton));
      await tester.pumpAndSettle();

      // Lines drawer expands to normal → expand-to-full icon offered.
      expect(find.byIcon(Icons.unfold_more), findsOneWidget);
      expect(find.byIcon(Icons.unfold_less), findsNothing);

      // Full review — icon flips; no RenderFlex overflow; SAVE reachable.
      await tester.tap(find.byIcon(Icons.unfold_more));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.unfold_less), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, en.receiveSaveButton),
        findsOneWidget,
      );

      // Shrink back to normal.
      await tester.tap(find.byIcon(Icons.unfold_less));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.unfold_more), findsOneWidget);
    },
  );

  testWidgets(
    'changing qty auto-scales the seeded total until it is hand-edited;'
    ' the derived per-packaging caption recomputes',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-bag',
          displayName: 'Bariis',
          defaultUnitCode: 'bag',
          defaultUnitLabel: 'Bag',
          packagingLabel: '25 Kg Bag',
          defaultUnitLastCost: 24,
        ),
      ];

      await pumpReceive(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bariis'));
      await tester.pumpAndSettle();

      final qtyField = find.byWidgetPredicate((w) =>
          w is TextField &&
          w.decoration?.labelText == en.receiveLineQuantityLabel);
      final totalField = find.byWidgetPredicate((w) =>
          w is TextField &&
          w.decoration?.labelText == en.receiveLineTotalLabel('\$'));

      // Seeded at 24 (last_cost × 1). Bump qty to 5 — the total
      // auto-scales to 120 because it hasn't been hand-edited yet.
      await tester.enterText(qtyField, '5');
      await tester.pump();
      expect(tester.widget<TextField>(totalField).controller!.text, '120');
      expect(
        find.text(en.receiveLineDerivedPerUnit('\$24.00', '25 Kg Bag')),
        findsOneWidget,
      );

      // Hand-edit the total → it's now locked. Changing qty no longer
      // rescales it; the derived caption reflects the new split (100/2).
      await tester.enterText(totalField, '100');
      await tester.enterText(qtyField, '2');
      await tester.pump();
      expect(tester.widget<TextField>(totalField).controller!.text, '100');
      expect(
        find.text(en.receiveLineDerivedPerUnit('\$50.00', '25 Kg Bag')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SAVE sends line_total + shop_item_unit_id, paid=0, no payment method',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-bag',
          displayName: 'Bariis',
          baseUnitCode: 'kg',
          baseUnitLabel: 'Kg',
          defaultUnitCode: 'bag',
          defaultUnitLabel: 'Bag',
          defaultUnitConversionToBase: 25,
          packagingLabel: '25 Kg Bag',
          defaultUnitLastCost: 24,
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
      // Bump qty to 5 — the seeded total auto-scales to $120 (5 × 24),
      // no manual total entry needed.
      await tester.enterText(find.widgetWithText(TextField, '1'), '5');
      await tester.pump();
      await tester.tap(find.text(en.receiveAddLineButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text(en.receiveSaveButton));
      await tester.pumpAndSettle();
      // Let the "saved" confirmation toast's display timer fire so it
      // doesn't leak past the test (into the next file).
      await tester.pump(const Duration(seconds: 2));

      expect(captured, isNotNull);
      final lines = captured!['lines'] as List<ReceiveLinePayload>;
      expect(lines, hasLength(1));
      expect(lines.first.shopItemUnitId, 'siu-bag');
      expect(lines.first.quantity, 5);
      expect(lines.first.lineTotal, 120);
      // Always fully credit.
      expect(captured!['paidAmount'], 0);
      expect(captured!['paymentMethod'], isNull);
    },
  );

  testWidgets('SAVE is disabled with no lines', (tester) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(
        shopItemId: 'si-1',
        itemId: 'i1',
        defaultShopItemUnitId: 'siu-1',
        displayName: 'Bariis',
      ),
    ];

    await pumpReceive(tester);
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, en.receiveSaveButton),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets(
    'unit picker: switching packaging sends the new shop_item_unit_id on SAVE',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-bag',
          displayName: 'Bariis',
          baseUnitCode: 'kg',
          baseUnitLabel: 'Kg',
          defaultUnitCode: 'bag',
          defaultUnitLabel: 'Bag',
          defaultUnitConversionToBase: 25,
          packagingLabel: '25 Kg Bag',
          defaultUnitLastCost: 24,
        ),
      ];
      api.onListShopItemUnits = (_, _, _) async => const [
        ReceiveUnitOption(
          shopItemUnitId: 'siu-kg',
          unitCode: 'kg',
          unitLabel: 'Kg',
          packagingLabel: 'Kg',
          conversionToBase: 1,
          salePrice: null,
          lastCost: null,
          isDefault: false,
          isBaseUnit: true,
        ),
        ReceiveUnitOption(
          shopItemUnitId: 'siu-bag',
          unitCode: 'bag',
          unitLabel: 'Bag',
          packagingLabel: '25 Kg Bag',
          conversionToBase: 25,
          salePrice: null,
          lastCost: null,
          isDefault: true,
          isBaseUnit: false,
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

      // Form pre-fills with $24 (default packaging × qty 1).
      expect(find.widgetWithText(TextField, '24'), findsOneWidget);

      // Tap the packaging chip (shows the ▾ arrow) to open the picker.
      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      await tester.pumpAndSettle();
      // Pick Kg (the base unit packaging).
      await tester.tap(find.text('Kg'));
      await tester.pumpAndSettle();

      // Total field cleared (no last_cost for the Kg packaging).
      expect(find.widgetWithText(TextField, '24'), findsNothing);

      // Type bono line: qty 5, total $5.
      await tester.enterText(find.widgetWithText(TextField, '1'), '5');
      await tester.pump();
      final totalField = find.byWidgetPredicate(
        (w) => w is TextField &&
            w.decoration?.labelText == en.receiveLineTotalLabel('\$'),
      );
      await tester.enterText(totalField, '5');
      await tester.pump();

      await tester.tap(find.text(en.receiveAddLineButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.receiveSaveButton));
      await tester.pumpAndSettle();
      // Let the "saved" confirmation toast's display timer fire so it
      // doesn't leak past the test (into the next file).
      await tester.pump(const Duration(seconds: 2));

      // post_receive received the KG packaging shop_item_unit_id, not BAG.
      final lines = captured!['lines'] as List<ReceiveLinePayload>;
      expect(lines.first.shopItemUnitId, 'siu-kg');
      expect(lines.first.quantity, 5);
      expect(lines.first.lineTotal, 5);
    },
  );

  testWidgets('Clear all wipes lines but keeps the supplier', (tester) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(
        shopItemId: 'si-1',
        itemId: 'i1',
        defaultShopItemUnitId: 'siu-1',
        displayName: 'Bariis',
        defaultUnitLastCost: 4,
      ),
      fakeActivatedItem(
        shopItemId: 'si-2',
        itemId: 'i2',
        defaultShopItemUnitId: 'siu-2',
        displayName: 'Sonkor',
        defaultUnitLastCost: 2,
      ),
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

  testWidgets(
    'attach bono → camera picker → uploaded id passes through to post_receive',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-1',
          displayName: 'Bariis',
          defaultUnitLastCost: 4,
        ),
      ];
      api.onUploadBonoImage = (shopId, bytes, mimeType, ext) async {
        return 'doc-uploaded-123';
      };
      String? capturedDocId;
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
        capturedDocId = documentId;
        return 'fake-receive';
      };

      await pumpReceive(
        tester,
        bonoPicker: _FakePicker(),
      );
      await tester.pumpAndSettle();

      // Tap the camera icon in the app bar → opens the source sheet.
      await tester.tap(find.byIcon(Icons.photo_camera_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.bonoAttachCamera));
      await tester.pumpAndSettle();
      // Drain the "attached" snackbar so it doesn't obscure SAVE.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Icon flips to the "attached" checkmark.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      // Ring up a quick line and SAVE.
      await tester.tap(find.text('Bariis'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.receiveAddLineButton));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, en.receiveSaveButton),
      );
      await tester.pumpAndSettle();

      // post_receive received the uploaded document_id.
      expect(capturedDocId, 'doc-uploaded-123');
    },
  );

  testWidgets(
    '#367 transient post_receive failure enqueues to the offline queue',
    (tester) async {
      FlutterError.onError = (_) {};
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-rice',
          itemId: 'item-rice',
          defaultShopItemUnitId: 'siu-bag',
          displayName: 'Bariis',
          baseUnitCode: 'kg',
          baseUnitLabel: 'Kg',
          defaultUnitCode: 'bag',
          defaultUnitLabel: 'Bag',
          defaultUnitConversionToBase: 25,
          packagingLabel: '25 Kg Bag',
          defaultUnitLastCost: 24,
        ),
      ];
      api.onPostReceive =
          (_, _, _, _, _, _, _, _) async =>
              throw Exception('connection reset');

      final drained = <Object>[];
      final queue = OfflineQueueController(
        dao: PendingPostDao(AppDatabase.instance()),
        executor: (post) async => drained.add(post),
        backoff: (_) => Duration.zero,
      );

      await tester.pumpWidget(
        wrapWithApp(
          ReceiveScreen(shop: shop),
          authController: auth,
          shopApi: api,
          receiveController: receive,
          offlineQueueController: queue,
          // #383-fixup: queue path lives in useLocalDb=true branch.
          configResolver:
              FakeConfigResolver(values: const {'use_local_db': true}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bariis'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.receiveAddLineButton));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, en.receiveSaveButton),
      );
      await tester.pumpAndSettle();

      // Lines cleared (the queue owns the work now).
      expect(receive.isEmpty, isTrue);
      // Exactly one post flowed through the queue's executor with
      // rpc='post_receive'.
      expect(drained, hasLength(1));
      final post = drained.single as PendingPost;
      expect(post.rpc, 'post_receive');
      expect(post.shopId, shop.id);
    },
  );
}

class _FakePicker implements BonoImagePicker {
  @override
  Future<PickedBono?> pickFromCamera() async => PickedBono(
        bytes: Uint8List.fromList(List.filled(128, 0xAA)),
        mimeType: 'image/jpeg',
        fileExtension: 'jpg',
      );

  @override
  Future<PickedBono?> pickFromGallery() async => PickedBono(
        bytes: Uint8List.fromList(List.filled(64, 0xBB)),
        mimeType: 'image/jpeg',
        fileExtension: 'jpg',
      );
}
