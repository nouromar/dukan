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

  test('insertLocalShopItemUnit makes a new packaging show in the detail',
      () async {
    await repo.applyItemsPayload({
      'items': [_item('si-1', 'Bariis')],
      'units': [
        {
          'shop_item_unit_id': 'siu-base',
          'shop_item_id': 'si-1',
          'unit_code': 'kg',
          'packaging_label': 'Kg',
          'conversion_to_base': 1,
          'sale_price': 1.5,
          'is_default_sale': true,
          'is_default_receive': true,
          'is_active': true,
          'server_updated_at_ms': 1,
        },
      ],
      'aliases': [],
      'barcodes': [],
    });

    // Optimistic add of a new packaging (no sync yet).
    await repo.insertLocalShopItemUnit(
      shopItemUnitId: 'siu-box',
      shopItemId: 'si-1',
      unitCode: 'box',
      packagingLabel: '12 Kg Box',
      conversionToBase: 12,
      salePrice: 18.0,
    );

    final detail = await repo.getShopItemDetail('si-1');
    expect(detail, isNotNull);
    expect(
      detail!.units.map((u) => u.packagingLabel).toSet(),
      containsAll(<String>['Kg', '12 Kg Box']),
    );
    final box = detail.units.firstWhere((u) => u.shopItemUnitId == 'siu-box');
    expect(box.conversionToBase, 12);
    expect(box.salePrice, 18.0);
    expect(box.isActive, isTrue);
  });

  test('getShopItemDetail resolves the category name from the mirror', () async {
    await repo.applyCategoriesPayload({
      'categories': [
        {
          'id': 'cat-staples',
          'shop_id': shopId,
          'code': 'staples',
          'parent_id': null,
          'name': 'Staples',
          'sort_order': 0,
          'is_active': true,
        },
      ],
    });
    await repo.applyItemsPayload({
      'items': [
        {..._item('si-1', 'Bariis'), 'category_id': 'cat-staples'},
        _item('si-2', 'Salt'), // category_id null
      ],
      'units': [
        {
          'shop_item_unit_id': 'siu-1',
          'shop_item_id': 'si-1',
          'unit_code': 'kg',
          'packaging_label': 'Kg',
          'conversion_to_base': 1,
          'is_default_sale': true,
          'is_default_receive': true,
          'is_active': true,
          'server_updated_at_ms': 1,
        },
      ],
      'aliases': [],
      'barcodes': [],
    });

    // Categorized item → real name (was null on the mirror, so the detail
    // Category tile used to read "Other" on offline_mode = full).
    final categorized = await repo.getShopItemDetail('si-1');
    expect(categorized!.header.categoryName, 'Staples');

    // Uncategorized item → null (rendered as "Other" at the call site).
    final uncategorized = await repo.getShopItemDetail('si-2');
    expect(uncategorized!.header.categoryName, isNull);
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

  test('searchItems rankBy=recency ranks by sale_count then last_sold',
      () async {
    await repo.applyItemsPayload({
      'items': [
        _item('si-a', 'Aaa', saleCount: 1, lastSoldAtMs: 100),
        _item('si-b', 'Bbb', saleCount: 5, lastSoldAtMs: 200),
        _item('si-c', 'Ccc', saleCount: 5, lastSoldAtMs: 300), // tie count, newer
      ],
      'units': [],
      'aliases': [],
      'barcodes': [],
    });

    // Recency: count DESC, then last_sold DESC → c (5,300), b (5,200), a (1).
    final recency = await repo.searchItems('', shopId: shopId, rankBy: 'recency');
    expect(recency.map((i) => i.shopItemId), ['si-c', 'si-b', 'si-a']);

    // Default stays alphabetical.
    final byName = await repo.searchItems('', shopId: shopId);
    expect(byName.map((i) => i.shopItemId), ['si-a', 'si-b', 'si-c']);
  });

  test('applyOptimisticSaleRecency floats the just-sold item to the top',
      () async {
    await repo.applyItemsPayload({
      'items': [_item('si-x', 'Xxx'), _item('si-y', 'Yyy')], // both unsold
      'units': [],
      'aliases': [],
      'barcodes': [],
    });

    // Both unsold (count 0, last_sold NULL) → recency falls back to name.
    var recency = await repo.searchItems('', shopId: shopId, rankBy: 'recency');
    expect(recency.map((i) => i.shopItemId), ['si-x', 'si-y']);

    // Sell y → it jumps to the top immediately, before any sync.
    await repo.applyOptimisticSaleRecency(shopItemIds: ['si-y'], nowMs: 999);
    recency = await repo.searchItems('', shopId: shopId, rankBy: 'recency');
    expect(recency.map((i) => i.shopItemId), ['si-y', 'si-x']);
  });

  test('supplierBasket returns the supplier\'s items, most recent first',
      () async {
    await repo.applyItemsPayload({
      'items': [_item('si-1', 'Rice'), _item('si-2', 'Sugar'), _item('si-3', 'Tea')],
      'units': [
        _unit('u-1', 'si-1', 'sack', 'Rice — sack', 25),
        _unit('u-2', 'si-2', 'sack', 'Sugar — sack', 50),
        _unit('u-3', 'si-3', 'box', 'Tea — box', 1),
      ],
      'aliases': [],
      'barcodes': [],
      'supplier_items': [
        // sup-A brings rice (older) + sugar (newer), not tea.
        {'party_id': 'sup-A', 'shop_id': 'shop-1', 'shop_item_unit_id': 'u-1',
          'last_unit_cost': 20, 'last_received_at_ms': 100,
          'server_updated_at_ms': 100},
        {'party_id': 'sup-A', 'shop_id': 'shop-1', 'shop_item_unit_id': 'u-2',
          'last_unit_cost': 40, 'last_received_at_ms': 200,
          'server_updated_at_ms': 200},
      ],
    });

    // Sugar (200) leads rice (100); tea isn't in this supplier's basket.
    final basket = await repo.supplierBasket('sup-A', shopId: shopId);
    expect(basket.map((r) => r.shopItemId), ['si-2', 'si-1']);

    // Receiving tea now floats it to the top immediately.
    await repo.applyOptimisticSupplierBasket(
      supplierId: 'sup-A', shopId: shopId, shopItemUnitIds: ['u-3'], nowMs: 999);
    final basket2 = await repo.supplierBasket('sup-A', shopId: shopId);
    expect(basket2.first.shopItemId, 'si-3');
  });

  test('applyOptimisticStockForLines bumps current_stock by base-unit delta',
      () async {
    await repo.applyItemsPayload({
      'items': [_item('si-1', 'Rice', stock: 10)],
      'units': [_unit('u-1', 'si-1', 'sack', 'Rice — sack', 25)], // ×25
      'aliases': [],
      'barcodes': [],
    });

    // Receive 2 sacks → +50 base units → 60.
    await repo.applyOptimisticStockForLines(
      lines: [ProjectionLine(shopItemUnitId: 'u-1', quantity: 2, direction: 1)],
    );
    expect((await repo.getShopItem('si-1'))!.currentStock, 60);

    // Reverting (direction -1) restores it — the rejected-bono path.
    await repo.applyOptimisticStockForLines(
      lines: [ProjectionLine(shopItemUnitId: 'u-1', quantity: 2, direction: -1)],
    );
    expect((await repo.getShopItem('si-1'))!.currentStock, 10);
  });

  test('applyOptimisticPartyCharge raises (and revert lowers) supplier payable',
      () async {
    await repo.applyPartiesPayload({
      'parties': [_party('p-1', 'Acme', type: 'supplier', payable: 30)],
    });

    await repo.applyOptimisticPartyCharge(
        partyId: 'p-1', direction: 'O', amount: 50);
    var rows =
        await repo.searchParties('', shopId: shopId, typeCode: 'supplier');
    expect(rows.single.payable, 80);

    // applyOptimisticPartyPayment reverts it (the reject path).
    await repo.applyOptimisticPartyPayment(
        partyId: 'p-1', direction: 'O', amount: 50);
    rows = await repo.searchParties('', shopId: shopId, typeCode: 'supplier');
    expect(rows.single.payable, 30);
  });

  test('applyOptimisticPartyCreate mirrors a new party into the list',
      () async {
    expect(
      await repo.searchParties('', shopId: shopId, typeCode: 'customer'),
      isEmpty,
    );

    await repo.applyOptimisticPartyCreate(
      partyId: 'p-new',
      shopId: shopId,
      name: 'Khadija',
      typeCode: 'customer',
      receivable: 25,
    );

    final rows =
        await repo.searchParties('', shopId: shopId, typeCode: 'customer');
    expect(rows.single.partyId, 'p-new');
    expect(rows.single.name, 'Khadija');
    expect(rows.single.receivable, 25);
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

  test('searchParties rankBy=recency orders by most recent transaction',
      () async {
    await repo.applyPartiesPayload({
      'parties': [
        // p-old owes more (leads under default balance); p-new is more recent.
        _party('p-old', 'Aaa Old', type: 'customer', receivable: 50),
        _party('p-new', 'Zzz New', type: 'customer', receivable: 5),
      ],
    });
    // p-new transacted more recently than p-old (occurred_at 2000 > 1000).
    for (final t in [
      {'txn_id': 't1', 'occurred_at': 1000, 'party_id': 'p-old'},
      {'txn_id': 't2', 'occurred_at': 2000, 'party_id': 'p-new'},
    ]) {
      await database.db.insert('local_transaction', {
        'txn_id': t['txn_id'],
        'shop_id': shopId,
        'type_code': 'sale',
        'occurred_at': t['occurred_at'],
        'total': 0,
        'party_id': t['party_id'],
        'server_updated_at': 0,
        'payload_json': '{}',
      });
    }

    // Recency: most-recent first (p-new), even though it owes less.
    final recency = await repo.searchParties('',
        shopId: shopId, typeCode: 'customer', rankBy: 'recency');
    expect(recency.map((p) => p.partyId), ['p-new', 'p-old']);

    // Default (balance): higher-debt party (p-old) leads, recency ignored.
    final byBalance =
        await repo.searchParties('', shopId: shopId, typeCode: 'customer');
    expect(byBalance.map((p) => p.partyId), ['p-old', 'p-new']);
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

  test('getPaymentDetailLocal reads a payment from the mirror (offline)',
      () async {
    await repo.applyTransactionsPayload({
      'transactions': [
        {
          ..._txn('pay-1', 'payment', occurredMs: 1000, total: 25),
          'party_id': 'party-9',
          'direction': 'I',
          'party_name': 'Axmed',
          'notes': 'debt settle',
          'is_refund': false,
        },
      ],
    });

    final d = await repo.getPaymentDetailLocal('pay-1');
    expect(d, isNotNull);
    expect(d!.paymentId, 'pay-1');
    expect(d.amount, 25);
    expect(d.direction, 'I');
    expect(d.partyId, 'party-9');
    expect(d.partyName, 'Axmed');
    expect(d.notes, 'debt settle');

    // A non-payment txn (or missing) returns null.
    expect(await repo.getPaymentDetailLocal('nope'), isNull);
  });

  test('settlement leg is flagged locally and links back to its sale',
      () async {
    await repo.applyTransactionsPayload({
      'transactions': [
        // A walk-in cash sale (base op id).
        {..._txn('sale-1', 'sale', occurredMs: 1000, total: 10),
          'client_op_id': 'op-xyz'},
        // Its till-cash leg: party-less, client_op_id = <base>:payment.
        {..._txn('leg-1', 'payment', occurredMs: 1000, total: 10),
          'direction': 'I', 'client_op_id': 'op-xyz:payment'},
        // A normal debt-settlement payment (no :payment suffix).
        {..._txn('pay-2', 'payment', occurredMs: 2000, total: 25),
          'party_id': 'party-9', 'direction': 'I', 'party_name': 'Axmed',
          'client_op_id': 'op-abc'},
      ],
    });

    // Detail read derives the flag + carries the client_op_id.
    final leg = await repo.getPaymentDetailLocal('leg-1');
    expect(leg!.isSettlementLeg, isTrue);
    expect(leg.clientOpId, 'op-xyz:payment');
    final normal = await repo.getPaymentDetailLocal('pay-2');
    expect(normal!.isSettlementLeg, isFalse);

    // The leg resolves back to its originating sale; a non-leg op → null.
    expect(await repo.settlementLegSourceTxnId('op-xyz:payment'), 'sale-1');
    expect(await repo.settlementLegSourceTxnId('op-abc'), isNull);

    // toPaymentSummary mirrors the flag off client_op_id.
    final summaries = (await repo.historyPayments(shopId: shopId))
        .map(repo.toPaymentSummary)
        .toList();
    expect(
      summaries.firstWhere((s) => s.paymentId == 'leg-1').isSettlementLeg,
      isTrue,
    );
    expect(
      summaries.firstWhere((s) => s.paymentId == 'pay-2').isSettlementLeg,
      isFalse,
    );
  });

  test('getExpenseDetailLocal reads an expense from the mirror (offline)',
      () async {
    await repo.applyTransactionsPayload({
      'transactions': [
        {
          ..._txn('exp-1', 'expense', occurredMs: 2000, total: 40),
          'category_id': 'cat-rent',
          'category_name': 'Rent',
          'notes': 'July',
        },
      ],
    });

    final e = await repo.getExpenseDetailLocal('exp-1');
    expect(e, isNotNull);
    expect(e!.txnId, 'exp-1');
    expect(e.amount, 40);
    expect(e.categoryName, 'Rent');
    expect(e.notes, 'July');
    expect(await repo.getExpenseDetailLocal('nope'), isNull);
  });

  test('writeOptimisticTransaction keys the row by the client txnId, not the '
      'client_op_id (0097 offline-void support)', () async {
    const txnId = '00000000-0000-4000-8000-00000000e001';
    const opId = 'expense-1783095528341-3366287978';
    await repo.writeOptimisticTransaction(
      clientOpId: opId,
      txnId: txnId,
      shopId: shopId,
      typeCode: 'expense',
      occurredAtMs: 1000,
      total: 12,
      payload: const {'category_id': 'c1', 'category_name': 'Rent'},
    );
    // The mirror row is addressable by the UUID (what a later void will use),
    // and NOT by the client_op_id placeholder.
    final byUuid = await repo.getTransaction(txnId);
    expect(byUuid, isNotNull);
    expect(byUuid!.clientOpId, opId);
    expect(await repo.getTransaction(opId), isNull);
    // And the expense detail reads back under the UUID.
    expect((await repo.getExpenseDetailLocal(txnId))!.txnId, txnId);
  });

  test('lowStockLocal: at/below threshold, or below 1 when no threshold',
      () async {
    await repo.applyItemsPayload({
      'items': [
        {..._item('si-1', 'Rice', stock: 2), 'reorder_threshold': 5}, // low
        {..._item('si-2', 'Sugar', stock: 10), 'reorder_threshold': 5}, // ok
        _item('si-3', 'Salt', stock: 0.5), // no threshold, <1 → low
        _item('si-4', 'Oil', stock: 3), // no threshold, >=1 → ok
        {..._item('si-5', 'Tea', stock: 1), 'reorder_threshold': 1}, // low (==)
      ],
      'units': [],
      'aliases': [],
      'barcodes': [],
    });

    final low = await repo.lowStockLocal('shop-1');
    // Most-below-threshold first: si-1 (-3), si-3 (-0.5), si-5 (0).
    expect(low.map((r) => r.shopItemId), ['si-1', 'si-3', 'si-5']);
    expect(low.first.currentStock, 2);
    expect(low.first.baseUnitLabel, 'kg'); // base_unit_code as the label
  });

  test('applyOptimisticVoid flags the local txn as voided', () async {
    await repo.applyTransactionsPayload({
      'transactions': [_txn('s-void', 'sale', occurredMs: 1000, total: 12)],
    });
    expect((await repo.getTransaction('s-void'))!.isVoided, isFalse);

    await repo.applyOptimisticVoid('s-void');
    expect((await repo.getTransaction('s-void'))!.isVoided, isTrue);
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

  test('#387: wipeAllLocalData clears every per-shop mirror table',
      () async {
    await repo.applyItemsPayload({
      'items': [_item('si-1', 'Rice')],
      'units': [_unit('siu-1', 'si-1', 'kg', 'kg', 1)],
      'aliases': [
        {'shop_item_id': 'si-1', 'alias': 'bariis', 'is_display': false},
      ],
      'barcodes': [
        {'shop_item_unit_id': 'siu-1', 'barcode': '123', 'is_primary': true},
      ],
    });
    await repo.applyPartiesPayload({
      'parties': [_party('p-1', 'Ahmed', type: 'customer')],
    });
    await repo.applyCategoriesPayload({
      'expense_categories': [
        {
          'category_id': 'c-1',
          'shop_id': shopId,
          'code': 'rent',
          'name': 'Rent',
          'is_active': true,
        },
      ],
    });
    await repo.applyTransactionsPayload({
      'transactions': [_txn('t-1', 'sale', occurredMs: 1700, total: 50)],
    });
    await repo.writeSyncState(
      shopId: shopId,
      resource: 'items',
      lastSyncedAtMs: 9999,
      fullSyncDone: true,
    );
    // Pre-assert there is something to wipe.
    expect((await repo.allActiveItems(shopId)), isNotEmpty);
    expect(
      (await repo.searchParties('', shopId: shopId, typeCode: 'customer')),
      isNotEmpty,
    );
    expect((await repo.expenseCategories(shopId: shopId)), isNotEmpty);
    expect((await repo.historySales(shopId: shopId)), isNotEmpty);
    expect((await repo.loadSyncState(shopId)), isNotEmpty);

    await repo.wipeAllLocalData(shopId);

    expect((await repo.allActiveItems(shopId)), isEmpty);
    expect(
      (await repo.searchParties('', shopId: shopId, typeCode: 'customer')),
      isEmpty,
    );
    expect((await repo.expenseCategories(shopId: shopId)), isEmpty);
    expect((await repo.historySales(shopId: shopId)), isEmpty);
    expect((await repo.loadSyncState(shopId)), isEmpty);
    expect(await repo.lookupBarcode('123'), isNull);
    expect(await repo.packagingsForItem('si-1'), isEmpty);
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
  int saleCount = 0,
  int? lastSoldAtMs,
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
      'sale_count': saleCount,
      'last_sold_at_ms': lastSoldAtMs,
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

