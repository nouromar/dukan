// Pre-#234 we had zero tests running in Locale('so'). A missing
// Somali ARB key would fail at runtime in production but pass every
// English test. This file pumps each daily-flow screen in Somali and
// asserts that:
//   1. The screen renders without throwing.
//   2. A representative Somali string appears — confirming the locale
//      actually applied (otherwise English fallback would silently
//      mask gaps).
// When a new screen is added, add it here too. When a daily-flow
// screen surfaces new text, this test catches a missing Somali key
// long before pilot.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/expense/expense_controller.dart';
import 'package:dukan/expense/expense_screen.dart';
import 'package:dukan/home/home_screen.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/payment/payment_controller.dart';
import 'package:dukan/payment/payment_screen.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/receive/receive_screen.dart';
import 'package:dukan/sale/cart_controller.dart';
import 'package:dukan/sale/sale_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late ShopSummary shop;
  late AppLocalizations so;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    shop = fakeShop();
    so = lookupAppLocalizations(const Locale('so'));
  });

  Future<void> pumpInSomali(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      wrapWithApp(
        child,
        authController: auth,
        shopApi: api,
        cartController: CartController(),
        receiveController: ReceiveController(),
        paymentController: PaymentController(),
        expenseController: ExpenseController(),
        locale: const Locale('so'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Home screen renders in Somali', (tester) async {
    api.onGetTodaySummary = (_, _) async => TodaySummary(
          salesToday: 0,
          receivablesTotal: 0,
          payablesTotal: 0,
          lowStockCount: 0,
        );
    await pumpInSomali(tester, HomeScreen(shop: shop));
    expect(find.text(so.homeHint), findsOneWidget);
  });

  testWidgets('Sale screen renders in Somali', (tester) async {
    api.onSearchItems = (_, _, _, _, _, _) async => const [];
    await pumpInSomali(tester, SaleScreen(shop: shop));
    expect(
      find.widgetWithText(FilledButton, so.saleSaveButton),
      findsOneWidget,
    );
  });

  testWidgets('Receive screen renders in Somali', (tester) async {
    api.onSearchItems = (_, _, _, _, _, _) async => const [];
    api.onSearchParties = (_, _, _, _) async => const [];
    await pumpInSomali(tester, ReceiveScreen(shop: shop));
    // Receive's SAVE label.
    expect(find.text(so.receiveSaveButton), findsWidgets);
  });

  testWidgets('Payment screen renders in Somali', (tester) async {
    api.onSearchParties = (_, _, _, _) async => const [];
    await pumpInSomali(tester, PaymentScreen(shop: shop));
    expect(
      find.widgetWithText(FilledButton, so.paymentSaveButton),
      findsOneWidget,
    );
  });

  testWidgets('Expense screen renders in Somali', (tester) async {
    api.onListExpenseCategories = (_, _) async => const [];
    await pumpInSomali(tester, ExpenseScreen(shop: shop));
    expect(
      find.widgetWithText(FilledButton, so.expenseSaveButton),
      findsOneWidget,
    );
  });
}
