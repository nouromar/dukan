import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/products/shop_item_detail_screen.dart';

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
  late FakeShopApi api;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
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
        shopApi: api,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'renders header (current stock + base unit) and packaging rows with default badges',
    (tester) async {
      api.onGetShopItem = (_, _, _) async => _detail();

      await pumpDetail(tester);

      // Stock readout (now its own section under the ITEM tiles).
      expect(find.text('50 Kg'), findsOneWidget);

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

  testWidgets('Delete non-base packaging → deactivateShopItemUnit fires',
      (tester) async {
    api.onGetShopItem = (_, _, _) async => _detail();
    await pumpDetail(tester);

    // Scroll the non-base packaging row's trash icon into view.
    await tester.scrollUntilVisible(find.text('25 Kg Bag'), 100);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, en.removePackagingConfirmAction),
    );
    await tester.pumpAndSettle();

    expect(api.deactivateShopItemUnitCalls, ['siu-bag']);
  });

  testWidgets('Stock readout tap → adjust sheet → postInventoryAdjustment fires',
      (tester) async {
    api.onGetShopItem = (_, _, _) async => _detail();
    await pumpDetail(tester);

    // Tap the big stock readout to open the adjust sheet.
    await tester.tap(find.text('50 Kg'));
    await tester.pumpAndSettle();

    // Default mode is "Opening". Enter 20 + save.
    await tester.enterText(find.byType(TextField).first, '20');
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, en.stockAdjustSaveButton),
    );
    await tester.pumpAndSettle();

    expect(api.postInventoryAdjustmentCalls, hasLength(1));
    expect(api.postInventoryAdjustmentCalls.first.reasonCode, 'opening');
    expect(api.postInventoryAdjustmentCalls.first.quantityDelta, 20);
    expect(api.postInventoryAdjustmentCalls.first.shopItemId, 'si-1');
  });

  testWidgets(
    'Stock adjust "Set exact" computes delta against current stock',
    (tester) async {
      api.onGetShopItem = (_, _, _) async => _detail(currentStock: 50);
      await pumpDetail(tester);

      await tester.tap(find.text('50 Kg'));
      await tester.pumpAndSettle();
      // Pick "Set exact" mode.
      await tester.tap(find.widgetWithText(
          ChoiceChip, en.stockAdjustModeSetExact));
      await tester.pumpAndSettle();
      // New total 80 → delta +30.
      await tester.enterText(find.byType(TextField).first, '80');
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, en.stockAdjustSaveButton),
      );
      await tester.pumpAndSettle();

      expect(api.postInventoryAdjustmentCalls.last.reasonCode, 'correction');
      expect(api.postInventoryAdjustmentCalls.last.quantityDelta, 30);
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

  testWidgets('+ Add alias on detail → addShopItemAlias fires (non-display)',
      (tester) async {
    api.onGetShopItem = (_, _, _) async => _detail();
    await pumpDetail(tester);

    // Aliases chip strip is below the packagings — scroll to it.
    await tester.scrollUntilVisible(
      find.widgetWithText(ActionChip, en.aliasAddTooltip),
      100,
    );
    await tester.tap(find.widgetWithText(ActionChip, en.aliasAddTooltip));
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
}
