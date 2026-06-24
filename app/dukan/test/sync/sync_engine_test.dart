// Unit tests for SyncEngine — full sync, delta sync, self-echo
// filtering, and bulk-burst debouncing.

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/pending_post_dao.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/sync_engine.dart';

import '../shared/fakes.dart';
import '../shared/test_database.dart';

void main() {
  late AppDatabase database;
  late LocalRepository repo;
  late PendingPostDao postDao;
  late FakeShopApi api;
  const shopId = 'shop-1';

  setUp(() async {
    database = await openTestDatabase();
    final dbFuture = Future.value(database);
    repo = LocalRepository(dbFuture);
    postDao = PendingPostDao(dbFuture);
    api = FakeShopApi();
  });

  tearDown(() async {
    await database.close();
  });

  test('first start runs a full sync and populates local mirror',
      () async {
    api.onGetShopFullSync = ({required shopId, force = false}) async => {
          'server_now_ms': 1700000000000,
          'items_payload': {
            'items': [
              {
                'shop_item_id': 'si-1',
                'shop_id': shopId,
                'item_id': null,
                'display_name': 'Rice 5kg',
                'category_id': null,
                'base_unit_code': 'kg',
                'current_stock': 12,
                'avg_cost': 5,
                'reorder_threshold': null,
                'is_active': true,
                'server_updated_at_ms': 1700000000000,
              },
            ],
            'units': const [],
            'aliases': const [],
            'barcodes': const [],
          },
          'parties_payload': {'parties': const []},
          'categories_payload': {
            'expense_categories': const [],
            'categories': const [],
            'units': const [],
          },
          'transactions_payload': {'transactions': const []},
        };

    final engine = SyncEngine(
      shopApi: api,
      localRepository: repo,
      pendingPostDao: postDao,
    );
    await engine.start(shopId);

    expect(engine.state, SyncEngineState.live);
    expect(engine.hasInitialSync, isTrue);
    final hit = await repo.getShopItem('si-1');
    expect(hit, isNotNull);
    expect(hit!.displayName, 'Rice 5kg');

    final state = await repo.loadSyncState(shopId);
    expect(state.length, 4);
    for (final s in state.values) {
      expect(s.fullSyncDone, isTrue);
      expect(s.lastSyncedAtMs, 1700000000000);
    }
    engine.dispose();
  });

  test('start with existing sync state skips full sync and runs delta',
      () async {
    // Seed prior sync state so the engine takes the delta path.
    for (final resource in SyncResource.all) {
      await repo.writeSyncState(
        shopId: shopId,
        resource: resource,
        lastSyncedAtMs: 1700000000000,
        fullSyncDone: true,
      );
    }
    var fullCalls = 0;
    api.onGetShopFullSync = ({required shopId, force = false}) async {
      fullCalls += 1;
      return const <String, dynamic>{};
    };
    api.onGetShopItemsDelta = ({required shopId, required since}) async => {
          'items': [
            {
              'shop_item_id': 'si-new',
              'shop_id': shopId,
              'item_id': null,
              'display_name': 'New Item',
              'category_id': null,
              'base_unit_code': 'kg',
              'current_stock': 0,
              'avg_cost': 0,
              'reorder_threshold': null,
              'is_active': true,
              'server_updated_at_ms': 1700000001000,
            },
          ],
          'units': const [],
          'aliases': const [],
          'barcodes': const [],
          'server_now_ms': 1700000001000,
        };

    final engine = SyncEngine(
      shopApi: api,
      localRepository: repo,
      pendingPostDao: postDao,
    );
    await engine.start(shopId);
    // Let the unawaited deltaSync finish.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(fullCalls, 0);
    final hit = await repo.getShopItem('si-new');
    expect(hit, isNotNull);
    expect(api.getShopItemsDeltaCalls, isNotEmpty);
    engine.dispose();
  });

  test('self-echo: realtime event matching a pending post clears projection',
      () async {
    final post = PendingPost(
      id: 'pp-1',
      clientOpId: 'op-echo',
      shopId: shopId,
      originalActorUserId: 'u-1',
      rpc: 'post_sale',
      params: const <String, dynamic>{},
      queuedAt: DateTime.utc(2026, 1, 1),
    );
    await postDao.insert(post);
    await repo.writeProjection(
      pendingPostId: 'pp-1',
      shopItemId: 'si-1',
      delta: -3,
    );
    await repo.applyItemsPayload({
      'items': [
        {
          'shop_item_id': 'si-1',
          'shop_id': shopId,
          'item_id': null,
          'display_name': 'Rice',
          'category_id': null,
          'base_unit_code': 'kg',
          'current_stock': 10,
          'avg_cost': 0,
          'reorder_threshold': null,
          'is_active': true,
          'server_updated_at_ms': 1,
        },
      ],
      'units': const [],
      'aliases': const [],
      'barcodes': const [],
    });
    expect(await repo.projectedStock('si-1'), 7);

    // Seed sync state so start() doesn't try a full sync.
    for (final resource in SyncResource.all) {
      await repo.writeSyncState(
        shopId: shopId,
        resource: resource,
        lastSyncedAtMs: 1700000000000,
        fullSyncDone: true,
      );
    }
    api.onGetShopItemsDelta = ({required shopId, required since}) async =>
        const {'items': [], 'units': [], 'aliases': [], 'barcodes': []};
    api.onGetPartiesDelta = ({required shopId, required since}) async =>
        const {'parties': []};
    api.onGetCategoriesDelta = ({required shopId, required since}) async =>
        const {'expense_categories': [], 'categories': [], 'units': []};
    api.onGetTransactionsDelta =
        ({required shopId, required since, int limit = 200}) async =>
            const {'transactions': []};

    final engine = SyncEngine(
      shopApi: api,
      localRepository: repo,
      pendingPostDao: postDao,
      realtimeDebounce: const Duration(milliseconds: 20),
    );
    await engine.start(shopId);

    engine.notifyEvent(const RealtimeEvent(
      table: 'txn',
      eventType: 'INSERT',
      newRow: {'id': 'txn-new', 'client_op_id': 'op-echo'},
      oldRow: null,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    // Projection cleared because the event was an echo of our own
    // write.
    expect(await repo.projectedStock('si-1'), 10);
    engine.dispose();
  });

  test(
    '#385-fixup-2: self-echo on `txn` still schedules transactions delta',
    () async {
      // Optimistic local rows only carry server_updated_at_ms=0 +
      // empty lines_summary. We need the delta to fetch the real
      // server row (with lines + posted_at) so void becomes
      // available. Other tables (shop_item, party) ARE complete in
      // their WAL row, so skip-on-self-echo stays correct for them.
      final post = PendingPost(
        id: 'pp-2',
        clientOpId: 'op-txn',
        shopId: shopId,
        originalActorUserId: 'u-1',
        rpc: 'post_sale',
        params: const <String, dynamic>{},
        queuedAt: DateTime.utc(2026, 1, 1),
      );
      await postDao.insert(post);
      for (final resource in SyncResource.all) {
        await repo.writeSyncState(
          shopId: shopId,
          resource: resource,
          lastSyncedAtMs: 1700000000000,
          fullSyncDone: true,
        );
      }
      var txnDeltaCalls = 0;
      var itemsDeltaCalls = 0;
      api.onGetTransactionsDelta =
          ({required shopId, required since, int limit = 200}) async {
        txnDeltaCalls += 1;
        return const {'transactions': []};
      };
      api.onGetShopItemsDelta = ({required shopId, required since}) async {
        itemsDeltaCalls += 1;
        return const {
          'items': [],
          'units': [],
          'aliases': [],
          'barcodes': [],
        };
      };
      api.onGetPartiesDelta = ({required shopId, required since}) async =>
          const {'parties': []};
      api.onGetCategoriesDelta = ({required shopId, required since}) async =>
          const {'expense_categories': [], 'categories': [], 'units': []};

      final engine = SyncEngine(
        shopApi: api,
        localRepository: repo,
        pendingPostDao: postDao,
        realtimeDebounce: const Duration(milliseconds: 20),
      );
      await engine.start(shopId);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final baselineTxn = txnDeltaCalls;
      final baselineItems = itemsDeltaCalls;

      engine.notifyEvent(const RealtimeEvent(
        table: 'txn',
        eventType: 'INSERT',
        newRow: {'id': 'txn-echo', 'client_op_id': 'op-txn'},
        oldRow: null,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(txnDeltaCalls - baselineTxn, 1,
          reason: 'self-echo on txn must schedule a transactions delta');
      expect(itemsDeltaCalls - baselineItems, 0,
          reason: 'txn echo must not trigger items delta');
      engine.dispose();
    },
  );

  test(
    '#385-fixup-2: self-echo on non-txn tables still skips delta',
    () async {
      final post = PendingPost(
        id: 'pp-3',
        clientOpId: 'op-item',
        shopId: shopId,
        originalActorUserId: 'u-1',
        rpc: 'set_shop_item_unit_sale_price',
        params: const <String, dynamic>{},
        queuedAt: DateTime.utc(2026, 1, 1),
      );
      await postDao.insert(post);
      for (final resource in SyncResource.all) {
        await repo.writeSyncState(
          shopId: shopId,
          resource: resource,
          lastSyncedAtMs: 1700000000000,
          fullSyncDone: true,
        );
      }
      var itemsDeltaCalls = 0;
      api.onGetShopItemsDelta = ({required shopId, required since}) async {
        itemsDeltaCalls += 1;
        return const {
          'items': [],
          'units': [],
          'aliases': [],
          'barcodes': [],
        };
      };
      api.onGetPartiesDelta = ({required shopId, required since}) async =>
          const {'parties': []};
      api.onGetCategoriesDelta = ({required shopId, required since}) async =>
          const {'expense_categories': [], 'categories': [], 'units': []};
      api.onGetTransactionsDelta =
          ({required shopId, required since, int limit = 200}) async =>
              const {'transactions': []};

      final engine = SyncEngine(
        shopApi: api,
        localRepository: repo,
        pendingPostDao: postDao,
        realtimeDebounce: const Duration(milliseconds: 20),
      );
      await engine.start(shopId);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final baseline = itemsDeltaCalls;

      engine.notifyEvent(const RealtimeEvent(
        table: 'shop_item',
        eventType: 'UPDATE',
        newRow: {'shop_item_id': 'si-1', 'client_op_id': 'op-item'},
        oldRow: null,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(itemsDeltaCalls - baseline, 0,
          reason: 'shop_item self-echo must NOT trigger an items delta');
      engine.dispose();
    },
  );

  test('bulk burst: many events in the debounce window flush once',
      () async {
    for (final resource in SyncResource.all) {
      await repo.writeSyncState(
        shopId: shopId,
        resource: resource,
        lastSyncedAtMs: 1700000000000,
        fullSyncDone: true,
      );
    }
    var partiesDeltaCalls = 0;
    api.onGetPartiesDelta = ({required shopId, required since}) async {
      partiesDeltaCalls += 1;
      return const {'parties': [], 'server_now_ms': 1700000002000};
    };
    api.onGetShopItemsDelta = ({required shopId, required since}) async =>
        const {'items': [], 'units': [], 'aliases': [], 'barcodes': []};
    api.onGetCategoriesDelta = ({required shopId, required since}) async =>
        const {'expense_categories': [], 'categories': [], 'units': []};
    api.onGetTransactionsDelta =
        ({required shopId, required since, int limit = 200}) async =>
            const {'transactions': []};

    final engine = SyncEngine(
      shopApi: api,
      localRepository: repo,
      pendingPostDao: postDao,
      realtimeDebounce: const Duration(milliseconds: 50),
    );
    await engine.start(shopId);
    // Wait for the initial unawaited deltaSync from start() to land
    // so we measure ONLY the burst-induced calls below.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final baseline = partiesDeltaCalls;

    var notifications = 0;
    engine.addListener(() => notifications += 1);

    for (var i = 0; i < 10; i += 1) {
      engine.notifyEvent(RealtimeEvent(
        table: 'party',
        eventType: 'UPDATE',
        newRow: {'id': 'p-$i', 'client_op_id': null},
        oldRow: null,
      ));
    }
    // Wait past the debounce window plus the unawaited delta call
    // it kicks off.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // Exactly one listener notification despite 10 events.
    expect(notifications, 1);
    // Exactly one parties delta RPC kicked off by the flush.
    expect(partiesDeltaCalls - baseline, 1);
    engine.dispose();
  });

  test('fullSync errored state when API throws', () async {
    api.onGetShopFullSync = ({required shopId, force = false}) async {
      throw StateError('boom');
    };
    final engine = SyncEngine(
      shopApi: api,
      localRepository: repo,
      pendingPostDao: postDao,
    );
    await expectLater(
      engine.fullSync(shopId),
      throwsA(isA<StateError>()),
    );
    expect(engine.state, SyncEngineState.errored);
    engine.dispose();
  });

  test('forceDelta returns the count of advanced resources (#375)',
      () async {
    // Seed sync state as if delta sync ran once already.
    for (final res in SyncResource.all) {
      await repo.writeSyncState(
        shopId: shopId,
        resource: res,
        lastSyncedAtMs: 1000,
        fullSyncDone: true,
      );
    }
    api.onGetShopItemsDelta = ({required shopId, required since}) async => {
          'items': [],
          'units': [],
          'aliases': [],
          'barcodes': [],
          'server_now_ms': 2000,
        };
    api.onGetPartiesDelta = ({required shopId, required since}) async => {
          'parties': [],
          'server_now_ms': 2000,
        };
    api.onGetCategoriesDelta = ({required shopId, required since}) async => {
          'expense_categories': [],
          'categories': [],
          'units': [],
          'server_now_ms': 2000,
        };
    api.onGetTransactionsDelta =
        ({required shopId, required since, int limit = 200}) async => {
              'transactions': [],
              'server_now_ms': 2000,
            };
    final engine = SyncEngine(
      shopApi: api,
      localRepository: repo,
      pendingPostDao: postDao,
    );
    final advanced = await engine.forceDelta(shopId);
    expect(advanced, SyncResource.all.length);
    expect(engine.lastSyncedAt, isNotNull);
    engine.dispose();
  });

  test('markRealtime{Connected,Disconnected} flip realtimeDisconnectedAt',
      () async {
    final engine = SyncEngine(
      shopApi: api,
      localRepository: repo,
      pendingPostDao: postDao,
    );
    expect(engine.realtimeDisconnectedAt, isNull);
    engine.markRealtimeDisconnected();
    expect(engine.realtimeDisconnectedAt, isNotNull);
    engine.markRealtimeConnected();
    expect(engine.realtimeDisconnectedAt, isNull);
    engine.dispose();
  });
}
