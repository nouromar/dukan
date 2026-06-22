// Tests for #375 LocalRepository history methods + summary converters.
// historySales / historyReceives / historyPayments / historyExpenses
// + toSaleSummary / toReceiveSummary / toPaymentSummary /
// toExpenseSummary are the seams the offline_mode=full history
// screens consume. We lock the mapping (payload_json → DTO field)
// here so screen tests can mock at a higher level.

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

  group('historySales', () {
    test('filters by date range and party', () async {
      await repo.applyTransactionsPayload({
        'transactions': [
          _txn('t-old', 'sale', occurredMs: 500, total: 5),
          _txn('t-1', 'sale', occurredMs: 1500, total: 10, partyId: 'p-1'),
          _txn('t-2', 'sale', occurredMs: 2000, total: 20, partyId: 'p-2'),
          _txn('t-new', 'sale', occurredMs: 3000, total: 30),
        ],
      });

      final byDate = await repo.historySales(
        shopId: shopId,
        dateFrom: DateTime.fromMillisecondsSinceEpoch(1000),
        dateTo: DateTime.fromMillisecondsSinceEpoch(2500),
      );
      expect(byDate.map((t) => t.txnId), ['t-2', 't-1']);

      final byParty = await repo.historySales(
        shopId: shopId,
        partyId: 'p-1',
      );
      expect(byParty.map((t) => t.txnId), ['t-1']);
    });
  });

  group('historyPayments', () {
    test('filters by direction stored on payload', () async {
      await repo.applyTransactionsPayload({
        'transactions': [
          _txn('t-in', 'payment', occurredMs: 1000, total: 50, extra: {
            'direction': 'I',
            'party_name': 'Ahmed',
          }),
          _txn('t-out', 'payment', occurredMs: 2000, total: 70, extra: {
            'direction': 'O',
            'party_name': 'Supplier',
          }),
        ],
      });

      final inbound = await repo.historyPayments(
        shopId: shopId,
        direction: 'I',
      );
      expect(inbound.map((t) => t.txnId), ['t-in']);

      final outbound = await repo.historyPayments(
        shopId: shopId,
        direction: 'O',
      );
      expect(outbound.map((t) => t.txnId), ['t-out']);
    });
  });

  group('historyExpenses', () {
    test('returns only expense rows ordered most-recent first', () async {
      await repo.applyTransactionsPayload({
        'transactions': [
          _txn('e-old', 'expense', occurredMs: 1000, total: 3),
          _txn('e-new', 'expense', occurredMs: 5000, total: 8),
          _txn('s-1', 'sale', occurredMs: 4000, total: 10),
        ],
      });

      final expenses = await repo.historyExpenses(shopId: shopId);
      expect(expenses.map((t) => t.txnId), ['e-new', 'e-old']);
    });
  });

  group('summary converters', () {
    test('toSaleSummary reads denormalized payload fields', () async {
      await repo.applyTransactionsPayload({
        'transactions': [
          _txn('t-1', 'sale', occurredMs: 1000, total: 12, partyId: 'p', extra: {
            'party_name': 'Ahmed',
            'payment_method_code': 'cash',
            'paid_amount': 10,
            'posted_at': '2026-01-15T08:00:00.000Z',
          }),
        ],
      });
      final t = (await repo.historySales(shopId: shopId)).single;
      final s = repo.toSaleSummary(t);
      expect(s.txnId, 't-1');
      expect(s.partyName, 'Ahmed');
      expect(s.partyId, 'p');
      expect(s.totalAmount, 12);
      expect(s.paidAmount, 10);
      expect(s.paymentMethodCode, 'cash');
      expect(s.isVoided, isFalse);
      expect(s.postedAt, isNotNull);
    });

    test('toPaymentSummary reads direction + isRefund', () async {
      await repo.applyTransactionsPayload({
        'transactions': [
          _txn('p-1', 'payment', occurredMs: 1000, total: 50, partyId: 'p',
              extra: {
                'direction': 'O',
                'party_name': 'Supplier',
                'is_refund': true,
              }),
        ],
      });
      final t = (await repo.historyPayments(shopId: shopId)).single;
      final s = repo.toPaymentSummary(t);
      expect(s.paymentId, 'p-1');
      expect(s.direction, 'O');
      expect(s.partyName, 'Supplier');
      expect(s.isRefund, isTrue);
      expect(s.amount, 50);
    });

    test('toExpenseSummary picks up category + notes', () async {
      await repo.applyTransactionsPayload({
        'transactions': [
          _txn('e-1', 'expense', occurredMs: 1000, total: 5, extra: {
            'category_id': 'cat-1',
            'category_name': 'Cleaning',
            'notes': 'mop',
          }),
        ],
      });
      final t = (await repo.historyExpenses(shopId: shopId)).single;
      final s = repo.toExpenseSummary(t);
      expect(s.txnId, 'e-1');
      expect(s.categoryId, 'cat-1');
      expect(s.categoryName, 'Cleaning');
      expect(s.notes, 'mop');
    });
  });

  group('hasAnyData', () {
    test('flips from false to true after the first applyItemsPayload',
        () async {
      expect(await repo.hasAnyData(shopId), isFalse);
      await repo.applyItemsPayload({
        'items': [
          {
            'shop_item_id': 'si-1',
            'shop_id': shopId,
            'item_id': null,
            'display_name': 'Rice',
            'category_id': null,
            'base_unit_code': 'kg',
            'current_stock': 1,
            'avg_cost': 0,
            'reorder_threshold': null,
            'is_active': true,
            'server_updated_at_ms': 1,
          }
        ],
        'units': [],
        'aliases': [],
        'barcodes': [],
      });
      expect(await repo.hasAnyData(shopId), isTrue);
    });
  });

  group('saleLinesFromLocal', () {
    test('extracts lines from payload_json', () async {
      await repo.applyTransactionsPayload({
        'transactions': [
          _txn('t-1', 'sale', occurredMs: 1000, total: 12, extra: {
            'lines': [
              {
                'line_no': 1,
                'item_id': 'i-1',
                'shop_item_unit_id': 'siu-1',
                'item_name': 'Rice',
                'quantity': 2,
                'unit_label': 'kg',
                'unit_amount': 6,
                'line_total': 12,
                'packaging_label': 'Rice 5kg',
              }
            ],
          }),
        ],
      });
      final lines = await repo.saleLinesFromLocal('t-1');
      expect(lines, hasLength(1));
      expect(lines.single.itemName, 'Rice');
      expect(lines.single.quantity, 2);
    });

    test('returns empty when row not synced', () async {
      final lines = await repo.saleLinesFromLocal('not-yet-synced');
      expect(lines, isEmpty);
    });
  });
}

Map<String, dynamic> _txn(
  String id,
  String typeCode, {
  required int occurredMs,
  required num total,
  String? partyId,
  Map<String, dynamic>? extra,
}) {
  final base = <String, dynamic>{
    'txn_id': id,
    'shop_id': 'shop-1',
    'type_code': typeCode,
    'occurred_at_ms': occurredMs,
    'total': total,
    'party_id': partyId,
    'is_voided': false,
    'server_updated_at_ms': occurredMs,
  };
  if (extra != null) base.addAll(extra);
  return base;
}
