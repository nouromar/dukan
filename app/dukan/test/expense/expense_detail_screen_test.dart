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

  const syncedId = '00000000-0000-4000-8000-0000000000e1';

  ExpenseSummary expense({
    bool voided = false,
    DateTime? posted,
    String txnId = syncedId,
  }) =>
      ExpenseSummary(
        txnId: txnId,
        occurredAt: DateTime(2026, 6, 20),
        postedAt: posted ?? DateTime.now(),
        amount: 12,
        paymentMethodCode: 'cash',
        categoryId: 'c1',
        categoryName: 'Rent',
        notes: 'June rent',
        isVoided: voided,
      );

  Future<void> pump(WidgetTester tester, {String txnId = syncedId}) async {
    await tester.pumpWidget(
      wrapWithApp(
        ExpenseDetailScreen(shop: shop, txnId: txnId),
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
    expect(api.voidExpenseCalls, contains('00000000-0000-4000-8000-0000000000e1'));
  });

  testWidgets('offline-created (unsynced) expense hides VOID + shows the '
      'sync hint (no non-UUID id sent to void_expense)', (tester) async {
    // A client_op_id placeholder id — what an offline post_expense mirrors
    // before the server assigns a real UUID.
    const localId = 'expense-1783095528341-3366287978';
    api.onGetExpense = (_, _) async => expense(txnId: localId);
    await pump(tester, txnId: localId);
    expect(find.text(en.expenseDetailVoidButton), findsNothing);
    expect(find.text(en.voidNotSyncedHint), findsOneWidget);
  });

  testWidgets('backdated expense (UUID id, but outside the window) hides VOID',
      (tester) async {
    // With a client-minted UUID id the sync gate passes, so the void window —
    // measured from the (backdated) postedAt — is the only thing gating VOID.
    api.onGetExpense =
        (_, _) async => expense(posted: DateTime(2020, 1, 1));
    await pump(tester);
    expect(find.text(en.expenseDetailVoidButton), findsNothing);
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
