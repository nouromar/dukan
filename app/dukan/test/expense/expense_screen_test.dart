import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/expense/expense_controller.dart';
import 'package:dukan/expense/expense_screen.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/shared/client_op_id.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/pending_post_dao.dart';

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

  testWidgets('SAVE is in the body, not a bottomNavigationBar (keyboard-safe)',
      (tester) async {
    api.onListExpenseCategories = (_, _) async => const [
      ExpenseCategoryOption(id: 'c1', code: 'rent', name: 'Rent'),
    ];
    await pumpExpense(tester);
    await tester.pumpAndSettle();

    // The bottom nav bar (which iOS hides under the keyboard) is gone; SAVE
    // lives in the resizable body so it floats above the keyboard.
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
      isNull,
    );
    expect(
      find.widgetWithText(FilledButton, en.expenseSaveButton),
      findsOneWidget,
    );
  });

  testWidgets('tapping outside the amount field closes the keyboard',
      (tester) async {
    api.onListExpenseCategories = (_, _) async => const [
      ExpenseCategoryOption(id: 'c1', code: 'rent', name: 'Rent'),
    ];
    await pumpExpense(tester);
    await tester.pumpAndSettle();

    // Focus the amount field.
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    final node =
        tester.widget<EditableText>(find.byType(EditableText).first).focusNode;
    expect(node.hasFocus, isTrue);

    // Tap a category (anywhere outside the field) → onTapOutside → unfocus.
    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    expect(node.hasFocus, isFalse);
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
    await tester.enterText(find.byType(TextField).first, '50');
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
    await tester.enterText(find.byType(TextField).first, '120');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, en.expenseSaveButton));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!['shopId'], shop.id);
    expect(captured!['categoryId'], 'c1');
    expect(captured!['amount'], 120);
    expect(captured!['methodCode'], 'cash');
  });

  testWidgets(
    '#367 transient post_expense failure enqueues to the offline queue',
    (tester) async {
      FlutterError.onError = (_) {};
      api.onListExpenseCategories = (_, _) async => const [
        ExpenseCategoryOption(id: 'c1', code: 'rent', name: 'Rent'),
      ];
      api.onPostExpense =
          (_, _, _, _, _, _) async => throw Exception('connection reset');

      final drained = <Object>[];
      final queue = OfflineQueueController(
        dao: PendingPostDao(AppDatabase.instance()),
        executor: (post) async => drained.add(post),
        backoff: (_) => Duration.zero,
      );

      await tester.pumpWidget(
        wrapWithApp(
          ExpenseScreen(shop: shop),
          authController: auth,
          shopApi: api,
          expenseController: expense,
          offlineQueueController: queue,
          // #383-fixup: queue path lives in useLocalDb=true branch.
          configResolver:
              FakeConfigResolver(values: const {'use_local_db': true}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rent'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '120');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, en.expenseSaveButton));
      await tester.pumpAndSettle();

      // Exactly one post flowed through the queue's executor with
      // rpc='post_expense'.
      expect(drained, hasLength(1));
      final post = drained.single as PendingPost;
      expect(post.rpc, 'post_expense');
      expect(post.shopId, shop.id);
      expect(post.params['expense_category_id'], 'c1');
      expect(post.params['amount'], 120);
      // The queued post carries a client-minted UUID txn id (not the
      // client_op_id placeholder) so an offline expense can be voided before
      // it syncs — the whole point of migration 0097.
      final txnId = post.params['txn_id'] as String?;
      expect(txnId, isNotNull);
      expect(isStableTxnId(txnId!), isTrue);
    },
  );
}
