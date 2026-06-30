import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/auth/capabilities.dart';
import 'package:dukan/expense/expense_detail_screen.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController(
      capabilities: Capabilities.forTesting(const ['expense.void']),
    );
    api = FakeShopApi();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  ExpenseSummary expense({bool voided = false, DateTime? posted}) =>
      ExpenseSummary(
        txnId: 'exp-1',
        occurredAt: DateTime(2026, 6, 20),
        postedAt: posted ?? DateTime.now(),
        amount: 12,
        paymentMethodCode: 'cash',
        categoryId: 'c1',
        categoryName: 'Rent',
        notes: 'June rent',
        isVoided: voided,
      );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        ExpenseDetailScreen(shop: shop, txnId: 'exp-1'),
        authController: auth,
        shopApi: api,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders category + amount + VOID for an owner', (tester) async {
    api.onGetExpense = (_, _) async => expense();
    await pump(tester);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('\$12.00'), findsOneWidget);
    expect(find.text(en.expenseDetailVoidButton), findsOneWidget);
  });

  testWidgets('VOID → confirm posts void_expense', (tester) async {
    api.onGetExpense = (_, _) async => expense();
    await pump(tester);
    await tester.tap(find.text(en.expenseDetailVoidButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.expenseVoidConfirmYes));
    await tester.pumpAndSettle();
    expect(api.voidExpenseCalls, contains('exp-1'));
  });

  testWidgets('cashier without expense.void sees no VOID', (tester) async {
    auth = FakeAuthController(capabilities: Capabilities.forTesting(const []));
    api.onGetExpense = (_, _) async => expense();
    await pump(tester);
    expect(find.text(en.expenseDetailVoidButton), findsNothing);
  });

  testWidgets('already-voided expense shows the banner, no VOID',
      (tester) async {
    api.onGetExpense = (_, _) async => expense(voided: true);
    await pump(tester);
    expect(find.text(en.saleDetailVoidedHeader), findsOneWidget);
    expect(find.text(en.expenseDetailVoidButton), findsNothing);
  });
}
