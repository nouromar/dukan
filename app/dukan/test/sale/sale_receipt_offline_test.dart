// Unit tests for the #375 offline sale receipt path. Widget-mounting
// SaleReceiptView under fake-async has proven flaky (Material Card +
// ListView keep ticking under our test clock), so we test the
// boundary's two seams directly:
//   - SaleReceiptFallback.fromCart — the snapshot conversion that
//     lets the receipt render before the txn is mirrored locally.
//   - LocalRepository.getTransaction + saleLinesFromLocal — the
//     local-mirror lookup the SaleReceiptView consults first under
//     offline_mode=full.

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/sale/cart_controller.dart';
import 'package:dukan/sale/sale_detail_screen.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/sync/local_repository.dart';

import '../shared/test_database.dart';

void main() {
  group('SaleReceiptFallback.fromCart', () {
    test('cash sale: total + paid_amount equal, payment_method=cash',
        () {
      final snapshot = CartSnapshot(
        lines: {
          'siu-1': CartLine(
            shopItemUnitId: 'siu-1',
            shopItemId: 'si-1',
            itemId: 'i-1',
            displayName: 'Bread',
            packagingLabel: 'loaf',
            baseUnitLabel: 'piece',
            unitPrice: 5,
            quantity: 2,
          ),
        },
        debt: false,
        customer: null,
      );
      final fallback = SaleReceiptFallback.fromCart(snapshot);
      expect(fallback.totalAmount, 10);
      expect(fallback.paidAmount, 10);
      expect(fallback.paymentMethodCode, 'cash');
      expect(fallback.partyName, isNull);
      expect(fallback.lines, hasLength(1));
      expect(fallback.lines.single.itemName, 'Bread');
      expect(fallback.lines.single.quantity, 2);
      expect(fallback.lines.single.lineTotal, 10);
    });

    test('debt sale: paid=0, customer name surfaced, no payment method',
        () {
      final snapshot = CartSnapshot(
        lines: {
          'siu-1': CartLine(
            shopItemUnitId: 'siu-1',
            shopItemId: 'si-1',
            itemId: 'i-1',
            displayName: 'Sugar',
            packagingLabel: 'kg',
            baseUnitLabel: 'kg',
            unitPrice: 8,
          ),
        },
        debt: true,
        customer: const PartySearchResult(
          id: 'p-1',
          name: 'Ahmed',
          phone: null,
          typeCode: 'customer',
          receivable: 0,
          payable: 0,
        ),
      );
      final fallback = SaleReceiptFallback.fromCart(snapshot);
      expect(fallback.totalAmount, 8);
      expect(fallback.paidAmount, 0);
      expect(fallback.paymentMethodCode, isNull);
      expect(fallback.partyName, 'Ahmed');
    });
  });

  group('local-mirror receipt source', () {
    late AppDatabase database;
    late LocalRepository repo;

    setUp(() async {
      database = await openTestDatabase();
      repo = LocalRepository(Future.value(database));
    });
    tearDown(() async {
      await database.close();
    });

    test(
        'getTransaction + saleLinesFromLocal returns the receipt payload',
        () async {
      await repo.applyTransactionsPayload({
        'transactions': [
          {
            'txn_id': 'txn-1',
            'shop_id': 'shop-1',
            'type_code': 'sale',
            'occurred_at_ms': 1700000000000,
            'total': 25,
            'party_id': null,
            'is_voided': false,
            'server_updated_at_ms': 1700000000000,
            'party_name': 'Ahmed',
            'payment_method_code': 'cash',
            'paid_amount': 25,
            'lines': [
              {
                'line_no': 1,
                'item_id': 'i-1',
                'shop_item_unit_id': 'siu-1',
                'item_name': 'Rice',
                'quantity': 1,
                'unit_label': 'kg',
                'unit_amount': 25,
                'line_total': 25,
                'packaging_label': 'Rice 5kg',
              }
            ],
          }
        ],
      });
      final t = await repo.getTransaction('txn-1');
      expect(t, isNotNull);
      final header = repo.toSaleSummary(t!);
      expect(header.totalAmount, 25);
      expect(header.partyName, 'Ahmed');
      expect(header.paymentMethodCode, 'cash');

      final lines = await repo.saleLinesFromLocal('txn-1');
      expect(lines, hasLength(1));
      expect(lines.single.itemName, 'Rice');
    });

    test('getTransaction returns null when txn not yet mirrored',
        () async {
      final t = await repo.getTransaction('nope');
      expect(t, isNull);
    });
  });
}
