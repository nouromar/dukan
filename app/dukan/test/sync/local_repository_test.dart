// Unit tests for LocalRepository — reads + projection math + the
// apply* upserts that the SyncEngine drives.

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

  test('searchItems returns active items by display_name + aliases',
      () async {
    await repo.applyItemsPayload({
      'items': [
        _item('si-1', 'Rice 5kg', stock: 12),
        _item('si-2', 'Sugar 1kg'),
        _item('si-3', 'Tea 100g'),
      ],
      'units': [],
      'aliases': [
        {'shop_item_id': 'si-1', 'alias': 'bariis', 'is_display': false},
      ],
      'barcodes': [],
    });

    final byName = await repo.searchItems('rice', shopId: shopId);
    expect(byName.map((i) => i.shopItemId), contains('si-1'));

    // Match via alias.
    final byAlias = await repo.searchItems('bariis', shopId: shopId);
    expect(byAlias.map((i) => i.shopItemId), contains('si-1'));

    final all = await repo.searchItems('', shopId: shopId);
    expect(all.length, 3);
  });

  test('lookupBarcode returns the matching shop_item_unit', () async {
    await repo.applyItemsPayload({
      'items': [_item('si-1', 'Rice 5kg')],
      'units': [_unit('siu-1', 'si-1', 'kg', 'Rice — 5kg', 5, price: 80000)],
      'aliases': [],
      'barcodes': [
        {
          'barcode': '0123456789012',
          'shop_item_unit_id': 'siu-1',
          'is_primary': true,
        },
      ],
    });

    final hit = await repo.lookupBarcode('0123456789012');
    expect(hit, isNotNull);
    expect(hit!.shopItemUnitId, 'siu-1');
    expect(hit.shopItemId, 'si-1');

    final miss = await repo.lookupBarcode('9999999999999');
    expect(miss, isNull);
  });

  test('packagingsForItem returns active packagings sorted by conversion',
      () async {
    await repo.applyItemsPayload({
      'items': [_item('si-1', 'Rice 5kg')],
      'units': [
        _unit('siu-big', 'si-1', 'bag', 'Rice — bag', 50),
        _unit('siu-small', 'si-1', 'kg', 'Rice — 5kg', 5),
      ],
      'aliases': [],
      'barcodes': [],
    });

    final packs = await repo.packagingsForItem('si-1');
    expect(packs.map((u) => u.shopItemUnitId), ['siu-small', 'siu-big']);
  });

  test('searchParties filters by type_code + name', () async {
    await repo.applyPartiesPayload({
      'parties': [
        _party('p-cust', 'Ahmed', type: 'customer'),
        _party('p-supp', 'Big Supplier Co', type: 'supplier'),
      ],
    });

    final customers =
        await repo.searchParties('', shopId: shopId, typeCode: 'customer');
    expect(customers.map((p) => p.partyId), ['p-cust']);

    final supplier =
        await repo.searchParties('big', shopId: shopId, typeCode: 'supplier');
    expect(supplier.length, 1);
    expect(supplier.first.partyId, 'p-supp');
  });

  test('expenseCategories returns active rows for the shop', () async {
    await repo.applyCategoriesPayload({
      'expense_categories': [
        {
          'category_id': 'ec-1',
          'shop_id': shopId,
          'code': 'rent',
          'name': 'Rent',
          'is_active': true,
        },
        {
          'category_id': 'ec-2',
          'shop_id': shopId,
          'code': 'utilities',
          'name': 'Utilities',
          'is_active': false,
        },
      ],
      'categories': [],
      'units': [],
    });

    final rows = await repo.expenseCategories(shopId: shopId);
    expect(rows.map((c) => c.categoryId), ['ec-1']);
  });

  test('historySales orders sales most-recent first', () async {
    await repo.applyTransactionsPayload({
      'transactions': [
        _txn('t-1', 'sale', occurredMs: 1000, total: 10),
        _txn('t-2', 'sale', occurredMs: 3000, total: 20),
        _txn('t-3', 'receive', occurredMs: 2500, total: 50),
      ],
    });

    final sales = await repo.historySales(shopId: shopId);
    expect(sales.map((t) => t.txnId), ['t-2', 't-1']);
  });

  test('projectedStock subtracts pending sale deltas', () async {
    await repo.applyItemsPayload({
      'items': [_item('si-1', 'Rice 5kg', stock: 10)],
      'units': [],
      'aliases': [],
      'barcodes': [],
    });
    await repo.writeProjection(
      pendingPostId: 'pp-1',
      shopItemId: 'si-1',
      delta: -3,
    );
    await repo.writeProjection(
      pendingPostId: 'pp-2',
      shopItemId: 'si-1',
      delta: -1,
    );

    expect(await repo.projectedStock('si-1'), 6);

    await repo.clearProjectionsForPost('pp-1');
    expect(await repo.projectedStock('si-1'), 9);
  });

  test('writeSyncState preserves fullSyncDone when null is passed',
      () async {
    await repo.writeSyncState(
      shopId: shopId,
      resource: 'items',
      lastSyncedAtMs: 1000,
      fullSyncDone: true,
    );
    await repo.writeSyncState(
      shopId: shopId,
      resource: 'items',
      lastSyncedAtMs: 2000,
    );
    final state = await repo.loadSyncState(shopId);
    expect(state['items']!.lastSyncedAtMs, 2000);
    expect(state['items']!.fullSyncDone, isTrue);
  });
}

// --- Fixture helpers -----------------------------------------------------

Map<String, dynamic> _item(
  String id,
  String name, {
  num stock = 0,
  num avgCost = 0,
  bool active = true,
  int updatedAtMs = 1700000000000,
}) =>
    {
      'shop_item_id': id,
      'shop_id': 'shop-1',
      'item_id': null,
      'display_name': name,
      'category_id': null,
      'base_unit_code': 'kg',
      'current_stock': stock,
      'avg_cost': avgCost,
      'reorder_threshold': null,
      'is_active': active,
      'server_updated_at_ms': updatedAtMs,
    };

Map<String, dynamic> _unit(
  String id,
  String shopItemId,
  String unitCode,
  String label,
  num conversion, {
  num? price,
  num? lastCost,
  bool active = true,
  int updatedAtMs = 1700000000000,
}) =>
    {
      'shop_item_unit_id': id,
      'shop_item_id': shopItemId,
      'unit_code': unitCode,
      'packaging_label': label,
      'conversion_to_base': conversion,
      'sale_price': price,
      'last_cost': lastCost,
      'is_default_sale': false,
      'is_default_receive': false,
      'is_active': active,
      'server_updated_at_ms': updatedAtMs,
    };

Map<String, dynamic> _party(
  String id,
  String name, {
  required String type,
  num receivable = 0,
  num payable = 0,
  bool active = true,
}) =>
    {
      'party_id': id,
      'shop_id': 'shop-1',
      'name': name,
      'phone': null,
      'type_code': type,
      'receivable': receivable,
      'payable': payable,
      'is_active': active,
      'server_updated_at_ms': 1700000000000,
    };

Map<String, dynamic> _txn(
  String id,
  String typeCode, {
  required int occurredMs,
  required num total,
}) =>
    {
      'txn_id': id,
      'shop_id': 'shop-1',
      'type_code': typeCode,
      'occurred_at_ms': occurredMs,
      'total': total,
      'party_id': null,
      'payment_method_code': 'cash',
      'is_voided': false,
      'server_updated_at_ms': occurredMs,
      'lines_summary': const [],
    };

