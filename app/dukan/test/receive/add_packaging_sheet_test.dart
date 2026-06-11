import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/receive/add_packaging_sheet.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeShopApi api;
  late AppLocalizations en;

  setUp(() {
    api = FakeShopApi();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<ReceiveUnitOption? Function()> pumpAndOpen(
    WidgetTester tester, {
    String shopId = 'shop-1',
    String shopItemId = 'si-1',
    String baseUnitCode = 'kg',
    String baseUnitLabel = 'Kg',
    String? categoryId,
    List<PackagingSuggestion> suggestions = const [],
  }) async {
    api.onSuggestItemPackagings = (_, _, _, _, _, _) async => suggestions;
    ReceiveUnitOption? captured;
    var didCapture = false;
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  captured = await AddPackagingSheet.show(
                    context,
                    shopId,
                    shopItemId,
                    baseUnitCode,
                    baseUnitLabel,
                    categoryId: categoryId,
                  );
                  didCapture = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        shopApi: api,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => didCapture ? captured : null;
  }

  Future<void> tapCustom(WidgetTester tester) async {
    await tester.tap(find.text(en.addPackagingCustomEntry));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'inline picker: chips + Custom render directly; ADD PACKAGING starts'
    ' disabled; "Less common" header appears between category and'
    ' cross_category groups',
    (tester) async {
      await pumpAndOpen(
        tester,
        suggestions: const [
          PackagingSuggestion(
            unitCode: 'bag',
            unitLabel: 'Bag',
            conversionToBase: 25,
            uses: 12,
            source: 'category',
          ),
          PackagingSuggestion(
            unitCode: 'bag',
            unitLabel: 'Bag',
            conversionToBase: 50,
            uses: 4,
            source: 'cross_category',
          ),
        ],
      );

      expect(find.text(en.addPackagingSuggestionsHeader), findsOneWidget);
      expect(find.text('25 Kg Bag'), findsOneWidget);
      expect(find.text('50 Kg Bag'), findsOneWidget);
      expect(find.text(en.addPackagingLessCommonHeader), findsOneWidget);
      expect(find.text(en.addPackagingCustomEntry), findsOneWidget);

      // ADD PACKAGING disabled before any pick.
      final initial = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.addPackagingSaveButton),
      );
      expect(initial.onPressed, isNull);
    },
  );

  testWidgets(
    'tapping a chip reveals the price field with packaging-aware label'
    ' and enables ADD PACKAGING; confirm calls createShopItemUnit',
    (tester) async {
      ({
        String shopId,
        String shopItemId,
        String unitCode,
        num conversionToBase,
        num? salePrice,
      })? createCall;
      api.onCreateShopItemUnit =
          (shopId, shopItemId, unitCode, conv, price) async {
        createCall = (
          shopId: shopId,
          shopItemId: shopItemId,
          unitCode: unitCode,
          conversionToBase: conv,
          salePrice: price,
        );
        return 'new-siu-id';
      };

      final readResult = await pumpAndOpen(
        tester,
        suggestions: const [
          PackagingSuggestion(
            unitCode: 'bag',
            unitLabel: 'Bag',
            conversionToBase: 25,
            uses: 12,
            source: 'category',
          ),
        ],
      );

      await tester.tap(find.text('25 Kg Bag'));
      await tester.pumpAndSettle();

      expect(
        find.text(en.addPackagingPickedPriceLabel('25 Kg Bag')),
        findsOneWidget,
      );

      // No price needed — ADD PACKAGING enables on pick.
      final enabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.addPackagingSaveButton),
      );
      expect(enabled.onPressed, isNotNull);

      await tester.tap(
        find.widgetWithText(FilledButton, en.addPackagingSaveButton),
      );
      await tester.pumpAndSettle();

      expect(createCall!.unitCode, 'bag');
      expect(createCall!.conversionToBase, 25);
      expect(createCall!.salePrice, isNull);

      final result = readResult()!;
      expect(result.shopItemUnitId, 'new-siu-id');
      expect(result.packagingLabel, '25 Kg Bag');
      expect(result.conversionToBase, 25);
    },
  );

  testWidgets(
    'custom mode: ADD PACKAGING disabled until a unit + positive,'
    ' non-1 conversion are entered',
    (tester) async {
      await pumpAndOpen(tester);
      await tapCustom(tester);

      await tester.tap(find.byType(DropdownButtonFormField<UnitOption>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bag').last);
      await tester.pumpAndSettle();

      final afterUnit = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.addPackagingSaveButton),
      );
      expect(afterUnit.onPressed, isNull);

      // Conversion of 0 invalid.
      await tester.enterText(find.byType(TextField).first, '0');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, en.addPackagingSaveButton),
            )
            .onPressed,
        isNull,
      );

      // Conversion of 1 invalid (= base packaging).
      await tester.enterText(find.byType(TextField).first, '1');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, en.addPackagingSaveButton),
            )
            .onPressed,
        isNull,
      );

      // Valid positive conversion → enabled.
      await tester.enterText(find.byType(TextField).first, '25');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, en.addPackagingSaveButton),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'custom mode conversion label uses base + chosen unit and the math-'
    'style phrasing ("How many Kg in 1 Bag?")',
    (tester) async {
      await pumpAndOpen(tester);
      await tapCustom(tester);

      await tester.tap(find.byType(DropdownButtonFormField<UnitOption>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bag').last);
      await tester.pumpAndSettle();

      expect(
        find.text(en.addPackagingConversionLabel('Kg', 'Bag')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'custom mode confirm: ADD PACKAGING calls createShopItemUnit and'
    ' pops with the synthesized ReceiveUnitOption',
    (tester) async {
      ({String unitCode, num conversionToBase, num? salePrice})? createCall;
      api.onCreateShopItemUnit =
          (shopId, shopItemId, unitCode, conv, price) async {
        createCall = (
          unitCode: unitCode,
          conversionToBase: conv,
          salePrice: price,
        );
        return 'new-siu-id';
      };

      final readResult = await pumpAndOpen(tester);
      await tapCustom(tester);

      await tester.tap(find.byType(DropdownButtonFormField<UnitOption>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bag').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '25');
      await tester.pump();

      await tester.tap(
        find.widgetWithText(FilledButton, en.addPackagingSaveButton),
      );
      await tester.pumpAndSettle();

      expect(createCall!.unitCode, 'bag');
      expect(createCall!.conversionToBase, 25);

      final result = readResult()!;
      expect(result.packagingLabel, '25 Kg Bag');
      expect(result.conversionToBase, 25);
    },
  );

  testWidgets(
    'custom mode hides the item base unit from the dropdown',
    (tester) async {
      await pumpAndOpen(
        tester,
        baseUnitCode: 'packet',
        baseUnitLabel: 'Packet',
      );
      await tapCustom(tester);

      await tester.tap(find.byType(DropdownButtonFormField<UnitOption>));
      await tester.pumpAndSettle();
      expect(find.text('Packet'), findsNothing);
      expect(find.text('Carton'), findsAtLeastNWidgets(1));
    },
  );
}
