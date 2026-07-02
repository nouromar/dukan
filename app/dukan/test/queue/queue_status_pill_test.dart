// The status pill must never fall silent while unposted data is
// stranded. Two states: soft "Syncing N" for pending posts, and a loud
// "N not sent — retry" alarm when any post has given up
// (failed_permanent). The alarm is the data-loss safety net — it turns
// a silently-stranded sale into a visible, one-tap-recoverable one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/queue/queue_status_pill.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/pending_post_dao.dart';

import '../shared/wrap.dart';

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
  testWidgets('hidden when nothing is pending or failed', (tester) async {
    final dao = PendingPostDao(AppDatabase.instance());
    final controller = OfflineQueueController(
      dao: dao,
      executor: (_) async {},
      backoff: (_) => Duration.zero,
      clock: () => DateTime.utc(2026, 6, 12),
    );
    await controller.start();

    await tester.pumpWidget(wrapWithApp(
      const Scaffold(body: QueueStatusPill()),
      offlineQueueController: controller,
    ));
    await tester.pump();

    expect(find.byType(Container), findsNothing);
    controller.dispose();
  });

  testWidgets('surfaces failed posts loudly and wires the tap to retry',
      (tester) async {
    final dao = PendingPostDao(AppDatabase.instance());
    final controller = OfflineQueueController(
      dao: dao,
      executor: (_) async {},
      backoff: (_) => Duration.zero,
      clock: () => DateTime.utc(2026, 6, 12),
    );

    // Seed a post that already gave up in a prior session, then start —
    // failedCount loads from the mirror. Pending is empty so no drain
    // timer is armed (keeps the widget test deterministic). The
    // drain→failed transition and retryFailed→drain behaviour are
    // covered by the controller test.
    await dao.insert(_post('s1'));
    await dao.markFailedPermanent('s1');
    await controller.start();
    expect(controller.failedCount, 1);

    await tester.pumpWidget(wrapWithApp(
      const Scaffold(body: QueueStatusPill()),
      offlineQueueController: controller,
    ));
    await tester.pump();

    // The alarm shows the "not sent" copy + its distinct icon, and its
    // tap is wired to retryFailed (not the softer drainNow).
    expect(find.textContaining('not sent'), findsOneWidget);
    expect(find.byIcon(Icons.sync_problem), findsOneWidget);
    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.onTap, equals(controller.retryFailed),
        reason: 'the alarm tap must retry stranded posts');

    controller.dispose();
  });
}
