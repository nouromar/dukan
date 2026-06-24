// #391: tests for the unpaid-invoices mirror — apply payload
// (upsert + tombstone-on-zero-remaining) and read via
// listUnpaidInvoices.

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/storage/app_database.dart';
import 'package:dukan/sync/local_repository.dart';

import '../shared/test_database.dart';

Map<String, dynamic> _row({
  String shopId = 'shop-1',
  String partyId = 'party-A',
  String direction = 'I',
  required String txnId,
  int occurredAtMs = 1700000000000,
  num originalAmount = 100.0,
  num alreadyPaid = 0.0,
  num? remaining,
  String? documentId,
  int serverUpdatedAtMs = 1700000000000,
}) => {
      'shop_id': shopId,
      'party_id': partyId,
      'direction': direction,
      'txn_id': txnId,
      'occurred_at_ms': occurredAtMs,
      'original_amount': originalAmount,
      'already_paid': alreadyPaid,
      'remaining': remaining ?? (originalAmount - alreadyPaid),
      'document_id': documentId,
      'server_updated_at_ms': serverUpdatedAtMs,
    };

void main() {
  late AppDatabase database;
  late LocalRepository repo;

  setUp(() async {
    database = await openTestDatabase();
    repo = LocalRepository(Future.value(database));
  });

  tearDown(() async {
    await database.close();
  });

  test('applyUnpaidInvoicesPayload inserts new rows', () async {
    await repo.applyUnpaidInvoicesPayload({
      'unpaid_invoices': [
        _row(txnId: 'sale-1', originalAmount: 50),
        _row(txnId: 'sale-2', originalAmount: 75, alreadyPaid: 25),
      ],
    });
    final rows = await repo.listUnpaidInvoices(
      shopId: 'shop-1',
      partyId: 'party-A',
      direction: 'I',
    );
    expect(rows, hasLength(2));
    expect(rows[0].transactionId, 'sale-1');
    expect(rows[0].remaining, 50.0);
    expect(rows[1].transactionId, 'sale-2');
    expect(rows[1].remaining, 50.0);
  });

  test('applyUnpaidInvoicesPayload replaces existing rows on conflict',
      () async {
    await repo.applyUnpaidInvoicesPayload({
      'unpaid_invoices': [
        _row(txnId: 'sale-1', originalAmount: 100, alreadyPaid: 0),
      ],
    });
    // Partial payment lands → already_paid bumps, remaining drops.
    await repo.applyUnpaidInvoicesPayload({
      'unpaid_invoices': [
        _row(txnId: 'sale-1', originalAmount: 100, alreadyPaid: 30),
      ],
    });
    final rows = await repo.listUnpaidInvoices(
      shopId: 'shop-1',
      partyId: 'party-A',
      direction: 'I',
    );
    expect(rows, hasLength(1));
    expect(rows.single.alreadyPaid, 30.0);
    expect(rows.single.remaining, 70.0);
  });

  test('applyUnpaidInvoicesPayload deletes when remaining <= 0 (tombstone)',
      () async {
    await repo.applyUnpaidInvoicesPayload({
      'unpaid_invoices': [
        _row(txnId: 'sale-1', originalAmount: 50),
        _row(txnId: 'sale-2', originalAmount: 100),
      ],
    });
    // sale-1 is fully paid off → remaining 0 in next delta.
    await repo.applyUnpaidInvoicesPayload({
      'unpaid_invoices': [
        _row(txnId: 'sale-1', originalAmount: 50, alreadyPaid: 50,
            remaining: 0),
      ],
    });
    final rows = await repo.listUnpaidInvoices(
      shopId: 'shop-1',
      partyId: 'party-A',
      direction: 'I',
    );
    expect(rows, hasLength(1));
    expect(rows.single.transactionId, 'sale-2');
  });

  test('listUnpaidInvoices filters by party + direction', () async {
    await repo.applyUnpaidInvoicesPayload({
      'unpaid_invoices': [
        _row(txnId: 's-1', partyId: 'party-A', direction: 'I'),
        _row(txnId: 's-2', partyId: 'party-A', direction: 'O',
            originalAmount: 40),
        _row(txnId: 's-3', partyId: 'party-B', direction: 'I',
            originalAmount: 60),
      ],
    });
    final aIn = await repo.listUnpaidInvoices(
      shopId: 'shop-1',
      partyId: 'party-A',
      direction: 'I',
    );
    expect(aIn.map((r) => r.transactionId), ['s-1']);

    final aOut = await repo.listUnpaidInvoices(
      shopId: 'shop-1',
      partyId: 'party-A',
      direction: 'O',
    );
    expect(aOut.map((r) => r.transactionId), ['s-2']);

    final bIn = await repo.listUnpaidInvoices(
      shopId: 'shop-1',
      partyId: 'party-B',
      direction: 'I',
    );
    expect(bIn.map((r) => r.transactionId), ['s-3']);
  });

  test('listUnpaidInvoices orders oldest-first by occurred_at', () async {
    await repo.applyUnpaidInvoicesPayload({
      'unpaid_invoices': [
        _row(txnId: 'newer', occurredAtMs: 1800000000000),
        _row(txnId: 'older', occurredAtMs: 1600000000000),
        _row(txnId: 'middle', occurredAtMs: 1700000000000),
      ],
    });
    final rows = await repo.listUnpaidInvoices(
      shopId: 'shop-1',
      partyId: 'party-A',
      direction: 'I',
    );
    expect(
      rows.map((r) => r.transactionId).toList(),
      ['older', 'middle', 'newer'],
    );
  });
}
