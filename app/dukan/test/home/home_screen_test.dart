import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/home/home_screen.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;
  late FakeShopApi shopApi;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController();
    shopApi = FakeShopApi();
    en = lookupAppLocalizations(const Locale('en'));
  });

  testWidgets('AppBar carries the shop name + four daily actions render', (
    tester,
  ) async {
    final shop = fakeShop(name: 'Hodan Shop');

    await tester.pumpWidget(
      wrapWithApp(
        HomeScreen(shop: shop, onSignOut: () {}),
        authController: auth,
        shopApi: shopApi,
      ),
    );
    await tester.pumpAndSettle();

    // Shop name is now in the AppBar title (replaced the static
    // "Dukan" brand) — the in-body chip was removed to save space.
    expect(find.text('Hodan Shop'), findsOneWidget);
    expect(find.text(en.sale), findsOneWidget);
    expect(find.text(en.receive), findsOneWidget);
    // Payment was split into two tiles (#2 feedback).
    expect(find.text(en.paymentInLabel), findsOneWidget);
    expect(find.text(en.paymentOutLabel), findsOneWidget);
    expect(find.text(en.expense), findsOneWidget);
    // Products is the 6th tile on the home grid (also reachable from
    // the drawer with the same label).
    expect(find.text(en.drawerProducts), findsAtLeastNWidgets(1));
  });

  testWidgets('AppBar shows drawer hamburger + language globe (logout moved to drawer)', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(
        HomeScreen(shop: fakeShop(), onSignOut: () {}),
        authController: auth,
        shopApi: shopApi,
      ),
    );
    await tester.pumpAndSettle();

    // Scaffold's drawer auto-installs the hamburger menu icon.
    expect(find.byIcon(Icons.menu), findsOneWidget);
    // Language picker globe on the AppBar (replaces the old
    // logout button — logout is now inside the drawer).
    expect(find.byIcon(Icons.language), findsOneWidget);
    // Logout is no longer in the AppBar.
    expect(find.byIcon(Icons.logout), findsNothing);
  });

  testWidgets('opening drawer shows the grouped destinations', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        HomeScreen(shop: fakeShop(), onSignOut: () {}),
        authController: auth,
        shopApi: shopApi,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    // HISTORY group — four items.
    expect(find.text(en.drawerSalesHistory), findsOneWidget);
    expect(find.text(en.drawerReceiveHistory), findsOneWidget);
    expect(find.text(en.drawerExpenseHistory), findsOneWidget);
    expect(find.text(en.drawerPaymentHistory), findsOneWidget);
    // PEOPLE group — customers + suppliers (replaces the old
    // receivables/payables/parties trio).
    expect(find.text(en.drawerCustomers), findsOneWidget);
    expect(find.text(en.drawerSuppliers), findsOneWidget);

    // PRODUCTS group and SETUP group sit at the bottom — scroll the
    // drawer list to bring Settings (last item) into view first.
    await tester.scrollUntilVisible(
      find.text(en.drawerSettings),
      80,
      scrollable: find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    // drawerProducts is rendered in BOTH the drawer destinations and
    // the home grid tile (Batch B / #342) — accept "at least one"
    // since both surfaces are mounted.
    expect(find.text(en.drawerProducts), findsAtLeastNWidgets(1));
    // drawerLowStock shares its text with homeLowStockLabel on Home —
    // accept "at least one" since both surfaces are mounted.
    expect(find.text(en.drawerLowStock), findsAtLeastNWidgets(1));
    expect(find.text(en.drawerTopMovers), findsOneWidget);
    expect(find.text(en.drawerSettings), findsOneWidget);
  });

  testWidgets('drawer sign-out tile hidden when onSignOut is null', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        HomeScreen(shop: fakeShop()),
        authController: auth,
        shopApi: shopApi,
      ),
    );
    await tester.pumpAndSettle();

    // Open the drawer and verify the logout tile is absent.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.logout), findsNothing);
  });

  testWidgets(
    'today card renders all five activity rows + the attention section',
    (tester) async {
      shopApi.onGetTodaySummary = (_, _) async => const TodaySummary(
            salesToday: 1234,
            salesCount: 7,
            receivedToday: 300,
            receivedCount: 1,
            moneyInToday: 40,
            moneyInCount: 3,
            moneyOutToday: 0,
            moneyOutCount: 0,
            expensesToday: 12,
            expensesCount: 2,
            receivablesTotal: 50,
            payablesTotal: 20,
            lowStockCount: 3,
          );

      await tester.pumpWidget(
        wrapWithApp(
          HomeScreen(shop: fakeShop(), onSignOut: () {}),
          authController: auth,
          shopApi: shopApi,
        ),
      );
      await tester.pumpAndSettle();

      // Card defaults to COLLAPSED — shows the "Summary" teaser, body hidden.
      expect(find.text(en.homeSummaryLabel), findsOneWidget);
      expect(find.text(en.homeSalesTodayLabel), findsNothing);

      // Tap the header to expand.
      await tester.tap(find.text(en.homeSummaryLabel));
      await tester.pumpAndSettle();

      // Header now reads "Today"; the five activity rows + attention show.
      expect(find.text(en.homeTodayHeader), findsOneWidget);
      expect(find.text(en.homeSalesTodayLabel), findsOneWidget);
      expect(find.text(en.homeReceivedLabel), findsOneWidget);
      expect(find.text(en.homeMoneyInLabel), findsOneWidget);
      expect(find.text(en.homeMoneyOutLabel), findsOneWidget);
      expect(find.text(en.homeExpensesLabel), findsOneWidget);
      // Counts render in parens next to the money.
      expect(find.text('(7)'), findsOneWidget); // 7 sales
      expect(find.text('(0)'), findsOneWidget); // 0 money-out
      // Attention section.
      expect(find.text(en.homeNeedsAttentionLabel), findsOneWidget);
      expect(find.text(en.homeReceivablesLabel), findsOneWidget);
      expect(find.text(en.homePayablesLabel), findsOneWidget);
      expect(find.text(en.homeLowStockLabel), findsOneWidget);
      expect(find.text(en.homeLowStockCount(3)), findsOneWidget);
    },
  );

  testWidgets('the Today card expands and re-collapses on header tap', (
    tester,
  ) async {
    shopApi.onGetTodaySummary = (_, _) async => const TodaySummary(
          salesToday: 10,
          salesCount: 1,
          receivablesTotal: 5,
          payablesTotal: 0,
          lowStockCount: 0,
        );

    await tester.pumpWidget(
      wrapWithApp(
        HomeScreen(shop: fakeShop(), onSignOut: () {}),
        authController: auth,
        shopApi: shopApi,
      ),
    );
    await tester.pumpAndSettle();

    // Collapsed by default: "Summary" header, body hidden.
    expect(find.text(en.homeSummaryLabel), findsOneWidget);
    expect(find.text(en.homeSalesTodayLabel), findsNothing);

    // Tap to expand → header becomes "Today", body shows.
    await tester.tap(find.text(en.homeSummaryLabel));
    await tester.pumpAndSettle();
    expect(find.text(en.homeTodayHeader), findsOneWidget);
    expect(find.text(en.homeSalesTodayLabel), findsOneWidget);
    expect(find.text(en.homeNeedsAttentionLabel), findsOneWidget);

    // Tap the "Today" header to collapse again.
    await tester.tap(find.text(en.homeTodayHeader));
    await tester.pumpAndSettle();
    expect(find.text(en.homeSummaryLabel), findsOneWidget);
    expect(find.text(en.homeSalesTodayLabel), findsNothing);
  });

  testWidgets('tapping low-stock row navigates into the low-stock report', (
    tester,
  ) async {
    shopApi.onGetTodaySummary = (_, _) async => const TodaySummary(
          salesToday: 0,
          receivablesTotal: 0,
          payablesTotal: 0,
          lowStockCount: 2,
        );
    shopApi.onListLowStock = (_, _) async => const <LowStockRow>[];

    await tester.pumpWidget(
      wrapWithApp(
        HomeScreen(shop: fakeShop(), onSignOut: () {}),
        authController: auth,
        shopApi: shopApi,
      ),
    );
    await tester.pumpAndSettle();

    // Card is collapsed by default — expand it to reach the low-stock row.
    await tester.tap(find.text(en.homeSummaryLabel));
    await tester.pumpAndSettle();

    // The Today card sits in a scroll view above the action grid; on a
    // short test viewport the low-stock row can be off-screen.
    await tester.dragUntilVisible(
      find.text(en.homeLowStockLabel),
      find.byType(SingleChildScrollView),
      const Offset(0, -50),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.homeLowStockLabel));
    await tester.pumpAndSettle();
    // Surfacing the Future-loaded body
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text(en.lowStockReportTitle), findsAtLeastNWidgets(1));
  });
}
