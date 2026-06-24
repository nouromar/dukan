// Tests for #385 writeOptimisticTransaction + dedup-by-client-op-id
// in applyTransactionsPayload.
//
// The mobile app writes an optimistic local_transaction row at
// queue-enqueue time so the cashier sees the sale / receive /
// payment / expense in history INSTANTLY. When the
// server-authoritative copy arrives via delta sync, the optimistic
// row must be replaced (not duplicated). The dedup key is
// client_op_id (NOT txn_id — the server assigns its own UUID).

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/storage/app_database.dart';
import 'package:dukan/sync/local_repository.dart';

import '../shared/test_database.dart';

void main() {
  late AppDatabase database;
  late LocalRepository repo;
  const shopId = 'shop-1';

  setUp(() async {
    database = await openTestDatabase();
    repo = LocalRepository(Future.value(database));
  });

  tearDown(() async {
    await database.close();
  });

  test('writeOptimisticTransaction inserts a row that historySales returns',
      () async {
    await repo.writeOptimisticTransaction(
      clientOpId: 'sale-cop-123',
      shopId: shopId,
      typeCode: 'sale',
      occurredAtMs: 2_000_000,
      total: 11.30,
      partyId: null,
      payload: <String, dynamic>{
        'party_name': null,
        'payment_method_code': 'cash',
        'paid_amount': 11.30,
        'lines_summary': <Map<String, dynamic>>[
          <String, dynamic>{
            'line_no': 1,
            'item_name': 'Bariis',
            'quantity': 1.0,
            'line_total': 11.30,
          },
        ],
      },
    );

    final rows = await repo.historySales(shopId: shopId);
    expect(rows, hasLength(1));
    final t = rows.single;
    expect(t.txnId, 'sale-cop-123');
    expect(t.clientOpId, 'sale-cop-123');
    expect(t.total, 11.30);
    expect(t.isOptimistic, isTrue);
    // payload_json round-trips with the optimistic marker added.
    expect(t.payload['client_op_id'], 'sale-cop-123');
    expect(t.payload['server_updated_at_ms'], 0);
    expect(t.payload['lines_summary'], isA<List<dynamic>>());

    final lines = await repo.saleLinesFromLocal('sale-cop-123');
    expect(lines, hasLength(1));
    expect(lines.single.itemName, 'Bariis');
    expect(lines.single.lineTotal, 11.30);
  });

  test(
      'applyTransactionsPayload replaces the optimistic row by client_op_id, '
      'preserving uniqueness in history', () async {
    await repo.writeOptimisticTransaction(
      clientOpId: 'sale-cop-abc',
      shopId: shopId,
      typeCode: 'sale',
      occurredAtMs: 1_000_000,
      total: 50,
      partyId: 'p-1',
      payload: <String, dynamic>{
        'party_name': 'Hibo',
        'payment_method_code': 'cash',
        'lines_summary': <Map<String, dynamic>>[],
      },
    );

    // Server eventually returns the authoritative row via delta
    // sync. txn_id is a different (server-assigned) UUID; the
    // client_op_id matches.
    await repo.applyTransactionsPayload({
      'transactions': [
        <String, dynamic>{
          'txn_id': 'server-uuid-xyz',
          'shop_id': shopId,
          'type_code': 'sale',
          'occurred_at_ms': 1_000_000,
          'total': 50,
          'party_id': 'p-1',
          'is_voided': false,
          'server_updated_at_ms': 1_500_000,
          'client_op_id': 'sale-cop-abc',
          'party_name': 'Hibo',
          'payment_method_code': 'cash',
          'lines_summary': <Map<String, dynamic>>[
            <String, dynamic>{
              'line_no': 1,
              'item_id': 'item-1',
              'shop_item_unit_id': 'siu-1',
              'item_name': 'Bariis',
              'quantity': 1.0,
              'unit_amount': 50.0,
              'line_total': 50.0,
            },
          ],
        },
      ],
    });

    final rows = await repo.historySales(shopId: shopId);
    expect(rows, hasLength(1), reason: 'optimistic row must be replaced');
    final t = rows.single;
    expect(t.txnId, 'server-uuid-xyz',
        reason: 'server-assigned UUID wins over optimistic placeholder');
    expect(t.clientOpId, 'sale-cop-abc');
    expect(t.isOptimistic, isFalse,
        reason: 'server_updated_at_ms > 0 marks the row as synced');

    // Lines now reflect the server-authoritative payload.
    final lines = await repo.saleLinesFromLocal('server-uuid-xyz');
    expect(lines, hasLength(1));
    expect(lines.single.itemId, 'item-1');
    expect(lines.single.shopItemUnitId, 'siu-1');
    expect(lines.single.unitAmount, 50.0);
  });

  test('applyTransactionsPayload without matching optimistic row inserts cleanly',
      () async {
    // Foreign device's write arriving — no local optimistic row to
    // dedupe against. Insert proceeds normally.
    await repo.applyTransactionsPayload({
      'transactions': [
        <String, dynamic>{
          'txn_id': 'server-uuid-foreign',
          'shop_id': shopId,
          'type_code': 'sale',
          'occurred_at_ms': 9_000_000,
          'total': 7,
          'party_id': null,
          'is_voided': false,
          'server_updated_at_ms': 9_500_000,
          'client_op_id': 'foreign-cop-zzz',
          'lines_summary': <Map<String, dynamic>>[],
        },
      ],
    });

    final rows = await repo.historySales(shopId: shopId);
    expect(rows, hasLength(1));
    expect(rows.single.txnId, 'server-uuid-foreign');
    expect(rows.single.clientOpId, 'foreign-cop-zzz');
  });

  test(
      'saleLinesFromLocal reads lines_summary (server key) AND legacy lines '
      '(for any old-shape rows)', () async {
    await repo.applyTransactionsPayload({
      'transactions': [
        <String, dynamic>{
          'txn_id': 't-new',
          'shop_id': shopId,
          'type_code': 'sale',
          'occurred_at_ms': 1,
          'total': 1,
          'is_voided': false,
          'server_updated_at_ms': 1,
          'lines_summary': <Map<String, dynamic>>[
            <String, dynamic>{
              'line_no': 1,
              'item_name': 'X',
              'quantity': 1.0,
              'line_total': 1.0,
            },
          ],
        },
      ],
    });
    final lines = await repo.saleLinesFromLocal('t-new');
    expect(lines, hasLength(1));
    expect(lines.single.itemName, 'X');
  });
}
