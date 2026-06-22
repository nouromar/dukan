// Tests for #374 stock projection wiring:
// - applyProjectionLines computes base-unit deltas from
//   shop_item_unit + quantity + direction (sale = -1, receive = +1)
// - projectedStock combines current_stock with the pending deltas
// - clearProjectionsForPost removes one post's rows
// - OfflineQueueController calls onProjectionCleanup on drain
//   success AND failed_permanent

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/pending_post_dao.dart';
import 'package:dukan/sync/local_repository.dart';

import '../shared/test_database.dart';

void main() {
  late AppDatabase database;
  late LocalRepository repo;
  const shopId = 'shop-1';

  setUp(() async {
    database = await openTestDatabase();
    repo = LocalRepository(Future.value(database));
    // Seed: one item with 100 in stock, packaging that converts 5:1.
    await repo.applyItemsPayload({
      'items': [
        {
          'shop_item_id': 'si-1',
          'shop_id': shopId,
          'item_id': null,
          'display_name': 'Rice',
          'category_id': null,
          'base_unit_code': 'kg',
          'current_stock': 100,
          'avg_cost': 0,
          'reorder_threshold': null,
          'is_active': true,
          'server_updated_at_ms': 1700000000000,
        }
      ],
      'units': [
        {
          'shop_item_unit_id': 'siu-bag',
          'shop_item_id': 'si-1',
          'unit_code': 'bag',
          'packaging_label': 'Rice — 5kg',
          'conversion_to_base': 5,
          'sale_price': 80000,
          'last_cost': 50000,
          'is_default_sale': true,
          'is_default_receive': false,
          'is_active': true,
          'server_updated_at_ms': 1700000000000,
        }
      ],
      'aliases': [],
      'barcodes': [],
    });
  });

  tearDown(() async {
    await database.close();
  });

  test('applyProjectionLines: sale decreases projected stock by qty*conversion',
      () async {
    // Sale of 2 bags @ 5kg = -10 base units.
    await repo.applyProjectionLines(
      pendingPostId: 'post-sale-1',
      lines: const [
        ProjectionLine(
          shopItemUnitId: 'siu-bag',
          quantity: 2,
          direction: -1,
        ),
      ],
    );

    final projected = await repo.projectedStock('si-1');
    expect(projected, 90); // 100 - 10
  });

  test('applyProjectionLines: receive increases projected stock', () async {
    // Receive of 3 bags @ 5kg = +15 base units.
    await repo.applyProjectionLines(
      pendingPostId: 'post-recv-1',
      lines: const [
        ProjectionLine(
          shopItemUnitId: 'siu-bag',
          quantity: 3,
          direction: 1,
        ),
      ],
    );

    final projected = await repo.projectedStock('si-1');
    expect(projected, 115); // 100 + 15
  });

  test('multiple posts accumulate; clearProjectionsForPost removes one',
      () async {
    await repo.applyProjectionLines(
      pendingPostId: 'post-1',
      lines: const [
        ProjectionLine(shopItemUnitId: 'siu-bag', quantity: 2, direction: -1),
      ],
    );
    await repo.applyProjectionLines(
      pendingPostId: 'post-2',
      lines: const [
        ProjectionLine(shopItemUnitId: 'siu-bag', quantity: 1, direction: -1),
      ],
    );
    expect(await repo.projectedStock('si-1'), 85); // 100 - 10 - 5

    await repo.clearProjectionsForPost('post-1');
    expect(await repo.projectedStock('si-1'), 95); // 100 - 5

    await repo.clearProjectionsForPost('post-2');
    expect(await repo.projectedStock('si-1'), 100); // back to base
  });

  test('applyProjectionLines skips lines for unknown units', () async {
    await repo.applyProjectionLines(
      pendingPostId: 'post-bad',
      lines: const [
        ProjectionLine(
          shopItemUnitId: 'siu-unknown',
          quantity: 1,
          direction: -1,
        ),
      ],
    );

    // No effect because unit not in local mirror.
    expect(await repo.projectedStock('si-1'), 100);
  });

  test('OfflineQueueController clears projection on drain success', () async {
    final dao = PendingPostDao(Future.value(database));
    var executorCalls = 0;
    final controller = OfflineQueueController(
      dao: dao,
      executor: (post) async {
        executorCalls++;
      },
      onProjectionCleanup: repo.clearProjectionsForPost,
      maxAttempts: 5,
      backoff: (_) => const Duration(seconds: 5),
    );
    await controller.start();

    final post = PendingPost(
      id: 'post-drain-ok',
      clientOpId: 'cop-1',
      shopId: shopId,
      originalActorUserId: '',
      rpc: 'post_sale',
      params: const {},
      queuedAt: DateTime.now(),
    );
    // Pre-stage projection.
    await repo.applyProjectionLines(
      pendingPostId: post.id,
      lines: const [
        ProjectionLine(shopItemUnitId: 'siu-bag', quantity: 2, direction: -1),
      ],
    );
    expect(await repo.projectedStock('si-1'), 90);

    await controller.enqueue(post);
    // Wait for drain.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(executorCalls, 1);
    expect(await repo.projectedStock('si-1'), 100); // cleared
    controller.dispose();
  });

  test('OfflineQueueController clears projection on failed_permanent',
      () async {
    final dao = PendingPostDao(Future.value(database));
    final controller = OfflineQueueController(
      dao: dao,
      executor: (post) async {
        throw StateError('permanent error');
      },
      onProjectionCleanup: repo.clearProjectionsForPost,
      maxAttempts: 1, // single attempt → straight to failed_permanent
      backoff: (_) => const Duration(milliseconds: 1),
    );
    await controller.start();

    final post = PendingPost(
      id: 'post-drain-bad',
      clientOpId: 'cop-2',
      shopId: shopId,
      originalActorUserId: '',
      rpc: 'post_sale',
      params: const {},
      queuedAt: DateTime.now(),
    );
    await repo.applyProjectionLines(
      pendingPostId: post.id,
      lines: const [
        ProjectionLine(shopItemUnitId: 'siu-bag', quantity: 2, direction: -1),
      ],
    );
    expect(await repo.projectedStock('si-1'), 90);

    await controller.enqueue(post);
    // Wait for drain failure → failed_permanent transition.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(await repo.projectedStock('si-1'), 100); // cleared on permanent fail
    controller.dispose();
  });
}
