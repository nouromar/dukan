// #383: when useLocalDb=false the Expense screen posts directly
// via ShopApi and does NOT enqueue on failure. These tests assert
// both shapes (success + failure) and confirm zero rows land in
// `pending_post` either way.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/expense/expense_controller.dart';
import 'package:dukan/expense/expense_screen.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/device_config_dao.dart';
import 'package:dukan/storage/pending_post_dao.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late ExpenseController expense;
  late ShopSummary shop;
  late AppLocalizations en;
  late PendingPostDao postDao;
  late OfflineQueueController queue;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    expense = ExpenseController();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
    postDao = PendingPostDao(AppDatabase.instance());
    queue = OfflineQueueController(
      dao: postDao,
      executor: (_) async {},
      backoff: (_) => Duration.zero,
    );
  });

  tearDown(() => queue.dispose());

  Future<void> pumpWithUseLocalDbOff(WidgetTester tester) async {
    final resolver = _StubResolver(
      {'use_local_db': false},
      AppDatabase.instance(),
    );
    await tester.pumpWidget(
      wrapWithApp(
        ExpenseScreen(shop: shop),
        authController: auth,
        shopApi: api,
        expenseController: expense,
        offlineQueueController: queue,
        configResolver: resolver,
      ),
    );
  }

  testWidgets('useLocalDb=false: posts directly to ShopApi.postExpense',
      (tester) async {
    api.onListExpenseCategories = (_, _) async => const [
          ExpenseCategoryOption(id: 'c1', code: 'rent', name: 'Rent'),
        ];
    var postCalls = 0;
    api.onPostExpense = (
      shopId,
      categoryId,
      amount,
      method,
      clientOpId,
      notes,
    ) async {
      postCalls++;
      expect(categoryId, 'c1');
      expect(amount, 50);
      expect(method, 'cash');
      return 'fake-expense-id';
    };
    final before = (await tester.runAsync(() => postDao.load()))!.length;

    await pumpWithUseLocalDbOff(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '50');
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, en.expenseSaveButton),
    );
    await tester.pumpAndSettle();

    expect(postCalls, 1);
    final after = (await tester.runAsync(() => postDao.load()))!.length;
    expect(after, before, reason: 'no pending_post row should be written');
  });

  testWidgets('useLocalDb=false: failure shows error toast, no queue row',
      (tester) async {
    api.onListExpenseCategories = (_, _) async => const [
          ExpenseCategoryOption(id: 'c1', code: 'rent', name: 'Rent'),
        ];
    api.onPostExpense = (_, _, _, _, _, _) async {
      throw StateError('network down');
    };
    final before = (await tester.runAsync(() => postDao.load()))!.length;

    await pumpWithUseLocalDbOff(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '50');
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, en.expenseSaveButton),
    );
    await tester.pumpAndSettle();

    // _saveDirect reports the post failure via FlutterError.reportError
    // (observability) before showing the inline error — consume that
    // expected error so it doesn't fail the test.
    expect(tester.takeException(), isA<StateError>());
    expect(
      find.textContaining(en.expensePostFailedMessage),
      findsWidgets,
    );
    final after = (await tester.runAsync(() => postDao.load()))!.length;
    expect(after, before, reason: 'failure must NOT enqueue');
  });
}

class _StubResolver extends ConfigResolver {
  _StubResolver(this._values, Future<AppDatabase> dbFuture)
      : super(
          shopApi: FakeShopApi(),
          deviceConfigDao: DeviceConfigDao(dbFuture),
        );
  final Map<String, dynamic> _values;

  @override
  T resolve<T>(ConfigKey<T> key) {
    if (_values.containsKey(key.name)) return _values[key.name] as T;
    return key.defaultValue;
  }

  @override
  Object? rawOverride(String keyName) {
    if (_values.containsKey(keyName)) return _values[keyName];
    return super.rawOverride(keyName);
  }
}
