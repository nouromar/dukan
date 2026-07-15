// Tests for getTodaySummaryLocal — the local-first Home Today card source.
// Must match get_today_summary's rules exactly (the online reconcile target):
// void-excluded, money-in excludes settlement legs, money-out counts outbound,
// balances from projections, low-stock uses the SERVER condition, and only
// today's (device-local) rows count.

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/storage/app_database.dart';
import 'package:dukan/sync/local_repository.dart';

import '../shared/test_database.dart';

void main() {
  late AppDatabase database;
  late LocalRepository repo;
  const shopId = 'shop-1';

  // Fixed "now" so the device-local day boundary is deterministic.
  final now = DateTime(2026, 1, 15, 10);
  final todayMs = DateTime(2026, 1, 15, 9).millisecondsSinceEpoch;
  final yesterdayMs = DateTime(2026, 1, 14, 9).millisecondsSinceEpoch;

  setUp(() async {
    database = await openTestDatabase();
    repo = LocalRepository(Future.value(database));
  });

  tearDown(() async {
    await database.close();
  });

  Map<String, dynamic> item(String id, num stock, num? threshold) => {
        'shop_item_id': id,
        'shop_id': shopId,
        'item_id': null,
        'display_name': id,
        'category_id': null,
        'base_unit_code': 'kg',
        'current_stock': stock,
        'avg_cost': 0,
        'reorder_threshold': threshold,
        'is_active': true,
        'server_updated_at_ms': 1,
      };

  Map<String, dynamic> party(String id, {num receivable = 0, num payable = 0}) =>
      {
        'party_id': id,
        'shop_id': shopId,
        'name': id,
        'phone': null,
        'type_code': 'customer',
        'receivable': receivable,
        'payable': payable,
        'is_active': true,
        'server_updated_at_ms': 1,
      };

  Map<String, dynamic> txn(
    String id,
    String type,
    num total, {
    int? occurredMs,
    bool voided = false,
    String? direction,
    String? clientOpId,
  }) =>
      {
        'txn_id': id,
        'shop_id': shopId,
        'client_op_id': clientOpId,
        'type_code': type,
        'occurred_at_ms': occurredMs ?? todayMs,
        'total': total,
        'party_id': null,
        'is_voided': voided,
        'server_updated_at_ms': occurredMs ?? todayMs,
        if (direction != null) 'direction': direction,
      };

  test('aggregates today only, void-excluded, settlement-leg-excluded', () async {
    await repo.applyPartiesPayload({
      'parties': [
        party('cust', receivable: 20),
        party('supp', payable: 50),
        party('zero', receivable: 0), // excluded (not > 0)
      ],
    });
    await repo.applyItemsPayload({
      'items': [
        item('low-null', 0.5, null), // 0.5 < 1 → low
        item('at-thresh', 5, 5), //     5 <= 5 → low
        item('ok', 100, 10), //         neither → not low
        // 0.5 with threshold 0.2: server counts it (0.5<1); lowStockLocal would
        // NOT. Proves getTodaySummaryLocal uses the SERVER condition.
        item('below-1-above-thresh', 0.5, 0.2),
      ],
      'units': [],
      'aliases': [],
      'barcodes': [],
    });
    await repo.applyTransactionsPayload({
      'transactions': [
        txn('sale-1', 'sale', 10),
        txn('sale-void', 'sale', 5, voided: true), // excluded
        txn('sale-yday', 'sale', 99, occurredMs: yesterdayMs), // excluded
        txn('recv-1', 'receive', 80),
        txn('exp-1', 'expense', 12),
        txn('pay-in', 'payment', 3, direction: 'I', clientOpId: 'op-real'),
        // settlement leg (cash-sale till cash) — excluded from money-in
        txn('pay-leg', 'payment', 7, direction: 'I', clientOpId: 'base:payment'),
        txn('pay-out', 'payment', 4, direction: 'O', clientOpId: 'op-out'),
      ],
    });

    final s = await repo.getTodaySummaryLocal(shopId, now: now);

    expect(s.salesToday, 10);
    expect(s.salesCount, 1);
    expect(s.receivedToday, 80);
    expect(s.receivedCount, 1);
    expect(s.expensesToday, 12);
    expect(s.expensesCount, 1);
    expect(s.moneyInToday, 3, reason: 'settlement leg (7) excluded');
    expect(s.moneyInCount, 1);
    expect(s.moneyOutToday, 4);
    expect(s.moneyOutCount, 1);
    expect(s.receivablesTotal, 20);
    expect(s.payablesTotal, 50);
    expect(s.lowStockCount, 3, reason: 'low-null, at-thresh, below-1-above-thresh');
  });

  test('empty shop → all zeros, no throw', () async {
    final s = await repo.getTodaySummaryLocal(shopId, now: now);
    expect(s.salesToday, 0);
    expect(s.salesCount, 0);
    expect(s.receivablesTotal, 0);
    expect(s.lowStockCount, 0);
  });
}
