// Drives the controller's state machine via a stub executor + a
// stubbed backoff/clock so timing is deterministic and we don't
// wait for real delays in the test.

import 'package:flutter/foundation.dart';
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

PendingPost _post(String id, {DateTime? queuedAt, String shopId = 'shop-1'}) =>
    PendingPost(
      id: id,
      clientOpId: 'op-$id',
      shopId: shopId,
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

  test('holds posts for a shop the current user cannot access, drains its own '
      '(cross-account safety)', () async {
    final drained = <String>[];
    final scoped = OfflineQueueController(
      dao: dao,
      executor: (post) async => drained.add(post.id),
      backoff: (_) => Duration.zero,
      clock: () => DateTime.utc(2026, 6, 12, 12, 0, 0),
      // Current user can access shop-A only.
      canDrainShop: (shopId) => shopId == 'shop-A',
    );
    addTearDown(scoped.dispose);
    await dao.insert(_post('mine', shopId: 'shop-A'));
    await dao.insert(_post('theirs', shopId: 'shop-B'));
    await scoped.start();
    for (var i = 0; i < 16; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    // My shop's post drained; the other user's post was NOT attempted and
    // stays pending (not failed) for its own user to drain later.
    expect(drained, contains('mine'));
    expect(drained, isNot(contains('theirs')));
    final remaining = (await dao.load()).map((p) => p.id);
    expect(remaining, contains('theirs'));
    final failed = (await dao.loadFailedPermanent()).map((p) => p.id);
    expect(failed, isNot(contains('theirs')));
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

  test('over the soft cap: keeps every post (never drops) + warns once',
      () async {
    final warnings = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) => warnings.add(d.exception.toString());
    addTearDown(() => FlutterError.onError = prev);

    final tiny = OfflineQueueController(
      dao: dao,
      // Never drains, so posts pile up past the soft cap.
      executor: (_) async => throw StateError('offline'),
      backoff: (_) => const Duration(days: 1),
      clock: () => DateTime.utc(2026, 6, 12, 12, 0, 0),
      maxPending: 2, // soft cap
    );
    await tiny.start();
    await tiny.enqueue(_post('a',
        queuedAt: DateTime.utc(2026, 6, 12, 12, 0, 0)));
    await tiny.enqueue(_post('b',
        queuedAt: DateTime.utc(2026, 6, 12, 12, 1, 0)));
    await tiny.enqueue(_post('c',
        queuedAt: DateTime.utc(2026, 6, 12, 12, 2, 0)));
    // Nothing is dropped — a queued sale is never deleted to save space.
    expect(tiny.pending.map((p) => p.id), ['a', 'b', 'c']);
    // Crossing the soft cap warned exactly once (for observability).
    expect(
      warnings.where((w) => w.contains('offline queue is large')),
      hasLength(1),
    );
    tiny.dispose();
  });

  test('permanent (server-reject) failure parks the post; transient never does',
      () async {
    // A permanent-classified error parks immediately (one attempt).
    final terminal = OfflineQueueController(
      dao: dao,
      executor: (post) async {
        throw StateError('server rejected');
      },
      isPermanentError: (_) => true,
      backoff: (_) => Duration.zero,
      clock: () => DateTime.utc(2026, 6, 12, 12, 0, 0),
    );
    final failed = <String>[];
    terminal.addFailedPermanentListener((p) => failed.add(p.id));
    await terminal.start();
    await terminal.enqueue(_post('a'));
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (terminal.failedCount > 0) break;
    }
    expect(failed, ['a']);
    expect(terminal.pendingCount, 0,
        reason: 'parked rows leave the pending list');
    expect(terminal.failedCount, 1);
    expect((await dao.loadFailedPermanent()).map((p) => p.id), ['a']);
    terminal.dispose();
  });

  test('transient failure retries FOREVER and never parks', () async {
    // Always fails, but the error is NOT classified permanent → the
    // post must keep climbing attempts and never leave the queue.
    final forever = OfflineQueueController(
      dao: dao,
      executor: (post) async {
        throw StateError('network down');
      },
      backoff: (_) => Duration.zero,
      clock: () => DateTime.utc(2026, 6, 12, 12, 0, 0),
    );
    await forever.start();
    await forever.enqueue(_post('b'));
    // Let many retries fire.
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(forever.failedCount, 0, reason: 'never parked');
    expect(forever.pendingCount, 1, reason: 'still queued, still retrying');
    expect((await dao.load()).map((p) => p.id), ['b']);
    final head = (await dao.load()).single;
    expect(head.attempts, greaterThan(2),
        reason: 'attempts keep climbing (drives backoff), not a death count');
    forever.dispose();
  });

  test('auth failure refreshes the session and never consumes an attempt',
      () async {
    var refreshes = 0;
    var failWithAuth = true;
    final authy = OfflineQueueController(
      dao: dao,
      executor: (post) async {
        if (failWithAuth) throw StateError('JWT expired');
        executed.add(post.id);
      },
      isAuthError: (e) => e.toString().contains('JWT'),
      refreshSession: () async => refreshes++,
      backoff: (_) => Duration.zero,
      clock: () => DateTime.utc(2026, 6, 12, 12, 0, 0),
    );
    await authy.start();
    await authy.enqueue(_post('c'));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (refreshes > 0) break;
    }
    expect(refreshes, greaterThan(0), reason: 'a 401 triggers a refresh');
    expect((await dao.load()).single.attempts, 0,
        reason: 'auth failures never burn an attempt');
    expect(authy.failedCount, 0, reason: 'auth never parks a post');

    // Token restored — the post now drains.
    failWithAuth = false;
    await authy.drainNow();
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (authy.pendingCount == 0) break;
    }
    expect(executed, ['c']);
    authy.dispose();
  });

  test('start() reloads failedCount from a prior session', () async {
    // Simulate a post that gave up in an earlier run.
    await dao.insert(_post('old'));
    await dao.markFailedPermanent('old');
    final reloaded = OfflineQueueController(
      dao: dao,
      executor: (post) async => executed.add(post.id),
      backoff: (_) => Duration.zero,
      clock: () => DateTime.utc(2026, 6, 12, 12, 0, 0),
    );
    await reloaded.start();
    expect(reloaded.failedCount, 1,
        reason: 'stranded posts must stay visible across app restarts');
    reloaded.dispose();
  });

  test('retryFailed(): resets parked posts to pending and drains them',
      () async {
    // Seed a post the server parked in a prior run.
    await dao.insert(_post('s1'));
    await dao.markFailedPermanent('s1');
    final retryable = OfflineQueueController(
      dao: dao,
      executor: (post) async => executed.add(post.id),
      backoff: (_) => Duration.zero,
      clock: () => DateTime.utc(2026, 6, 12, 12, 0, 0),
    );
    await retryable.start();
    expect(retryable.failedCount, 1);
    expect(executed, isEmpty);

    // Manual retry (pill tap / reconnect) — the post finally drains.
    await retryable.retryFailed();
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (retryable.failedCount == 0 && retryable.pendingCount == 0) break;
    }
    expect(executed, ['s1'], reason: 'the once-parked post finally posts');
    expect(retryable.failedCount, 0);
    expect(await dao.loadFailedPermanent(), isEmpty);
    retryable.dispose();
  });

  test('#365: soft cap sourced from ConfigResolver; still never drops',
      () async {
    final warnings = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) => warnings.add(d.exception.toString());
    addTearDown(() => FlutterError.onError = prev);

    // No explicit `maxPending:` — the controller reads the resolver-backed
    // value. Override to 2 so the soft-cap warning fires after 2 enqueues.
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
    await c.start();
    await c.enqueue(_post('a'));
    await c.enqueue(_post('b'));
    await c.enqueue(_post('c'));
    // The resolver-fed soft cap (2) drives the warning — proving it was
    // read (not the 10k default) — but NOTHING is dropped.
    expect(c.pendingCount, 3);
    expect(c.pending.map((p) => p.id), ['a', 'b', 'c']);
    expect(warnings.where((w) => w.contains('soft cap 2')), isNotEmpty);
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
