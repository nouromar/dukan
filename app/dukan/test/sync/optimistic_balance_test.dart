// Optimistic mirror writes that make a stock adjustment / party payment
// reflect on the list screens instantly (the denormalized columns the
// lists read are bumped locally; sync later reconciles to server truth).

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/storage/app_database.dart';
import 'package:dukan/sync/local_repository.dart';

import '../shared/test_database.dart';

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

  Future<num> readStock(String id) async {
    final rows = await database.db.query('local_shop_item',
        columns: ['current_stock'],
        where: 'shop_item_id = ?',
        whereArgs: [id]);
    return rows.first['current_stock'] as num;
  }

  Future<List<num>> readBalances(String id) async {
    final rows = await database.db.query('local_party',
        columns: ['receivable', 'payable'],
        where: 'party_id = ?',
        whereArgs: [id]);
    return [rows.first['receivable'] as num, rows.first['payable'] as num];
  }

  test('applyOptimisticStockDelta bumps stock both ways', () async {
    await database.db.insert('local_shop_item', {
      'shop_item_id': 'si-1',
      'shop_id': 'shop-1',
      'item_id': 'i-1',
      'display_name': 'Bariis',
      'base_unit_code': 'kg',
      'current_stock': 50,
      'avg_cost': 0,
      'is_active': 1,
      'updated_at': 0,
      'server_updated_at': 0,
    });

    await repo.applyOptimisticStockDelta(shopItemId: 'si-1', baseUnitDelta: 10);
    expect(await readStock('si-1'), 60);

    await repo.applyOptimisticStockDelta(shopItemId: 'si-1', baseUnitDelta: -15);
    expect(await readStock('si-1'), 45);
  });

  test('applyOptimisticPartyPayment decrements the right side, clamped at 0',
      () async {
    await database.db.insert('local_party', {
      'party_id': 'cust',
      'shop_id': 'shop-1',
      'name': 'Asha',
      'type_code': 'customer',
      'receivable': 100,
      'payable': 0,
      'is_active': 1,
      'server_updated_at': 0,
    });
    await database.db.insert('local_party', {
      'party_id': 'supp',
      'shop_id': 'shop-1',
      'name': 'Hodan',
      'type_code': 'supplier',
      'receivable': 0,
      'payable': 80,
      'is_active': 1,
      'server_updated_at': 0,
    });

    // Customer payment ('I') reduces receivable only.
    await repo.applyOptimisticPartyPayment(
        partyId: 'cust', direction: 'I', amount: 30);
    expect(await readBalances('cust'), [70, 0]);

    // Supplier payment ('O') reduces payable only.
    await repo.applyOptimisticPartyPayment(
        partyId: 'supp', direction: 'O', amount: 30);
    expect(await readBalances('supp'), [0, 50]);

    // Overpay clamps at 0 (never negative).
    await repo.applyOptimisticPartyPayment(
        partyId: 'cust', direction: 'I', amount: 1000);
    expect(await readBalances('cust'), [0, 0]);
  });
}
