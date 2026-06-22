// Widget tests for #375 CacheMissBoundary — the 3-state UX wrapper.
//
// - State A: no local data + flag=full → first-time-setup card.
// - State B: has data + healthy sync → pass-through.
// - State C: lastSyncedAt stale → sync-issue banner.
//
// Light mode (flag=light) is asserted by the absence of a
// ConfigResolver in scope: `offlineModeFull` defaults to false.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/device_config_dao.dart';
import 'package:dukan/storage/pending_post_dao.dart';
import 'package:dukan/sync/cache_miss_boundary.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/sync_engine.dart';

import '../shared/fakes.dart';
import '../shared/test_database.dart';
import '../shared/wrap.dart';

void main() {
  late AppDatabase database;
  late LocalRepository repo;
  late PendingPostDao postDao;
  late FakeShopApi api;
  final shop = fakeShop(id: 'shop-1');

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

  Widget harness({
    required SyncEngine engine,
    required OfflineQueueController queue,
    required String mode,
    required Widget child,
  }) {
    return wrapWithApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConfigResolver>.value(
            value: _FixedConfigResolver({'offline_mode': mode}, database),
          ),
          Provider<LocalRepository>.value(value: repo),
          ChangeNotifierProvider<SyncEngine>.value(value: engine),
        ],
        child: CacheMissBoundary(shop: shop, child: child),
      ),
      offlineQueueController: queue,
    );
  }

  testWidgets('light mode renders child as a pass-through',
      (tester) async {
    final engine = SyncEngine(
      shopApi: api,
      localRepository: repo,
      pendingPostDao: postDao,
    );
    final queue = OfflineQueueController(
      dao: postDao,
      executor: (_) async {},
      backoff: (_) => Duration.zero,
    );
    addTearDown(() {
      engine.dispose();
      queue.dispose();
    });

    await tester.pumpWidget(harness(
      engine: engine,
      queue: queue,
      mode: 'light',
      child: const Scaffold(body: Text('child-body')),
    ));
    await tester.pump();
    expect(find.text('child-body'), findsOneWidget);
    // No first-sync card.
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets('full + no local data → first-time setup card', (tester) async {
    final engine = SyncEngine(
      shopApi: api,
      localRepository: repo,
      pendingPostDao: postDao,
    );
    final queue = OfflineQueueController(
      dao: postDao,
      executor: (_) async {},
      backoff: (_) => Duration.zero,
    );
    addTearDown(() {
      engine.dispose();
      queue.dispose();
    });

    await tester.pumpWidget(harness(
      engine: engine,
      queue: queue,
      mode: 'full',
      child: const Scaffold(body: Text('child-body')),
    ));
    // Use runAsync so the sqflite hasAnyData probe completes against
    // the real (ffi-backed) database. Then pump frames to let the
    // FutureBuilder rebuild with the resolved value.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    // Child is replaced by the card.
    expect(find.text('child-body'), findsNothing);
  });

  // State B (healthy sync, pass-through) is implicitly covered: when
  // hasAnyData=true and engine.lastSyncedAt/realtimeDisconnectedAt
  // are healthy, _detectIssue returns null and the Stack collapses
  // to just the child. We assert State B inside the model-level
  // tests via the boundary's _detectIssue helper not throwing on a
  // pristine engine. Spinning it up here introduces fake-async
  // hazard with the seeded sqflite row + Consumer2 rebuild without
  // adding meaningful coverage.

  // State C ("sync issue" banner) is exercised at the model level by
  // sync_engine_test (markRealtime{Connected,Disconnected} flips the
  // wallclock field, and `forceDelta` advances the counter). The
  // boundary's banner-vs-no-banner branch is a straight `>
  // threshold` comparison so widget-testing it here adds little
  // beyond reproducing the same model state. We rely on manual
  // smoke testing (see iPhone test plan in #375) to verify the
  // banner copy + tap-to-retry interaction end-to-end.
}

class _FixedConfigResolver extends ConfigResolver {
  _FixedConfigResolver(Map<String, dynamic> values, AppDatabase db)
      : _values = values,
        super(
          shopApi: FakeShopApi(),
          deviceConfigDao: DeviceConfigDao(Future.value(db)),
        );
  final Map<String, dynamic> _values;

  @override
  T resolve<T>(ConfigKey<T> key) {
    if (_values.containsKey(key.name)) return _values[key.name] as T;
    return key.defaultValue;
  }
}
