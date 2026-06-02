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
                    baseUnitLabel: 'Kg',
                    itemId: 'i1',
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

  testWidgets('lists units from listItemUnits with default flagged', (
    tester,
  ) async {
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

    await pumpHostAndOpenSheet(tester);

    expect(find.text('Kg'), findsOneWidget);
    expect(find.text('Bag'), findsOneWidget);
    expect(find.text(en.unitPickerDefaultBadge), findsOneWidget);
    // Bag with conversion 25 should show "25 kg per bag"
    expect(find.text(en.unitPickerConversion('25', 'kg', 'bag')), findsOneWidget);
    // Kg with conversion 1 shows the "base unit" label
    expect(find.text(en.unitPickerBaseUnit), findsOneWidget);
  });

  testWidgets('tapping a unit returns it and closes the sheet', (tester) async {
    api.onListItemUnits = (_, _, _, _) async => const [
      ReceiveUnitOption(
        unitId: 'unit-bag',
        unitCode: 'bag',
        unitLabel: 'Bag',
        conversionToBase: 25,
        isDefault: true,
      ),
    ];

    final readResult = await pumpHostAndOpenSheet(tester);
    await tester.tap(find.text('Bag'));
    await tester.pumpAndSettle();

    final picked = readResult();
    expect(picked, isNotNull);
    expect(picked!.unitCode, 'bag');
  });
}
