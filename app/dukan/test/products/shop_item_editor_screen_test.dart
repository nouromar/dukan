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
    'SAVE & ADD ANOTHER commits, resets name + threshold, keeps base unit/category',
    (tester) async {
      api.onListUnits = () async => const [
            UnitOption(id: 'unit-kg', code: 'kg', label: 'Kg'),
          ];
      api.onListCategories = (_) async => const [
            CategoryOption(id: 'cat-1', code: 'staples', name: 'Staples'),
          ];
      await pumpEditor(tester);

      // Fill the form: name + base unit + category.
      await tester.enterText(
        find.widgetWithText(TextField, en.shopItemEditorNameLabel),
        'Bariis Cusub',
      );
      // Two String dropdowns exist (base unit + per-packaging unit) —
      // target the top one (base unit) via byType.first.
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kg').last);
      await tester.pumpAndSettle();
      // Category dropdown is the only DropdownButtonFormField<String?>.
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Staples').last);
      await tester.pumpAndSettle();

      // Drag the form ListView up to bring SAVE & ADD ANOTHER (near
      // the bottom) into view, then tap.
      await tester.drag(
        find
            .descendant(
              of: find.byType(ShopItemEditorScreen),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, -800),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(en.shopItemEditorSaveAndAddAnotherButton),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // The shop_item was created with name + category.
      expect(api.createShopItemCalls, hasLength(1));
      expect(api.createShopItemCalls.first.name, 'Bariis Cusub');
      expect(api.createShopItemCalls.first.categoryId, 'cat-1');

      // Crucially: we did NOT pop — the editor is still on the
      // navigator so the cashier can keep typing.
      expect(find.byType(ShopItemEditorScreen), findsOneWidget);
    },
  );
}
