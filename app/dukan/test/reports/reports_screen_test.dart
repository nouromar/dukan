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
    // Profit: gross $40.00, net $30.00, margin 40%.
    expect(find.text('\$40.00'), findsOneWidget);
    expect(find.text('\$30.00'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    // Stock: 12 items, value $250.00, 3 low.
    expect(find.text('12'), findsOneWidget);
    expect(find.text('\$250.00'), findsOneWidget);
  });
}
