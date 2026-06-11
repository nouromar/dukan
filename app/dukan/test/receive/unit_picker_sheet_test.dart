import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/receive/unit_picker_sheet.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<ReceiveUnitOption? Function()> pumpHostAndOpenSheet(
    WidgetTester tester,
  ) async {
    ReceiveUnitOption? captured;
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  captured = await showUnitPicker(
                    context,
                    shopId: 'shop-1',
                    shopItemId: 'si-1',
                    screen: 'receive',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        authController: auth,
        shopApi: api,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => captured;
  }

  testWidgets('lists units from listShopItemUnits with default flagged', (
    tester,
  ) async {
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
        shopItemUnitId: 'siu-bag-25',
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

    await pumpHostAndOpenSheet(tester);

    // Packaging labels are what the picker renders.
    expect(find.text('Kg'), findsOneWidget);
    expect(find.text('25 Kg Bag'), findsOneWidget);
    expect(find.text(en.unitPickerDefaultBadge), findsOneWidget);
    // The base unit row carries the "base unit" badge.
    expect(find.text(en.unitPickerBaseUnit), findsOneWidget);
  });

  testWidgets('tapping a unit returns it and closes the sheet', (tester) async {
    api.onListShopItemUnits = (_, _, _) async => const [
      ReceiveUnitOption(
        shopItemUnitId: 'siu-bag-25',
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

    final readResult = await pumpHostAndOpenSheet(tester);
    await tester.tap(find.text('25 Kg Bag'));
    await tester.pumpAndSettle();

    final picked = readResult();
    expect(picked, isNotNull);
    expect(picked!.unitCode, 'bag');
    expect(picked.shopItemUnitId, 'siu-bag-25');
  });
}
