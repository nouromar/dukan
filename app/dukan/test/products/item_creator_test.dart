import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/products/item_creator.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/sale/add_new_item_sheet.dart' show AddNewItemResult;
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/pending_post_dao.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeShopApi api;
  late ShopSummary shop;

  setUp(() {
    api = FakeShopApi();
    shop = fakeShop();
  });

  // Pump a host whose button runs [run] with a live BuildContext (so the
  // helper can read ShopApi / queue / repo from the tree), capturing its value.
  Future<T?> runWithContext<T>(
    WidgetTester tester,
    Future<T?> Function(BuildContext) run, {
    OfflineQueueController? queue,
    bool useLocalDb = false,
  }) async {
    T? captured;
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  captured = await run(context);
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
        shopApi: api,
        offlineQueueController: queue,
        configResolver: useLocalDb
            ? FakeConfigResolver(values: const {'use_local_db': true})
            : null,
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return captured;
  }

  OfflineQueueController drainingQueue(List<PendingPost> sink) {
    final queue = OfflineQueueController(
      dao: PendingPostDao(AppDatabase.instance()),
      executor: (p) async => sink.add(p),
      backoff: (_) => Duration.zero,
      clock: () => DateTime.utc(2026, 7, 11),
    );
    addTearDown(queue.dispose);
    return queue;
  }

  // --- createShopItemDraft --------------------------------------------------

  testWidgets('createShopItemDraft online → one create_shop_item with the pack',
      (tester) async {
    final result = await runWithContext<AddNewItemResult>(
      tester,
      (context) => createShopItemDraft(
        context,
        shop: shop,
        name: 'Bariis',
        categoryId: 'cat-1',
        baseUnitCode: 'kg',
        baseUnitLabel: 'Kg',
        soldUnitCode: 'bag',
        soldUnitLabel: 'Bag',
        soldConversion: 25,
        languageCode: 'en',
        defaultSide: 'receive',
        errorMessage: 'err',
      ),
    );

    expect(result, isNotNull);
    final call = api.createShopItemCalls.single;
    expect(call.name, 'Bariis');
    expect(call.baseUnitCode, 'kg');
    expect(call.soldUnitCode, 'bag');
    expect(call.soldConversion, 25);
    expect(call.defaultSide, 'receive');
    expect(call.categoryId, 'cat-1');
    // The returned default unit is the pack (default-receive) and the label is
    // synthesized "Bag (25 Kg)".
    expect(result!.shopItemUnitId, call.soldUnitId);
    expect(result.packagingLabel, isNotEmpty);
  });

  testWidgets('createShopItemDraft base-only online → soldUnitCode null',
      (tester) async {
    final result = await runWithContext<AddNewItemResult>(
      tester,
      (context) => createShopItemDraft(
        context,
        shop: shop,
        name: 'Loose Rice',
        baseUnitCode: 'kg',
        baseUnitLabel: 'Kg',
        languageCode: 'en',
        defaultSide: 'receive',
        errorMessage: 'err',
      ),
    );

    expect(result, isNotNull);
    final call = api.createShopItemCalls.single;
    expect(call.soldUnitCode, isNull);
    expect(call.soldUnitId, isNull);
    expect(result!.shopItemUnitId, call.baseUnitId);
  });

  testWidgets('createShopItemDraft transient → queued with the client ids',
      (tester) async {
    api.onCreateShopItem =
        (_, _, _, _, _, _, _, _, _) async => throw Exception('offline');
    final drained = <PendingPost>[];
    final queue = drainingQueue(drained);

    final result = await runWithContext<AddNewItemResult>(
      tester,
      (context) => createShopItemDraft(
        context,
        shop: shop,
        name: 'Bariis',
        baseUnitCode: 'kg',
        baseUnitLabel: 'Kg',
        soldUnitCode: 'bag',
        soldUnitLabel: 'Bag',
        soldConversion: 25,
        languageCode: 'en',
        defaultSide: 'receive',
        errorMessage: 'err',
      ),
      queue: queue,
      useLocalDb: true,
    );

    // Optimistic result returned, and the create is queued (not lost) with the
    // same client-minted ids + a client_op_id for idempotent drain.
    expect(result, isNotNull);
    final post = drained.singleWhere((p) => p.rpc == 'create_shop_item');
    expect(post.params['shop_item_id'], result!.shopItemId);
    expect(post.params['sold_unit_id'], result.shopItemUnitId);
    expect(post.params['default_side'], 'receive');
    expect(post.clientOpId, isNotNull);
  });

  // --- addShopItemUnitDraft -------------------------------------------------

  testWidgets('addShopItemUnitDraft online → one create_shop_item_unit',
      (tester) async {
    final added = await runWithContext<AddedUnit>(
      tester,
      (context) => addShopItemUnitDraft(
        context,
        shop: shop,
        shopItemId: 'si-1',
        unitCode: 'carton',
        unitLabel: 'Carton',
        baseUnitLabel: 'Kg',
        conversionToBase: 12,
        errorMessage: 'err',
      ),
    );

    expect(added, isNotNull);
    final call = api.createShopItemUnitCalls.single;
    expect(call.shopItemId, 'si-1');
    expect(call.unitCode, 'carton');
    expect(call.conversionToBase, 12);
    expect(added!.shopItemUnitId, call.shopItemUnitId);
    expect(added.packagingLabel, isNotEmpty);
  });

  testWidgets('addShopItemUnitDraft transient → queued with the client id',
      (tester) async {
    api.onCreateShopItemUnit =
        (_, _, _, _, _) async => throw Exception('offline');
    final drained = <PendingPost>[];
    final queue = drainingQueue(drained);

    final added = await runWithContext<AddedUnit>(
      tester,
      (context) => addShopItemUnitDraft(
        context,
        shop: shop,
        shopItemId: 'si-1',
        unitCode: 'carton',
        unitLabel: 'Carton',
        baseUnitLabel: 'Kg',
        conversionToBase: 12,
        errorMessage: 'err',
      ),
      queue: queue,
      useLocalDb: true,
    );

    expect(added, isNotNull);
    final post = drained.singleWhere((p) => p.rpc == 'create_shop_item_unit');
    expect(post.params['shop_item_unit_id'], added!.shopItemUnitId);
    expect(post.params['shop_item_id'], 'si-1');
    expect(post.params['conversion_to_base'], 12);
    expect(post.clientOpId, isNotNull);
  });
}
