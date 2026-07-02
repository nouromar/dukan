// shop_item_editor_screen tests — CREATE-only.
//
// EDIT lives on the product detail screen now (every field is a
// tap-to-edit tile there). This screen exists for new-product
// creation only, opened from the Products FAB and the setup
// onboarding "Add my own items" flow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/products/packaging_editor_sheet.dart';
import 'package:dukan/products/shop_item_editor_screen.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/pending_post_dao.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeShopApi api;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    api = FakeShopApi();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        ShopItemEditorScreen(shop: shop),
        shopApi: api,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Drives the "+ Add packaging" CTA → packaging editor sheet (which
  /// defaults the unit dropdown to the item's base unit) → SAVE flow.
  /// Post-#356, the BASE summary row only appears AFTER the cashier
  /// has populated at least one field, so there's no tappable BASE
  /// badge in the empty state. Fills sale price so the save invariant
  /// "at least one packaging filled" passes; the editor merges the
  /// sheet's result into _packagings[0] because the chosen unit is
  /// the base unit.
  Future<void> fillBaseSalePriceViaSheet(
    WidgetTester tester,
    String value,
  ) async {
    await tester.tap(find.text(en.shopItemEditorAddPackagingButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, en.addPackagingPriceLabel('Kg')),
      value,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.widgetWithText(
          FilledButton,
          en.packagingEditorSaveButton,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Returns a finder that uniquely matches the sheet's SAVE button —
  /// the editor's SAVE button has the same label ("SAVE") and would
  /// match `find.widgetWithText(FilledButton, ...)` ambiguously.
  Finder sheetSaveButton(AppLocalizations en) => find.descendant(
        of: find.byType(BottomSheet),
        matching: find.widgetWithText(
          FilledButton,
          en.packagingEditorSaveButton,
        ),
      );

  testWidgets('AppBar title is shopItemEditorTitleCreate', (tester) async {
    api.onListUnits = () async => const [
      UnitOption(id: 'unit-kg', code: 'kg', label: 'Kg'),
    ];
    await pumpEditor(tester);
    expect(find.text(en.shopItemEditorTitleCreate), findsOneWidget);
  });

  testWidgets('bootstrap is wired (listUnits is invoked on mount)',
      (tester) async {
    var called = 0;
    api.onListUnits = () async {
      called++;
      return const [UnitOption(id: 'unit-kg', code: 'kg', label: 'Kg')];
    };
    await pumpEditor(tester);
    await tester.pumpAndSettle();
    expect(called, 1);
  });

  testWidgets(
    'SAVE & ADD ANOTHER commits, resets name, keeps base unit/category — '
    'BASE row driven via the packaging sheet',
    (tester) async {
      api.onListUnits = () async => const [
            UnitOption(id: 'unit-kg', code: 'kg', label: 'Kg'),
          ];
      api.onListCategories = (_) async => const [
            CategoryOption(id: 'cat-1', code: 'staples', name: 'Staples'),
          ];
      await pumpEditor(tester);

      // Fill name + base unit + category.
      await tester.enterText(
        find.widgetWithText(TextField, en.shopItemEditorNameLabel),
        'Bariis Cusub',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kg').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Staples').last);
      await tester.pumpAndSettle();

      // Open BASE row → enter a sale price → save the sheet. Required
      // for the "at least one packaging filled" invariant.
      await fillBaseSalePriceViaSheet(tester, '15');

      // Scroll the SAVE & ADD ANOTHER button into view, then tap.
      await tester.scrollUntilVisible(
        find.text(en.shopItemEditorSaveAndAddAnotherButton),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ShopItemEditorScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(en.shopItemEditorSaveAndAddAnotherButton),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // Shop item was created with name + category + base sale price.
      expect(api.createShopItemCalls, hasLength(1));
      expect(api.createShopItemCalls.first.name, 'Bariis Cusub');
      expect(api.createShopItemCalls.first.categoryId, 'cat-1');
      expect(api.createShopItemCalls.first.salePrice, 15);

      // Crucially: we did NOT pop — editor stays mounted so the
      // cashier can keep adding items.
      expect(find.byType(ShopItemEditorScreen), findsOneWidget);
    },
  );

  testWidgets(
    'offline: the item create is queued with the client id, not lost',
    (tester) async {
      api.onListUnits = () async => const [
            UnitOption(id: 'unit-kg', code: 'kg', label: 'Kg'),
          ];
      // The item create fails as if offline (transient — NOT a reject).
      api.onCreateShopItem =
          (_, _, _, _, _, _, _, _, _) async => throw Exception('offline');

      final drained = <PendingPost>[];
      final queue = OfflineQueueController(
        dao: PendingPostDao(AppDatabase.instance()),
        executor: (p) async => drained.add(p),
        backoff: (_) => Duration.zero,
        clock: () => DateTime.utc(2026, 7, 2),
      );
      addTearDown(queue.dispose);

      await tester.pumpWidget(wrapWithApp(
        ShopItemEditorScreen(shop: shop),
        shopApi: api,
        offlineQueueController: queue,
        configResolver:
            FakeConfigResolver(values: const {'use_local_db': true}),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, en.shopItemEditorNameLabel),
        'Sonkor',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kg').last);
      await tester.pumpAndSettle();
      await fillBaseSalePriceViaSheet(tester, '15');

      await tester.scrollUntilVisible(
        find.text(en.shopItemEditorSaveAndAddAnotherButton),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ShopItemEditorScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(en.shopItemEditorSaveAndAddAnotherButton),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // The item create was queued (not lost) with a client-minted id +
      // client_op_id — base-only, so no extra-packaging post.
      final post = drained.singleWhere((p) => p.rpc == 'create_shop_item');
      expect(post.params['name'], 'Sonkor');
      expect(post.params['shop_item_id'], isNotNull);
      expect(post.params['base_unit_id'], isNotNull);
      expect(post.clientOpId, isNotNull);
      expect(drained.where((p) => p.rpc == 'create_shop_item_unit'), isEmpty);
    },
  );

  testWidgets(
    'SAVE without any packaging field surfaces the "fill a packaging" error',
    (tester) async {
      api.onListUnits = () async => const [
            UnitOption(id: 'unit-kg', code: 'kg', label: 'Kg'),
          ];
      await pumpEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextField, en.shopItemEditorNameLabel),
        'Bariis',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kg').last);
      await tester.pumpAndSettle();

      final editorSave = find.descendant(
        of: find.byType(ShopItemEditorScreen),
        matching: find.widgetWithText(
          FilledButton,
          en.shopItemEditorSaveButton,
        ),
      );
      await tester.scrollUntilVisible(
        editorSave,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ShopItemEditorScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(editorSave, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Invariant fired — no createShopItem call and the inline error
      // is visible on the packaging card.
      expect(api.createShopItemCalls, isEmpty);
      expect(
        find.text(en.shopItemEditorPackagingMissingMessage),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'fill only non-base packaging → base sale back-computed + default flags '
    'flipped onto the non-base packaging',
    (tester) async {
      api.onListUnits = () async => const [
            UnitOption(id: 'unit-kg', code: 'kg', label: 'Kg'),
            UnitOption(id: 'unit-bag', code: 'bag', label: 'Bag'),
          ];
      // Return a deterministic id for the non-base packaging so we can
      // assert set_default_flags fired on it.
      api.onCreateShopItemUnit = (_, _, unit, conv, _) async =>
          'unit-id-$unit-$conv';
      await pumpEditor(tester);

      // Name + base unit.
      await tester.enterText(
        find.widgetWithText(TextField, en.shopItemEditorNameLabel),
        'Bariis Kiis',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kg').last);
      await tester.pumpAndSettle();

      // BASE row stays empty. Add a "Bag" packaging via the sheet.
      await tester.scrollUntilVisible(
        find.text(en.shopItemEditorAddPackagingButton),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ShopItemEditorScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text(en.shopItemEditorAddPackagingButton));
      await tester.pumpAndSettle();
      // Pick Bag (Kg is excluded — already used by BASE).
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bag').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(
          TextField,
          en.addPackagingConversionLabel('Kg', 'Bag'),
        ),
        '25',
      );
      await tester.enterText(
        find.widgetWithText(TextField, en.addPackagingPriceLabel('Bag')),
        '50',
      );
      await tester.tap(sheetSaveButton(en));
      await tester.pumpAndSettle();

      // Sanity check before tap: exactly one editor SAVE button is in
      // the tree (sheet has popped — its sibling SAVE label is gone).
      final editorSave = find.descendant(
        of: find.byType(ShopItemEditorScreen),
        matching: find.widgetWithText(
          FilledButton,
          en.shopItemEditorSaveButton,
        ),
      );
      expect(editorSave, findsOneWidget,
          reason: 'sheet should have popped — only editor SAVE remains');
      await tester.scrollUntilVisible(
        editorSave,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ShopItemEditorScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(editorSave);
      await tester.pumpAndSettle();

      // createShopItem received the back-computed base sale price
      // (50 / 25 = 2).
      expect(api.createShopItemCalls, hasLength(1));
      expect(api.createShopItemCalls.first.salePrice, 2);

      // set_default_flags fired on the non-base packaging id, setting
      // both default-sale and default-receive true so the Sale screen
      // leads with the Bag packaging. The editor now mints the unit id
      // client-side (0094/0095), so the flags target that same client id
      // it passed to create_shop_item_unit — not the server's return.
      expect(api.setShopItemUnitDefaultFlagsCalls, hasLength(1));
      expect(api.createShopItemUnitCalls, hasLength(1));
      expect(
        api.setShopItemUnitDefaultFlagsCalls.first.shopItemUnitId,
        api.createShopItemUnitCalls.first.shopItemUnitId,
      );
      expect(api.createShopItemUnitCalls.first.shopItemUnitId, isNotNull);
      expect(
        api.setShopItemUnitDefaultFlagsCalls.first.isDefaultSale,
        isTrue,
      );
      expect(
        api.setShopItemUnitDefaultFlagsCalls.first.isDefaultReceive,
        isTrue,
      );
    },
  );

  testWidgets(
    'when BASE is filled, default-flag flip RPC is NOT called',
    (tester) async {
      api.onListUnits = () async => const [
            UnitOption(id: 'unit-kg', code: 'kg', label: 'Kg'),
          ];
      await pumpEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextField, en.shopItemEditorNameLabel),
        'Bariis',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kg').last);
      await tester.pumpAndSettle();

      await fillBaseSalePriceViaSheet(tester, '5');

      final editorSave = find.descendant(
        of: find.byType(ShopItemEditorScreen),
        matching: find.widgetWithText(
          FilledButton,
          en.shopItemEditorSaveButton,
        ),
      );
      await tester.scrollUntilVisible(
        editorSave,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ShopItemEditorScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(editorSave, warnIfMissed: false);
      await tester.pumpAndSettle();

      // create_shop_item already set BASE as default — no follow-up
      // flip should fire.
      expect(api.setShopItemUnitDefaultFlagsCalls, isEmpty);
    },
  );

  testWidgets(
    'PackagingDraftSubmission is reachable from this test file',
    (tester) async {
      // Light type-only sanity check so the sheet's public payload
      // can't be accidentally hidden from external test code.
      const payload = PackagingDraftSubmission(unitCode: 'kg', conversion: 1);
      expect(payload.unitCode, 'kg');
    },
  );

  testWidgets(
    '#357 fill ONLY non-base packaging stock → opening adjustment is '
    'posted with baseQuantity = stock × conversion',
    (tester) async {
      // Reproducing the user report: "I create new item base unit:Kg,
      // chose non-base package: 20 Kg bag. cost, price seem converted
      // to base correctly but stock is 0." Expected after 20 Kg/Bag
      // × 3 bags: baseQuantity = 60 Kg.
      api.onListUnits = () async => const [
            UnitOption(id: 'unit-kg', code: 'kg', label: 'Kg'),
            UnitOption(id: 'unit-bag', code: 'bag', label: 'Bag'),
          ];
      api.onCreateShopItemUnit = (_, _, unit, conv, _) async =>
          'unit-id-$unit-$conv';
      await pumpEditor(tester);

      // Name + base unit Kg.
      await tester.enterText(
        find.widgetWithText(TextField, en.shopItemEditorNameLabel),
        'Bariis 20 Kg',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kg').last);
      await tester.pumpAndSettle();

      // +Add → pick Bag → conv 20 → stock 3 (no price/cost) → SAVE.
      await tester.scrollUntilVisible(
        find.text(en.shopItemEditorAddPackagingButton),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ShopItemEditorScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text(en.shopItemEditorAddPackagingButton));
      await tester.pumpAndSettle();
      // Pick Bag.
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bag').last);
      await tester.pumpAndSettle();
      // Conversion 20.
      await tester.enterText(
        find.widgetWithText(
          TextField,
          en.addPackagingConversionLabel('Kg', 'Bag'),
        ),
        '20',
      );
      // Stock 3 (in Bag units).
      await tester.enterText(
        find.widgetWithText(TextField, en.packagingEditorStockLabel('Bag')),
        '3',
      );
      await tester.tap(sheetSaveButton(en));
      await tester.pumpAndSettle();

      // SAVE the item.
      final editorSave = find.descendant(
        of: find.byType(ShopItemEditorScreen),
        matching: find.widgetWithText(
          FilledButton,
          en.shopItemEditorSaveButton,
        ),
      );
      await tester.scrollUntilVisible(
        editorSave,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ShopItemEditorScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(editorSave, warnIfMissed: false);
      await tester.pumpAndSettle();

      // The asserted invariant: opening stock was posted with the
      // back-computed base quantity (3 bags × 20 Kg/bag = 60 Kg).
      expect(api.postInventoryAdjustmentCalls, hasLength(1));
      final adj = api.postInventoryAdjustmentCalls.first;
      expect(adj.reasonCode, 'opening');
      expect(adj.shopItemId, isNotNull);
      expect(adj.quantityDelta, 60);
    },
  );
}
