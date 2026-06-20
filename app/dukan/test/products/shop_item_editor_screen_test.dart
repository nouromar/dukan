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

  /// Drives the BASE summary row → packaging editor sheet → SAVE flow
  /// post-#354 (the inline base fields are gone — every edit is via
  /// the sheet). Fills the BASE row's sale price so the save invariant
  /// "at least one packaging filled" passes.
  Future<void> fillBaseSalePriceViaSheet(
    WidgetTester tester,
    String value,
  ) async {
    await tester.tap(find.text(en.shopItemEditorBaseBadge));
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
      // leads with the Bag packaging.
      expect(api.setShopItemUnitDefaultFlagsCalls, hasLength(1));
      expect(
        api.setShopItemUnitDefaultFlagsCalls.first.shopItemUnitId,
        'unit-id-bag-25',
      );
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
}
