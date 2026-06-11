import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/products/top_movers_screen.dart';

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

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(TopMoversScreen(shop: shop), shopApi: api),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders Top sellers + Dead stock segments', (tester) async {
    api.onListProductVelocity = (_, _, _, _) async => const ProductVelocity(
          top: [
            TopMoverRow(
              shopItemId: 'a',
              displayName: 'Bariis',
              baseUnitCode: 'kg',
              baseUnitLabel: 'Kg',
              unitsSoldBase: 42,
              revenue: 42.50,
              salesCount: 8,
            ),
          ],
          dead: [
            DeadStockRow(
              shopItemId: 'b',
              displayName: 'Coffee Bag',
              baseUnitCode: 'kg',
              baseUnitLabel: 'Kg',
              currentStock: 3,
            ),
          ],
        );

    await pump(tester);

    // Section headers render UPPERCASE by design.
    expect(find.text(en.topMoversTopSegment.toUpperCase()), findsOneWidget);
    expect(find.text('Bariis'), findsOneWidget);
    expect(find.text('\$42.50'), findsOneWidget);
    expect(find.text(en.topMoversDeadSegment.toUpperCase()), findsOneWidget);
    expect(find.text('Coffee Bag'), findsOneWidget);
  });

  testWidgets('empty data renders the empty message', (tester) async {
    api.onListProductVelocity = (_, _, _, _) async =>
        const ProductVelocity(top: [], dead: []);
    await pump(tester);
    expect(find.text(en.topMoversEmptyMessage), findsOneWidget);
  });

  testWidgets('period picker re-fetches with the new periodDays',
      (tester) async {
    var observed = -1;
    api.onListProductVelocity = (_, days, _, _) async {
      observed = days;
      return const ProductVelocity(top: [], dead: []);
    };
    await pump(tester);
    expect(observed, 7);

    // Open the period picker and select 30 days.
    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.topMoversPeriodOption(30)).last);
    await tester.pumpAndSettle();

    expect(observed, 30);
  });
}
