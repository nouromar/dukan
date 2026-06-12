import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/reports/low_stock_screen.dart';

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

  testWidgets('Low-stock report renders the empty state when nothing is low',
      (tester) async {
    api.onListLowStock = (_, _) async => const <LowStockRow>[];

    await tester.pumpWidget(
      wrapWithApp(LowStockScreen(shop: shop), shopApi: api),
    );
    await tester.pumpAndSettle();

    expect(find.text(en.lowStockReportEmptyMessage), findsOneWidget);
  });

  testWidgets('Low-stock report renders items with their stock label',
      (tester) async {
    api.onListLowStock = (_, _) async => const [
      LowStockRow(
        shopItemId: 'si-1',
        displayName: 'Bariis',
        currentStock: 0,
        reorderThreshold: 5,
        baseUnitCode: 'kg',
        baseUnitLabel: 'Kg',
      ),
    ];

    await tester.pumpWidget(
      wrapWithApp(LowStockScreen(shop: shop), shopApi: api),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bariis'), findsOneWidget);
    // Empty state must NOT appear when there is at least one row.
    expect(find.text(en.lowStockReportEmptyMessage), findsNothing);
  });

  testWidgets('search input filters to matching items only', (tester) async {
    api.onListLowStock = (_, _) async => const [
      LowStockRow(
        shopItemId: 'si-1',
        displayName: 'Bariis',
        currentStock: 0,
        reorderThreshold: 5,
        baseUnitCode: 'kg',
        baseUnitLabel: 'Kg',
      ),
      LowStockRow(
        shopItemId: 'si-2',
        displayName: 'Sonkor',
        currentStock: 0,
        reorderThreshold: 5,
        baseUnitCode: 'kg',
        baseUnitLabel: 'Kg',
      ),
    ];

    await tester.pumpWidget(
      wrapWithApp(LowStockScreen(shop: shop), shopApi: api),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bariis'), findsOneWidget);
    expect(find.text('Sonkor'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'son');
    await tester.pumpAndSettle();

    expect(find.text('Bariis'), findsNothing);
    expect(find.text('Sonkor'), findsOneWidget);
  });
}
