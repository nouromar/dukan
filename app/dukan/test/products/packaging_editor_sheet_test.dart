// Smoke test for the packaging editor sheet (#348). The sheet replaces
// the old inline _PackagingRow form rows on the New Item editor; tap
// "+ Add packaging" → sheet opens with empty fields; tap a summary
// row in edit mode → sheet opens pre-filled.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/products/packaging_editor_sheet.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

const _units = [
  UnitOption(id: 'unit-kg', code: 'kg', label: 'Kg'),
  UnitOption(id: 'unit-bag', code: 'bag', label: 'Bag'),
];

Future<PackagingDraftSubmission?> _openSheet(
  WidgetTester tester, {
  PackagingDraftSubmission? initial,
}) async {
  final shop = fakeShop();
  PackagingDraftSubmission? captured;
  await tester.pumpWidget(
    wrapWithApp(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await showPackagingEditorSheet(
                  context,
                  shop: shop,
                  units: _units,
                  baseUnitLabel: 'Kg',
                  baseUnitCode: 'kg',
                  initial: initial,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  late AppLocalizations en;
  setUp(() {
    en = lookupAppLocalizations(const Locale('en'));
  });

  testWidgets('opens empty with "Add packaging" title', (tester) async {
    await _openSheet(tester);
    expect(find.text(en.packagingEditorAddTitle), findsOneWidget);
    // Unit dropdown empty; conversion / price / cost / stock blank.
    final saveButton = find.widgetWithText(
      FilledButton,
      en.packagingEditorSaveButton,
    );
    expect(saveButton, findsOneWidget);
  });

  testWidgets('pre-fills when an existing draft is passed (Edit title)',
      (tester) async {
    await _openSheet(
      tester,
      initial: const PackagingDraftSubmission(
        unitCode: 'bag',
        conversion: 25,
        salePrice: 50,
        cost: 45,
        openingStock: 3,
        barcode: '6291100123456',
      ),
    );
    expect(find.text(en.packagingEditorEditTitle), findsOneWidget);
    // Pre-filled values render as the field text.
    expect(find.text('25'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text(en.shopItemEditorBarcodeBoundLabel('6291100123456')),
        findsOneWidget);
  });

  testWidgets(
      'SAVE with default base unit and no other fields returns a base submission',
      (tester) async {
    // Post-#356 the sheet always seeds the unit dropdown with
    // `defaultUnitCode` (which the parent passes as the item's base
    // unit). So the "no unit picked" branch is no longer reachable
    // from the editor — SAVE on a fresh sheet succeeds and the
    // result is a base-unit submission with conversion 1.
    final shop = fakeShop();
    PackagingDraftSubmission? captured;
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showPackagingEditorSheet(
                    context,
                    shop: shop,
                    units: _units,
                    baseUnitLabel: 'Kg',
                    baseUnitCode: 'kg',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, en.packagingEditorSaveButton),
    );
    await tester.pumpAndSettle();
    expect(captured, isNotNull);
    expect(captured!.unitCode, 'kg');
    expect(captured!.conversion, 1);
  });

  testWidgets('SAVE returns a populated submission when fields are valid',
      (tester) async {
    // Drive: open sheet → pick Bag → conversion 12 → price 30 → SAVE.
    // We use the same Builder pattern but capture the result via
    // tester's runZoned-style trick by re-using _openSheet's body
    // inline with a settled callback.
    final shop = fakeShop();
    PackagingDraftSubmission? captured;
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showPackagingEditorSheet(
                    context,
                    shop: shop,
                    units: _units,
                    baseUnitLabel: 'Kg',
                    baseUnitCode: 'kg',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Pick Bag from the unit dropdown.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bag').last);
    await tester.pumpAndSettle();
    // Fill conversion + price (cost/stock/barcode optional).
    final convField = find.widgetWithText(
      TextField,
      en.addPackagingConversionLabel('Kg', 'Bag'),
    );
    await tester.enterText(convField, '12');
    final priceField =
        find.widgetWithText(TextField, en.addPackagingPriceLabel('Bag'));
    await tester.enterText(priceField, '30');
    await tester.tap(
      find.widgetWithText(FilledButton, en.packagingEditorSaveButton),
    );
    await tester.pumpAndSettle();
    expect(captured, isNotNull);
    expect(captured!.unitCode, 'bag');
    expect(captured!.conversion, 12);
    expect(captured!.salePrice, 30);
  });
}
