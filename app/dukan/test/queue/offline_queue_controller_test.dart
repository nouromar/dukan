// Drives the controller's state machine via a stub executor + a
// stubbed backoff/clock so timing is deterministic and we don't
// wait for real delays in the test.

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/device_config_dao.dart';
import 'package:dukan/storage/pending_post_dao.dart';

import '../shared/fakes.dart';
import '../shared/test_database.dart';

PendingPost _post(String id, {DateTime? queuedAt}) => PendingPost(
      id: id,
      clientOpId: 'op-$id',
      shopId: 'shop-1',
      originalActorUserId: 'user-1',
      rpc: 'post_sale',
      params: const <String, dynamic>{},
      queuedAt: queuedAt ?? DateTime.utc(2026, 6, 12, 12, 0, 0),
    );

void main() {
  late PendingPostDao dao;
  late List<String> executed;
  late List<String> shouldFail;
  late OfflineQueueController controller;

  setUp(() {
    dao = PendingPostDao(AppDatabase.instance());
    executed = <String>[];
    shouldFail = <String>[];
    controller = OfflineQueueController(
      dao: dao,
      executor: (post) async {
        if (shouldFail.contains(post.id)) {
          throw StateError('network down for ${post.id}');
        }
        executed.add(post.id);
      },
      // Use zero-duration backoff so retries fire immediately in
      // tests without driving fake timers.
      backoff: (_) => Duration.zero,
      clock: () => DateTime.utc(2026, 6, 12, 12, 0, 0),
    );
  });

  tearDown(() => controller.dispose());

  Future<void> waitForIdle() async {
    // Pump a few microtasks so the queued Timer.zero retries fire.
    for (var i = 0; i < 16; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (!controller.isDraining && controller.pendingCount == 0) return;
    }
  }

  test('start() loads persisted posts and notifies', () async {
    await dao.insert(_post('a'));
    await dao.insert(_post('b'));
    var notified = 0;
    controller.addListener(() => notified++);
    await controller.start();
    expect(controller.pendingCount, greaterThanOrEqualTo(0));
    expect(notified, greaterThan(0));
  });

  test('enqueue persists + drains on success', () async {
    await controller.start();
    await controller.enqueue(_post('a'));
    await waitForIdle();
    expect(executed, ['a']);
    expect(controller.pendingCount, 0);
    expect(await dao.load(), isEmpty);
  });

  test('failure leaves the head queued with bumped attempt count', () async {
    shouldFail.add('a');
    await controller.start();
    await controller.enqueue(_post('a'));
    // Give it a couple of pumps; with zero-duration backoff the
    // controller will keep retrying. Cap with shouldFail unchanged
    // so 'a' should remain in queue with attempts > 0.
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(controller.pendingCount, 1);
    final head = controller.pending.first;
    expect(head.id, 'a');
    expect(head.attempts, greaterThan(0));
    expect(head.lastError, contains('network down'));
    expect(executed, isEmpty);
  });

  test('first failure stops the drain — second item not attempted', () async {
    shouldFail.add('a');
    await controller.start();
    await controller.enqueue(_post('a'));
    await controller.enqueue(_post('b'));
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(executed, isEmpty);
    expect(controller.pendingCount, 2);
  });

  test('removing fail flag lets the queue drain on next retry', () async {
    shouldFail.add('a');
    await controller.start();
    await controller.enqueue(_post('a'));
    await controller.enqueue(_post('b'));
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(controller.pendingCount, 2);
    shouldFail.clear();
    await controller.drainNow();
    await waitForIdle();
    expect(executed, ['a', 'b']);
    expect(controller.pendingCount, 0);
  });

  test('size cap: enqueue past max drops the oldest pending', () async {
    final tiny = OfflineQueueController(
      dao: dao,
      executor: (post) async {
        if (shouldFail.contains(post.id)) {
          throw StateError('network down for ${post.id}');
        }
        executed.add(post.id);
      },
      backoff: (_) => Duration.zero,
      clock: () => DateTime.utc(2026, 6, 12, 12, 0, 0),
      maxPending: 2,
    );
    final dropped = <String>[];
    tiny.addDroppedListener((p) => dropped.add(p.id));
    shouldFail.addAll(['a', 'b', 'c']);
    await tiny.start();
    await tiny.enqueue(_post('a',
        queuedAt: DateTime.utc(2026, 6, 12, 12, 0, 0)));
    await tiny.enqueue(_post('b',
        queuedAt: DateTime.utc(2026, 6, 12, 12, 1, 0)));
    // Third enqueue with cap=2 must drop the oldest ('a').
    await tiny.enqueue(_post('c',
        queuedAt: DateTime.utc(2026, 6, 12, 12, 2, 0)));
    expect(dropped, ['a']);
    expect(tiny.pending.map((p) => p.id), ['b', 'c']);
    tiny.dispose();
  });

  test('failed-permanent transition: drain stops retrying after maxAttempts',
      () async {
    final terminal = OfflineQueueController(
      dao: dao,
      executor: (post) async {
        // Always fail — testing the transition itself.
        throw StateError('persistent failure');
      },
      backoff: (_) => Duration.zero,
      clock: () => DateTime.utc(2026, 6, 12, 12, 0, 0),
      maxAttempts: 3,
    );
    final failed = <String>[];
    terminal.addFailedPermanentListener((p) => failed.add(p.id));
    await terminal.start();
    await terminal.enqueue(_post('a'));
    // Pump enough microtasks for 3 retries to fire.
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (terminal.pendingCount == 0) break;
    }
    expect(failed, ['a']);
    expect(terminal.pendingCount, 0,
        reason: 'failed-permanent rows leave the pending list');
    final stillPending = await dao.load();
    expect(stillPending, isEmpty);
    final inTerminal = await dao.loadFailedPermanent();
    expect(inTerminal.map((p) => p.id), ['a']);
    terminal.dispose();
  });

  test(
      '#365: maxPending sourced from ConfigResolver when no explicit override',
      () async {
    // No explicit `maxPending:` — the controller should read the
    // resolver-backed value. We override the org layer to 2 so the
    // cap fires after 2 enqueues.
    final db = await openTestDatabase();
    final fakeApi = FakeShopApi()
      ..platformConfigEntries = const [
        PlatformConfigEntry(key: 'queue_max_pending', value: 2),
      ];
    final resolver = ConfigResolver(
      shopApi: fakeApi,
      deviceConfigDao: DeviceConfigDao(Future.value(db)),
    );
    await resolver.loadForSession(shopId: 'shop-1');

    final freshDao = PendingPostDao(Future.value(db));
    final c = OfflineQueueController(
      dao: freshDao,
      executor: (_) async => throw StateError('network down'),
      backoff: (_) => const Duration(days: 1),
      clock: () => DateTime.utc(2026, 6, 12, 12, 0, 0),
      configResolver: resolver,
    );
    final dropped = <PendingPost>[];
    c.addDroppedListener(dropped.add);
    await c.start();
    await c.enqueue(_post('a'));
    await c.enqueue(_post('b'));
    expect(c.pendingCount, 2);
    // Third enqueue exceeds the resolver-fed cap of 2 → oldest
    // (`a`) is dropped before insert.
    await c.enqueue(_post('c'));
    expect(c.pendingCount, 2);
    expect(c.pending.map((p) => p.id), ['b', 'c']);
    expect(dropped.map((p) => p.id), ['a']);
    c.dispose();
  });

  test('drainWithTimeout returns even when drain takes longer', () async {
    // Force a slow executor that "hangs" past the timeout.
    final slow = OfflineQueueController(
      dao: dao,
      executor: (post) async {
        await Future<void>.delayed(const Duration(seconds: 30));
        executed.add(post.id);
      },
      backoff: (_) => Duration.zero,
      clock: () => DateTime.utc(2026, 6, 12, 12, 0, 0),
    );
    await slow.start();
    await slow.enqueue(_post('a'));
    final stopwatch = Stopwatch()..start();
    await slow.drainWithTimeout(const Duration(milliseconds: 50));
    stopwatch.stop();
    // Should have returned within ~timeout, not waited for executor.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    slow.dispose();
  });

  // #383: when useLocalDb=false the drain timer is suppressed.
  // Pre-existing pending rows stay frozen until either the user
  // flips back to ON or auth_bootstrap fires `drainNow()` once at
  // startup.
  group('useLocalDb=false', () {
    test(
        'drain timer is suppressed; enqueue persists but does NOT auto-execute',
        () async {
      final dbFuture = AppDatabase.instance();
      final dao2 = PendingPostDao(dbFuture);
      final executed2 = <String>[];
      final controller2 = OfflineQueueController(
        dao: dao2,
        executor: (post) async => executed2.add(post.id),
        configResolver:
            _StubResolver({'use_local_db': false}, dbFuture),
        backoff: (_) => Duration.zero,
      );
      addTearDown(controller2.dispose);
      await controller2.start();
      await controller2.enqueue(_post('frozen-1'));
      // Pump a few microtasks — with the gate ON for OFF mode, no
      // executor invocation should fire.
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(executed2, isEmpty);
      expect(controller2.pendingCount, greaterThanOrEqualTo(1));
    });

    test('drainNow() still works as the explicit one-shot path',
        () async {
      final dbFuture = AppDatabase.instance();
      final dao2 = PendingPostDao(dbFuture);
      final executed2 = <String>[];
      final controller2 = OfflineQueueController(
        dao: dao2,
        executor: (post) async => executed2.add(post.id),
        configResolver:
            _StubResolver({'use_local_db': false}, dbFuture),
        backoff: (_) => Duration.zero,
      );
      addTearDown(controller2.dispose);
      await dao2.insert(_post('one-shot-1'));
      await controller2.start();
      // start() loaded the row but did NOT schedule the timer.
      expect(executed2, isEmpty);
      // Explicit drain works even in OFF mode.
      await controller2.drainNow();
      expect(executed2, contains('one-shot-1'));
    });
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
  Object? rawOverride(String keyName) {
    if (_values.containsKey(keyName)) return _values[keyName];
    return super.rawOverride(keyName);
  }
}
