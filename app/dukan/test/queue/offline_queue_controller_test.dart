// Drives the controller's state machine via a stub executor + a
// stubbed backoff/clock so timing is deterministic and we don't
// wait for real delays in the test.

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/pending_post_dao.dart';

PendingPost _post(String id) => PendingPost(
      id: id,
      clientOpId: 'op-$id',
      shopId: 'shop-1',
      originalActorUserId: 'user-1',
      rpc: 'post_sale',
      params: const <String, dynamic>{},
      queuedAt: DateTime.utc(2026, 6, 12, 12, 0, 0),
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
}
