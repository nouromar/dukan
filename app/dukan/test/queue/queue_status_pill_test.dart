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

  testWidgets('shows a quiet indicator for parked posts, wired to retry',
      (tester) async {
    final dao = PendingPostDao(AppDatabase.instance());
    final controller = OfflineQueueController(
      dao: dao,
      executor: (_) async {},
      backoff: (_) => Duration.zero,
      clock: () => DateTime.utc(2026, 6, 12),
    );

    // Seed a parked post from a prior session (failedCount loads from
    // the mirror; pending empty so no drain timer — deterministic).
    await dao.insert(_post('s1'));
    await dao.markFailedPermanent('s1');
    await controller.start();
    expect(controller.failedCount, 1);

    await tester.pumpWidget(wrapWithApp(
      const Scaffold(body: QueueStatusPill()),
      offlineQueueController: controller,
    ));
    await tester.pump();

    // A quiet grey "Syncing 1" chip (NOT a red alarm), wired to retry.
    expect(find.textContaining('Syncing'), findsOneWidget);
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(InkWell),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration as BoxDecoration;
    final scheme = Theme.of(tester.element(find.byType(QueueStatusPill)))
        .colorScheme;
    expect(decoration.color, scheme.surfaceContainerHighest,
        reason: 'neutral grey — never a red alarm');
    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.onTap, equals(controller.retryFailed));

    controller.dispose();
  });

  testWidgets('shows the combined pending + parked count', (tester) async {
    final dao = PendingPostDao(AppDatabase.instance());
    // One parked + one pending seeded directly (no drain-driving under
    // the widget-test fake clock). Executor throws a transient so if the
    // start() drain does fire on pump, the pending post stays queued
    // (transient → never parks); the big backoff timer is cancelled on
    // dispose.
    final controller = OfflineQueueController(
      dao: dao,
      executor: (_) async => throw StateError('offline'),
      backoff: (_) => const Duration(hours: 1),
      clock: () => DateTime.utc(2026, 6, 12),
    );
    await dao.insert(_post('parked'));
    await dao.markFailedPermanent('parked');
    await dao.insert(_post('pending'));
    await controller.start();
    expect(controller.pendingCount, 1);
    expect(controller.failedCount, 1);

    await tester.pumpWidget(wrapWithApp(
      const Scaffold(body: QueueStatusPill()),
      offlineQueueController: controller,
    ));
    await tester.pump();

    expect(find.textContaining('2'), findsOneWidget,
        reason: 'pending + parked are summed into one count');
    controller.dispose();
  });
}
