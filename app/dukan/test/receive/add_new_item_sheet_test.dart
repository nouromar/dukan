import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/receive/add_new_item_sheet.dart';

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
    api.onFetchNewItemOptions = (_, _) async => const NewItemOptions(
          baseUnits: [BaseUnitOption(unitCode: 'kg', unitLabel: 'Kg', uses: 3)],
          packagedUnits: [],
        );
  });

  Future<AddNewItemResult? Function()> pumpAndOpen(
    WidgetTester tester, {
    String initialName = 'Caano',
  }) async {
    AddNewItemResult? captured;
    var didCapture = false;
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  captured = await AddNewItemSheet.show(
                    context,
                    shop,
                    initialName: initialName,
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

  testWidgets(
    'receive variant: trigger prompt is "How did the supplier deliver?"'
    ' and the price field is never shown',
    (tester) async {
      await pumpAndOpen(tester, initialName: 'Caano');

      expect(find.text(en.addNewItemHowDeliveredHeader), findsOneWidget);
      expect(find.text(en.addNewItemHowSoldHeader), findsNothing);

      // Single base unit (kg) → tapping the inline "Loose" chip auto-
      // picks "By Kg" without opening a sub-sheet.
      await tester.tap(find.text(en.addNewItemLooseType));
      await tester.pumpAndSettle();

      // Receive variant: price field stays hidden even after a pick.
      expect(
        find.text(en.addNewItemPickedPriceLabel('Kg')),
        findsNothing,
      );

      // Button enables immediately on pick (no price required).
      final enabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.addNewItemAddToReceiveButton),
      );
      expect(enabled.onPressed, isNotNull);
    },
  );

  testWidgets(
    'receive variant: button label uses addNewItemAddToReceiveButton',
    (tester) async {
      await pumpAndOpen(tester, initialName: 'Caano');

      expect(
        find.widgetWithText(FilledButton, en.addNewItemAddToReceiveButton),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, en.addNewItemAddToSaleButton),
        findsNothing,
      );
    },
  );

  testWidgets(
    'receive variant: confirm calls createShopItem with defaultSide=receive,'
    ' no listShopItemUnits round trip',
    (tester) async {
      ({String defaultSide, num? salePrice})? createCall;
      api.onCreateShopItem =
          (_, _, _, _, salePrice, _, _, _, defaultSide) async {
            createCall = (defaultSide: defaultSide, salePrice: salePrice);
            return (
              shopItemId: 'new-id',
              defaultShopItemUnitId: 'siu-new',
            );
          };
      var listCalls = 0;
      api.onListShopItemUnits = (_, _, _) async {
        listCalls++;
        return const [];
      };

      final readResult = await pumpAndOpen(tester, initialName: 'Caano');
      // Single base unit (kg) → tap inline Loose chip auto-picks By Kg.
      await tester.tap(find.text(en.addNewItemLooseType));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(FilledButton, en.addNewItemAddToReceiveButton),
      );
      await tester.pumpAndSettle();

      expect(createCall, isNotNull);
      expect(createCall!.defaultSide, 'receive');
      expect(createCall!.salePrice, isNull);
      // Sheet synthesizes the packaging label locally — no extra trip.
      expect(listCalls, 0);

      // The sheet mints the ids client-side (0095) and returns THOSE —
      // base-only, so the default unit is the base unit.
      final result = readResult();
      expect(result, isNotNull);
      expect(result!.shopItemId, isNotEmpty);
      expect(result.shopItemId, api.createShopItemCalls.last.shopItemId);
      expect(result.shopItemUnitId, api.createShopItemCalls.last.baseUnitId);
      expect(api.createShopItemCalls.last.clientOpId, isNotNull);
      expect(result.salePrice, isNull);
    },
  );
}
