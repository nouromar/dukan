import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/capabilities.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/products/shop_item_detail_screen.dart';
import 'package:dukan/scanner/scan_event.dart';
import 'package:dukan/scanner/scanner_sheet.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

ShopItemDetail _detail({
  String displayName = 'Bariis Basmati',
  double currentStock = 50,
  String baseUnitLabel = 'Kg',
  List<ShopItemUnitDetail>? units,
}) =>
    ShopItemDetail(
      header: ShopItemSummary(
        shopItemId: 'si-1',
        itemId: 'item-1',
        displayName: displayName,
        categoryName: null,
        baseUnitCode: 'kg',
        baseUnitLabel: baseUnitLabel,
        currentStock: currentStock,
        unitCount: units?.length ?? 2,
        isActive: true,
      ),
      units: units ??
          const [
            ShopItemUnitDetail(
              shopItemUnitId: 'siu-base',
              itemUnitId: null,
              unitCode: 'kg',
              unitLabel: 'Kg',
              packagingLabel: 'Kg',
              conversionToBase: 1,
              salePrice: 1.5,
              lastCost: null,
              isDefaultSale: true,
              isDefaultReceive: false,
              isBaseUnit: true,
              isActive: true,
            ),
            ShopItemUnitDetail(
              shopItemUnitId: 'siu-bag',
              itemUnitId: null,
              unitCode: 'bag',
              unitLabel: 'Bag',
              packagingLabel: '25 Kg Bag',
              conversionToBase: 25,
              salePrice: 35,
              lastCost: null,
              isDefaultSale: false,
              isDefaultReceive: true,
              isBaseUnit: false,
              isActive: true,
            ),
          ],
      aliases: const [],
      barcodes: const [],
    );

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    // Default to an owner capability set so the existing tests (which
    // assert edit affordances render) still pass. The cashier-mode
    // test below overrides explicitly.
    auth = FakeAuthController(
      capabilities: Capabilities.forTesting(const [
        'inventory.product.edit',
        'inventory.adjustment.post',
        'inventory.barcode.bind',
      ]),
    );
    api = FakeShopApi();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pumpDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        ShopItemDetailScreen(
          shop: shop,
          shopItemId: 'si-1',
          displayName: 'Bariis Basmati',
        ),
        authController: auth,
        shopApi: api,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Hide product deactivates it (queued set_shop_item_active)',
      (tester) async {
    api.onGetShopItem = (_, _, _) async => _detail();
    String? hiddenId;
    bool? hiddenActive;
    api.onSetShopItemActive = (id, active) async {
      hiddenId = id;
      hiddenActive = active;
    };

    await pumpDetail(tester);

    // The app-bar Hide action (owner caps by default in setUp).
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    expect(find.text(en.deactivateItemConfirmTitle), findsOneWidget);

    await tester.tap(find.text(en.deactivateItemConfirmAction));
    await tester.pumpAndSettle();

    // The queued post drained to set_shop_item_active(si-1, isActive=false).
    expect(hiddenId, 'si-1');
    expect(hiddenActive, false);
  });

  testWidgets(
    'renders header (current stock + base unit) and packaging rows with default badges',
    (tester) async {
      api.onGetShopItem = (_, _, _) async => _detail();

      await pumpDetail(tester);

      // Stock readout, expressed in the default *receive* packaging (the
      // "25 Kg Bag" here) rather than raw base — 50kg → "2 Bag(25Kg)".
      expect(find.text('2 Bag(25Kg)'), findsOneWidget);

      // First packaging row (base) is in view by default.
      expect(find.text('Kg'), findsWidgets);

      // Scroll the second packaging into view (long ListView).
      await tester.scrollUntilVisible(
        find.text('25 Kg Bag'),
        100,
      );
      expect(find.text('25 Kg Bag'), findsOneWidget);

      // Each packaging row renders both default chips. Exactly one chip
      // is selected per side; assert on selected count instead of label
      // text count (which depends on what's currently mounted).
      final selectedChips = tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .where((c) => c.selected)
          .toList();
      expect(selectedChips.length, greaterThanOrEqualTo(1));
    },
  );

  testWidgets(
    '"Edit price" opens a dialog; entering a value calls setShopItemUnitSalePrice and refreshes',
    (tester) async {
      var getCalls = 0;
      api.onGetShopItem = (_, _, _) async {
        getCalls++;
        return _detail();
      };

      await pumpDetail(tester);

      expect(getCalls, 1);

      // Price is the tap target now (no separate "Edit price" button) —
      // tap the base-unit price ($1.50) to open the edit dialog.
      await tester.tap(find.text('\$1.50'));
      await tester.pumpAndSettle();

      // Dialog is open — enter a new price.
      await tester.enterText(find.byType(TextField), '2.25');
      await tester.pump();

      // Confirm (the SAVE button uses shopItemEditorSaveButton).
      await tester.tap(
        find.widgetWithText(FilledButton, en.shopItemEditorSaveButton),
      );
      await tester.pumpAndSettle();

      expect(api.setShopItemUnitSalePriceCalls, hasLength(1));
      expect(
        api.setShopItemUnitSalePriceCalls.first.shopItemUnitId,
        'siu-base',
      );
      expect(api.setShopItemUnitSalePriceCalls.first.salePrice, 2.25);

      // Detail re-fetched after the price write.
      expect(getCalls, 2);
    },
  );

  testWidgets(
    'default chips are selection-only: tapping the selected default is ignored',
    (tester) async {
      api.onGetShopItem = (_, _, _) async => _detail();
      await pumpDetail(tester);

      // Base "Kg" is default-for-sale → its "Sale" chip is selected. Tapping
      // it would try to DESELECT, which must be ignored (an item must always
      // keep exactly one default per side).
      final selectedSale = find.byWidgetPredicate((w) =>
          w is FilterChip &&
          w.selected &&
          w.label is Text &&
          (w.label as Text).data == en.shopItemDetailDefaultSaleBadge);
      await tester.scrollUntilVisible(selectedSale, 100);
      expect(selectedSale, findsOneWidget);

      await tester.tap(selectedSale);
      await tester.pumpAndSettle();

      // No default-flags mutation queued/drained — deselect is a no-op.
      expect(api.setShopItemUnitDefaultFlagsCalls, isEmpty);
    },
  );

  testWidgets(
    'promoting a different packaging to default fires the flags RPC',
    (tester) async {
      api.onGetShopItem = (_, _, _) async => _detail();
      await pumpDetail(tester);

      // The bag is NOT default-for-sale → its "Sale" chip is unselected.
      final unselectedSale = find.byWidgetPredicate((w) =>
          w is FilterChip &&
          !w.selected &&
          w.label is Text &&
          (w.label as Text).data == en.shopItemDetailDefaultSaleBadge);
      await tester.scrollUntilVisible(unselectedSale, 100);
      expect(unselectedSale, findsOneWidget);

      await tester.tap(unselectedSale);
      await tester.pumpAndSettle();

      expect(api.setShopItemUnitDefaultFlagsCalls, hasLength(1));
      final call = api.setShopItemUnitDefaultFlagsCalls.single;
      expect(call.shopItemUnitId, 'siu-bag');
      expect(call.isDefaultSale, isTrue);
    },
  );

  testWidgets('AppBar has NO pencil — edits happen inline on this screen',
      (tester) async {
    api.onGetShopItem = (_, _, _) async => _detail();
    await pumpDetail(tester);

    final pencilInAppBar = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.edit_outlined),
    );
    expect(pencilInAppBar, findsNothing);
  });

  testWidgets('Name tile → dialog → addShopItemAlias commits rename',
      (tester) async {
    api.onGetShopItem = (_, _, _) async => _detail();
    await pumpDetail(tester);

    await tester.tap(find.text(en.shopItemEditorNameLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bariis Cusub');
    await tester.tap(
      find.widgetWithText(FilledButton, en.shopItemEditorSaveButton),
    );
    await tester.pumpAndSettle();

    expect(api.addShopItemAliasCalls, hasLength(1));
    expect(api.addShopItemAliasCalls.first.aliasText, 'Bariis Cusub');
    expect(api.addShopItemAliasCalls.first.isDisplay, true);
  });

  testWidgets('Category tile → picker → setShopItemCategory commits',
      (tester) async {
    api.onGetShopItem = (_, _, _) async => _detail();
    api.onListCategories = (_) async => const [
          CategoryOption(id: 'cat-1', code: 'staples', name: 'Staples'),
          CategoryOption(id: 'cat-2', code: 'beverages', name: 'Beverages'),
        ];
    await pumpDetail(tester);

    await tester.tap(find.text(en.shopItemEditorCategoryLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beverages'));
    await tester.pumpAndSettle();

    expect(api.setShopItemCategoryCalls, hasLength(1));
    expect(api.setShopItemCategoryCalls.first.categoryId, 'cat-2');
  });

  testWidgets('Delete non-base packaging → removeOrDisableShopItemUnit fires',
      (tester) async {
    api.onGetShopItem = (_, _, _) async => _detail();
    await pumpDetail(tester);

    // Scroll the non-base packaging row's trash icon into view.
    // scrollUntilVisible stops at the widget's edge; ensureVisible
    // pushes it fully on-screen so the tap centre isn't outside the
    // viewport (#346 added Add/Scan chips to the base packaging,
    // pushing the second packaging's trash icon below the 600 px
    // test fold).
    final deleteIcon = find.byIcon(Icons.delete_outline);
    await tester.scrollUntilVisible(deleteIcon, 100);
    await tester.ensureVisible(deleteIcon);
    await tester.pumpAndSettle();
    await tester.tap(deleteIcon);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, en.removePackagingConfirmAction),
    );
    await tester.pumpAndSettle();

    // #350 switched the mobile from deactivate_shop_item_unit (soft-
    // only) to remove_or_disable_shop_item_unit (hard-delete when the
    // packaging has no transaction lines, else soft-disable). The
    // fake's default is 'removed'.
    expect(api.removeOrDisableShopItemUnitCalls, ['siu-bag']);
    expect(api.deactivateShopItemUnitCalls, isEmpty);
  });

  testWidgets(
    'add packaging appears immediately even if the reload lacks it '
    '(optimistic merge — no need to re-open the screen)',
    (tester) async {
      // getShopItem always returns the OLD detail (no "50 Kg Bag"), as if a
      // racing delta sync dropped the just-added row from the reload. The
      // new packaging must still show — this was the bug where it only
      // appeared after leaving and re-opening the detail screen.
      api.onGetShopItem = (_, _, _) async => _detail();
      api.onSuggestItemPackagings = (_, _, _, _, _, _) async => const [
            PackagingSuggestion(
              unitCode: 'bag',
              unitLabel: 'Bag',
              conversionToBase: 50,
              uses: 3,
              source: 'category',
            ),
          ];
      api.onCreateShopItemUnit = (_, _, _, _, _) async => 'new-siu-50';

      await pumpDetail(tester);

      // Open the add-packaging sheet.
      final addButton = find.text(en.shopItemEditorAddPackagingButton);
      await tester.scrollUntilVisible(addButton, 120);
      await tester.ensureVisible(addButton);
      await tester.pumpAndSettle();
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Sheet opened with the suggested packaging.
      expect(find.text(en.addPackagingSuggestionsHeader), findsOneWidget);

      // Pick the new "50 Kg Bag" suggestion, then save.
      await tester.tap(find.text('50 Kg Bag'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, en.addPackagingSaveButton),
      );
      await tester.pumpAndSettle();

      // Sheet closed; the reload's getShopItem still lacks the row, yet the
      // optimistically-merged packaging is on screen.
      await tester.scrollUntilVisible(find.text('50 Kg Bag'), 120);
      expect(find.text('50 Kg Bag'), findsOneWidget);
    },
  );

  testWidgets('Stock readout tap → adjust sheet → postInventoryAdjustment fires',
      (tester) async {
    api.onGetShopItem = (_, _, _) async => _detail();
    await pumpDetail(tester);

    // Tap the big stock readout to open the adjust sheet.
    await tester.tap(find.text('2 Bag(25Kg)'));
    await tester.pumpAndSettle();

    // Default mode is "Set exact" (Opening is hidden post-onboarding
    // because the RPC refuses it once setup leaves the opening
    // window). Current stock = 50 in this fixture; typing 70 makes
    // delta = +20 against reason='correction'. Positive delta means
    // the unit-cost field appears and the server requires it (#340).
    await tester.enterText(find.byType(TextField).at(0), '70');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '5');
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, en.stockAdjustSaveButton),
    );
    await tester.pumpAndSettle();

    expect(api.postInventoryAdjustmentCalls, hasLength(1));
    expect(api.postInventoryAdjustmentCalls.first.reasonCode, 'correction');
    expect(api.postInventoryAdjustmentCalls.first.quantityDelta, 20);
    expect(api.postInventoryAdjustmentCalls.first.shopItemId, 'si-1');
    expect(api.postInventoryAdjustmentCalls.first.unitCost, 5);
  });

  testWidgets(
    'Stock adjust "Set exact" computes delta against current stock',
    (tester) async {
      api.onGetShopItem = (_, _, _) async => _detail(currentStock: 50);
      await pumpDetail(tester);

      await tester.tap(find.text('2 Bag(25Kg)'));
      await tester.pumpAndSettle();
      // Pick "Set exact" mode.
      await tester.tap(find.widgetWithText(
          ChoiceChip, en.stockAdjustModeSetExact));
      await tester.pumpAndSettle();
      // New total 80 → delta +30. Positive delta requires unit_cost.
      await tester.enterText(find.byType(TextField).at(0), '80');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '4');
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, en.stockAdjustSaveButton),
      );
      await tester.pumpAndSettle();

      expect(api.postInventoryAdjustmentCalls.last.reasonCode, 'correction');
      expect(api.postInventoryAdjustmentCalls.last.quantityDelta, 30);
      expect(api.postInventoryAdjustmentCalls.last.unitCost, 4);
    },
  );

  testWidgets('+ Add barcode on packaging tile → addShopItemBarcode fires',
      (tester) async {
    api.onGetShopItem = (_, _, _) async => _detail();
    await pumpDetail(tester);

    // Drag the page upward to bring the bag tile + its chip row into
    // the viewport (lazy ListView doesn't build offscreen children).
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(ActionChip, en.barcodeAddTooltip).first,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '6291100123456');
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, en.shopItemEditorSaveButton),
    );
    await tester.pumpAndSettle();

    expect(api.addShopItemBarcodeCalls, hasLength(1));
    expect(api.addShopItemBarcodeCalls.first.barcode, '6291100123456');
  });

  testWidgets(
    'Scan code on packaging tile → addShopItemBarcode with scanned value',
    (tester) async {
      api.onGetShopItem = (_, _, _) async => _detail();
      final restore = Scanner.overrideOpener(
        (_) async => const ScanEvent(
          code: '5901234123457',
          source: ScanSource.camera,
          symbology: 'ean13',
        ),
      );
      addTearDown(restore);

      await pumpDetail(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(ActionChip, en.barcodeScanAndBindAction).first,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(api.addShopItemBarcodeCalls, hasLength(1));
      expect(api.addShopItemBarcodeCalls.first.barcode, '5901234123457');
      expect(api.addShopItemBarcodeCalls.first.isPrimary, isFalse);
    },
  );

  testWidgets('+ Add alias on detail → addShopItemAlias fires (non-display)',
      (tester) async {
    api.onGetShopItem = (_, _, _) async => _detail();
    await pumpDetail(tester);

    // Aliases chip strip is below the packagings — scroll into view,
    // then ensureVisible so the chip's tap center isn't outside the
    // viewport (scrollUntilVisible stops at the chip's edge; a small
    // layout shift above can leave the center off-screen).
    final aliasChipFinder =
        find.widgetWithText(ActionChip, en.aliasAddTooltip);
    await tester.scrollUntilVisible(aliasChipFinder, 100);
    await tester.ensureVisible(aliasChipFinder);
    await tester.pumpAndSettle();
    await tester.tap(aliasChipFinder);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Riis');
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, en.shopItemEditorSaveButton),
    );
    await tester.pumpAndSettle();

    expect(api.addShopItemAliasCalls, hasLength(1));
    expect(api.addShopItemAliasCalls.first.aliasText, 'Riis');
    expect(api.addShopItemAliasCalls.first.isDisplay, false);
  });

  testWidgets(
    'cashier role hides every edit affordance on Product detail',
    (tester) async {
      auth.setCapabilities(Capabilities.empty());
      api.onGetShopItem = (_, _, _) async => _detail();
      await pumpDetail(tester);

      // Add packaging button hidden.
      expect(
        find.text(en.shopItemEditorAddPackagingButton),
        findsNothing,
      );
      // + Add code / Scan code / + Add other name chips hidden.
      expect(find.text(en.barcodeAddTooltip), findsNothing);
      expect(find.text(en.barcodeScanAndBindAction), findsNothing);
      expect(find.text(en.aliasAddTooltip), findsNothing);
      // No trash icon on the non-base packaging.
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      // The screen still renders — name, packaging, stock are visible.
      expect(find.text('Bariis Basmati'), findsAtLeastNWidgets(1));
      // Tapping the stock readout shouldn't open the adjust sheet —
      // the InkWell has onTap=null, so no _StockAdjustSheet shows up.
      await tester.tap(find.byType(InkWell).first, warnIfMissed: false);
      await tester.pumpAndSettle();
      // No postInventoryAdjustment call should have fired.
      expect(api.postInventoryAdjustmentCalls, isEmpty);
    },
  );
}
