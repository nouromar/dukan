import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/expense/expense_controller.dart';
import 'package:dukan/expense/expense_screen.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late ExpenseController expense;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    expense = ExpenseController();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pumpExpense(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        ExpenseScreen(shop: shop),
        authController: auth,
        shopApi: api,
        expenseController: expense,
      ),
    );
  }

  testWidgets('renders category chips from listExpenseCategories', (
    tester,
  ) async {
    api.onListExpenseCategories = (_, _) async => const [
      ExpenseCategoryOption(id: 'c1', code: 'rent', name: 'Rent'),
      ExpenseCategoryOption(id: 'c2', code: 'salary', name: 'Salary'),
    ];

    await pumpExpense(tester);
    await tester.pumpAndSettle();

    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
  });

  testWidgets('SAVE disabled until category + positive amount are set', (
    tester,
  ) async {
    api.onListExpenseCategories = (_, _) async => const [
      ExpenseCategoryOption(id: 'c1', code: 'rent', name: 'Rent'),
    ];

    await pumpExpense(tester);
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, en.expenseSaveButton),
    );
    expect(saveButton.onPressed, isNull);

    // Pick category — still no amount.
    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    final stillDisabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, en.expenseSaveButton),
    );
    expect(stillDisabled.onPressed, isNull);

    // Type amount.
    await tester.enterText(find.byType(TextField), '50');
    await tester.pump();
    final enabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, en.expenseSaveButton),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('SAVE posts the expense with category + amount + cash', (
    tester,
  ) async {
    api.onListExpenseCategories = (_, _) async => const [
      ExpenseCategoryOption(id: 'c1', code: 'rent', name: 'Rent'),
    ];
    Map<String, dynamic>? captured;
    api.onPostExpense = (
      shopId,
      categoryId,
      amount,
      methodCode,
      clientOpId,
      notes,
    ) async {
      captured = {
        'shopId': shopId,
        'categoryId': categoryId,
        'amount': amount,
        'methodCode': methodCode,
      };
      return 'fake-expense';
    };

    await pumpExpense(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '120');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, en.expenseSaveButton));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!['shopId'], shop.id);
    expect(captured!['categoryId'], 'c1');
    expect(captured!['amount'], 120);
    expect(captured!['methodCode'], 'cash');
  });
}
