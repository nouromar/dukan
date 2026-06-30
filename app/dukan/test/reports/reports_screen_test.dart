import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/reports/reports_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  testWidgets('renders Sales / Profit / Stock cards from the reports',
      (tester) async {
    api.onGetProfitReport = (from, to) => const ProfitReport(
          revenue: 100,
          cogs: 60,
          grossProfit: 40,
          expenseTotal: 10,
          netProfit: 30,
          saleCount: 5,
          expenseCount: 2,
        );
    api.onGetStockReport = () => const StockReport(
          itemCount: 12,
          stockValue: 250,
          lowStockCount: 3,
        );

    await tester.pumpWidget(
      wrapWithApp(
        ReportsScreen(shop: shop),
        authController: auth,
        shopApi: api,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(en.reportsSalesTitle), findsOneWidget);
    expect(find.text(en.reportsProfitTitle), findsOneWidget);
    expect(find.text(en.reportsStockTitle), findsOneWidget);

    // Sales: total $100.00, 5 sales, avg $20.00.
    expect(find.text('\$100.00'), findsOneWidget);
    expect(find.text('5'), findsWidgets);
    expect(find.text('\$20.00'), findsOneWidget);
    // Profit: gross $40.00, net $30.00, NET margin 30% (net ÷ revenue).
    expect(find.text('\$40.00'), findsOneWidget);
    expect(find.text('\$30.00'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    // Stock: 12 items, value $250.00, 3 low.
    expect(find.text('12'), findsOneWidget);
    expect(find.text('\$250.00'), findsOneWidget);
  });

  test('marginPct is net margin (matches the bottom line, incl. losses)', () {
    // A gross-profitable but expense-heavy period: gross 207.47, expenses 300
    // → net -92.53. Margin must be net ÷ revenue (negative), not gross.
    const p = ProfitReport(
      revenue: 247.80,
      cogs: 40.33,
      grossProfit: 207.47,
      expenseTotal: 300,
      netProfit: -92.53,
      saleCount: 8,
      expenseCount: 1,
    );
    // -92.53 / 247.80 * 100 ≈ -37.3%
    expect(p.marginPct, closeTo(-37.3, 0.1));
  });
}
