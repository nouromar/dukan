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

    test('credit sale (paid_amount 0) reads as debt, not cash', () async {
      // Regression: a debt sale opened from the local mirror used to
      // render as a fully-paid CASH sale because the sync payload
      // omitted paid_amount and toSaleSummary defaulted it to the full
      // total. With paid_amount carried in the payload (migration 0089)
      // the cash/debt split is honoured.
      await repo.applyTransactionsPayload({
        'transactions': [
          _txn('t-debt', 'sale', occurredMs: 2000, total: 28.8, partyId: 'c',
              extra: {
                'party_name': 'New Customer',
                'payment_method_code': 'cash',
                'paid_amount': 0,
              }),
        ],
      });
      final t = (await repo.historySales(shopId: shopId))
          .firstWhere((e) => e.txnId == 't-debt');
      final s = repo.toSaleSummary(t);
      expect(s.paidAmount, 0);
      expect(s.totalAmount, 28.8);
      expect(s.isDebt, isTrue,
          reason: 'partyId set and paidAmount < total → debt');
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

  group('getPartyDetailLocal', () {
    Map<String, dynamic> party(String id, String type,
            {num receivable = 0, num payable = 0}) =>
        {
          'party_id': id,
          'shop_id': shopId,
          'name': type == 'supplier' ? 'ACME Supplies' : 'New Customer',
          'phone': null,
          'type_code': type,
          'receivable': receivable,
          'payable': payable,
          'is_active': true,
          'server_updated_at_ms': 1,
        };

    test('returns null when the party is not mirrored', () async {
      final d = await repo.getPartyDetailLocal(shopId: shopId, partyId: 'nope');
      expect(d, isNull);
    });

    test('customer: debt sale surfaces with correct paid/debt split offline',
        () async {
      await repo.applyPartiesPayload({
        'parties': [party('c-1', 'customer', receivable: 28.8)],
      });
      await repo.applyTransactionsPayload({
        'transactions': [
          _txn('t-debt', 'sale', occurredMs: 2000, total: 28.8, partyId: 'c-1',
              extra: {'party_name': 'New Customer', 'paid_amount': 0}),
        ],
      });
      final d = await repo.getPartyDetailLocal(shopId: shopId, partyId: 'c-1');
      expect(d, isNotNull);
      expect(d!.header.typeCode, 'customer');
      expect(d.header.receivable, 28.8);
      expect(d.sales.single.txnId, 't-debt');
      expect(d.sales.single.totalAmount, 28.8);
      expect(d.sales.single.paidAmount, 0,
          reason: 'debt sale must not read as fully paid offline');
      expect(d.receives, isEmpty);
      expect(d.payments, isEmpty);
    });

    test('supplier: receives + outbound payment surface offline', () async {
      await repo.applyPartiesPayload({
        'parties': [party('s-1', 'supplier', payable: 100)],
      });
      await repo.applyTransactionsPayload({
        'transactions': [
          _txn('r-1', 'receive', occurredMs: 1000, total: 100, partyId: 's-1',
              extra: {'paid_amount': 0}),
          _txn('pay-1', 'payment', occurredMs: 1500, total: 40, partyId: 's-1',
              extra: {'direction': 'O'}),
        ],
      });
      final d = await repo.getPartyDetailLocal(shopId: shopId, partyId: 's-1');
      expect(d, isNotNull);
      expect(d!.header.typeCode, 'supplier');
      expect(d.header.payable, 100);
      expect(d.sales, isEmpty);
      expect(d.receives.single.txnId, 'r-1');
      expect(d.payments.single.paymentId, 'pay-1');
      expect(d.payments.single.amount, 40);
      expect(d.payments.single.direction, 'O');
    });
  });

  group('listCategoriesLocal', () {
    test('returns active top-level rows, global first then custom',
        () async {
      await repo.applyCategoriesPayload({
        'expense_categories': [],
        'units': [],
        'categories': [
          // global (shop_id null), out-of-order sort to prove ordering
          {
            'id': 'g-2',
            'shop_id': null,
            'code': 'drinks',
            'parent_id': null,
            'name': 'Drinks',
            'sort_order': 2,
            'is_active': true,
          },
          {
            'id': 'g-1',
            'shop_id': null,
            'code': 'food',
            'parent_id': null,
            'name': 'Food',
            'sort_order': 1,
            'is_active': true,
          },
          // a child (parent_id set) — must be excluded from the picker
          {
            'id': 'g-1a',
            'shop_id': null,
            'code': 'rice',
            'parent_id': 'g-1',
            'name': 'Rice',
            'sort_order': 1,
            'is_active': true,
          },
          // inactive — excluded
          {
            'id': 'g-3',
            'shop_id': null,
            'code': 'old',
            'parent_id': null,
            'name': 'Old',
            'sort_order': 3,
            'is_active': false,
          },
          // this shop's custom category — after globals
          {
            'id': 'c-1',
            'shop_id': shopId,
            'code': 'custom',
            'parent_id': null,
            'name': 'Custom',
            'sort_order': 1,
            'is_active': true,
          },
          // another shop's custom — excluded
          {
            'id': 'x-1',
            'shop_id': 'other-shop',
            'code': 'nope',
            'parent_id': null,
            'name': 'Nope',
            'sort_order': 1,
            'is_active': true,
          },
        ],
      });
      final cats = await repo.listCategoriesLocal(shopId: shopId);
      expect(cats.map((c) => c.id), ['g-1', 'g-2', 'c-1'],
          reason: 'globals by sort_order first, then this shop custom; '
              'child + inactive + other-shop excluded');
      expect(cats.first.name, 'Food');
    });
  });

  group('listUnpaidInvoices includeOptimistic', () {
    test('surfaces a just-saved debt sale before it syncs; cash sale excluded',
        () async {
      // Optimistic debt sale (server_updated_at == 0, paid < total).
      await repo.writeOptimisticTransaction(
        clientOpId: 'op-debt',
        shopId: shopId,
        typeCode: 'sale',
        occurredAtMs: 2000,
        total: 26.5,
        partyId: 'c-1',
        payload: {'party_name': 'Ali', 'paid_amount': 0},
      );
      // Optimistic cash sale to the same customer — fully paid, must NOT
      // appear as an open invoice.
      await repo.writeOptimisticTransaction(
        clientOpId: 'op-cash',
        shopId: shopId,
        typeCode: 'sale',
        occurredAtMs: 2100,
        total: 10,
        partyId: 'c-1',
        payload: {'party_name': 'Ali', 'paid_amount': 10},
      );

      // Default path (allocation) never sees the optimistic rows.
      final synced = await repo.listUnpaidInvoices(
        shopId: shopId,
        partyId: 'c-1',
        direction: 'I',
      );
      expect(synced, isEmpty);

      // Party-page path surfaces only the open (debt) invoice.
      final withOptimistic = await repo.listUnpaidInvoices(
        shopId: shopId,
        partyId: 'c-1',
        direction: 'I',
        includeOptimistic: true,
      );
      expect(withOptimistic, hasLength(1));
      expect(withOptimistic.single.transactionId, 'op-debt');
      expect(withOptimistic.single.remaining, 26.5);
    });

    test('combines synced invoices with optimistic ones, oldest first',
        () async {
      await repo.applyUnpaidInvoicesPayload({
        'unpaid_invoices': [
          {
            'shop_id': shopId,
            'party_id': 'c-1',
            'direction': 'I',
            'txn_id': 'synced-1',
            'occurred_at_ms': 1000,
            'original_amount': 5.0,
            'already_paid': 0.0,
            'remaining': 5.0,
            'document_id': null,
            'server_updated_at_ms': 1,
          },
        ],
      });
      await repo.writeOptimisticTransaction(
        clientOpId: 'op-2',
        shopId: shopId,
        typeCode: 'sale',
        occurredAtMs: 3000,
        total: 8,
        partyId: 'c-1',
        payload: {'paid_amount': 0},
      );
      final list = await repo.listUnpaidInvoices(
        shopId: shopId,
        partyId: 'c-1',
        direction: 'I',
        includeOptimistic: true,
      );
      expect(list.map((i) => i.transactionId), ['synced-1', 'op-2']);
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
