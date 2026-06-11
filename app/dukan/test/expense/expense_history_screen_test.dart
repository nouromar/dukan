import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/expense/expense_history_screen.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

ExpenseSummary _row({
  String txnId = 'e-1',
  double amount = 12.5,
  String? categoryName = 'Electricity',
  String? paymentMethodCode = 'cash',
  String? notes,
}) {
  return ExpenseSummary(
    txnId: txnId,
    occurredAt: DateTime(2026, 6, 3, 14, 32),
    postedAt: DateTime(2026, 6, 3, 14, 32),
    amount: amount,
    paymentMethodCode: paymentMethodCode,
    categoryId: categoryName == null ? null : 'cat-$txnId',
    categoryName: categoryName,
    notes: notes,
  );
}

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
      wrapWithApp(ExpenseHistoryScreen(shop: shop), shopApi: api),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders expense rows with category + payment method',
      (tester) async {
    api.onListExpenses = (_, _, _) async => [
          _row(amount: 12, categoryName: 'Electricity'),
          _row(txnId: 'e-2', amount: 5, categoryName: 'Tea', notes: 'morning'),
        ];

    await pump(tester);

    expect(find.textContaining('Electricity'), findsOneWidget);
    expect(find.textContaining('Tea'), findsOneWidget);
  });

  testWidgets('empty state renders the empty message', (tester) async {
    api.onListExpenses = (_, _, _) async => const [];
    await pump(tester);
    expect(find.text(en.expenseHistoryEmptyMessage), findsOneWidget);
  });

  testWidgets('default scope is Today — subtitle reflects it', (tester) async {
    api.onListExpenses = (_, _, _) async => const [];
    await pump(tester);
    expect(find.text(en.dateRangeToday), findsOneWidget);
  });
}
