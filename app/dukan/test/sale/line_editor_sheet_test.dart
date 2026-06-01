import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/sale/line_editor_sheet.dart';

import '../shared/wrap.dart';

void main() {
  late AppLocalizations en;

  setUp(() {
    en = lookupAppLocalizations(const Locale('en'));
  });

  /// Pump a host that opens the editor with the given config and returns
  /// a closure that reads back the LineEditorResult after the sheet is
  /// dismissed.
  Future<LineEditorResult? Function()> pumpAndOpen(
    WidgetTester tester, {
    required String itemName,
    String baseUnitLabel = 'Kg',
    int initialQuantity = 1,
    num? initialUnitPrice,
    bool priceRequired = false,
  }) async {
    LineEditorResult? captured;
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  captured = await showLineEditor(
                    context,
                    itemName: itemName,
                    baseUnitLabel: baseUnitLabel,
                    initialQuantity: initialQuantity,
                    initialUnitPrice: initialUnitPrice,
                    priceRequired: priceRequired,
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
    return () => captured;
  }

  testWidgets('priceRequired mode: helper visible, DONE disabled until price', (
    tester,
  ) async {
    await pumpAndOpen(
      tester,
      itemName: 'Caano qalaylan',
      priceRequired: true,
    );

    expect(find.text('Caano qalaylan'), findsOneWidget);
    expect(find.text(en.lineEditorPriceRequiredHelper), findsOneWidget);

    final doneButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, en.lineEditorDoneButton),
    );
    expect(doneButton.onPressed, isNull);

    // Typing a price enables DONE.
    await tester.enterText(find.byType(TextField), '4.5');
    await tester.pump();
    final doneEnabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, en.lineEditorDoneButton),
    );
    expect(doneEnabled.onPressed, isNotNull);
  });

  testWidgets('priceRequired mode: 0 is a valid explicit free-sale price', (
    tester,
  ) async {
    final readResult = await pumpAndOpen(
      tester,
      itemName: 'Sample',
      priceRequired: true,
    );

    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, en.lineEditorDoneButton),
    );
    await tester.pumpAndSettle();

    final result = readResult();
    expect(result, isNotNull);
    expect(result!.quantity, 1);
    expect(result.unitPrice, 0);
  });

  testWidgets('normal mode: price pre-filled, DONE enabled immediately', (
    tester,
  ) async {
    final readResult = await pumpAndOpen(
      tester,
      itemName: 'Bariis',
      initialUnitPrice: 1.5,
    );

    expect(find.text(en.lineEditorPriceRequiredHelper), findsNothing);
    final doneButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, en.lineEditorDoneButton),
    );
    expect(doneButton.onPressed, isNotNull);

    await tester.tap(
      find.widgetWithText(FilledButton, en.lineEditorDoneButton),
    );
    await tester.pumpAndSettle();

    final result = readResult();
    expect(result, isNotNull);
    expect(result!.quantity, 1);
    expect(result.unitPrice, 1.5);
  });

  testWidgets('qty stepper: + and - bounded at 1', (tester) async {
    final readResult = await pumpAndOpen(
      tester,
      itemName: 'Bariis',
      initialUnitPrice: 1.5,
    );

    // Start at 1, decrement should stay at 1.
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    // Increment three times → 4.
    await tester.tap(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('4'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(FilledButton, en.lineEditorDoneButton),
    );
    await tester.pumpAndSettle();

    expect(readResult()!.quantity, 4);
  });

  testWidgets('Cancel dismisses the sheet and returns null', (tester) async {
    final readResult = await pumpAndOpen(
      tester,
      itemName: 'Bariis',
      initialUnitPrice: 1.5,
    );

    await tester.tap(
      find.widgetWithText(OutlinedButton, en.cartClearConfirmNo),
    );
    await tester.pumpAndSettle();

    expect(readResult(), isNull);
  });

  testWidgets('editing an existing line: seeds qty and price', (tester) async {
    final readResult = await pumpAndOpen(
      tester,
      itemName: 'Sonkor',
      initialQuantity: 3,
      initialUnitPrice: 2,
    );

    expect(find.text('3'), findsOneWidget);
    // Override the price.
    await tester.enterText(find.byType(TextField), '5');
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, en.lineEditorDoneButton),
    );
    await tester.pumpAndSettle();

    final result = readResult();
    expect(result, isNotNull);
    expect(result!.quantity, 3);
    expect(result.unitPrice, 5);
  });
}
