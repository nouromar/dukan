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
    expect(find.text(en.payment), findsOneWidget);
    expect(find.text(en.expense), findsOneWidget);
  });

  testWidgets('drawer hamburger + sign-out icons appear when shop and onSignOut are set', (
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
    expect(find.byIcon(Icons.logout), findsOneWidget);
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
    expect(find.text(en.drawerProducts), findsOneWidget);
    // drawerLowStock shares its text with homeLowStockLabel on Home —
    // accept "at least one" since both surfaces are mounted.
    expect(find.text(en.drawerLowStock), findsAtLeastNWidgets(1));
    expect(find.text(en.drawerTopMovers), findsOneWidget);
    expect(find.text(en.drawerSettings), findsOneWidget);
  });

  testWidgets('sign-out icon hidden when onSignOut is null', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        HomeScreen(shop: fakeShop()),
        authController: auth,
        shopApi: shopApi,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.logout), findsNothing);
  });

  testWidgets(
    'today summary renders sales, receivables, payables, low-stock',
    (tester) async {
      shopApi.onGetTodaySummary = (_, _) async => const TodaySummary(
            salesToday: 1234,
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

      expect(find.text(en.homeTodayHeader), findsOneWidget);
      expect(find.text(en.homeSalesTodayLabel), findsOneWidget);
      expect(find.text(en.homeReceivablesLabel), findsOneWidget);
      expect(find.text(en.homePayablesLabel), findsOneWidget);
      expect(find.text(en.homeLowStockLabel), findsOneWidget);
      expect(find.text(en.homeLowStockCount(3)), findsOneWidget);
    },
  );

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
