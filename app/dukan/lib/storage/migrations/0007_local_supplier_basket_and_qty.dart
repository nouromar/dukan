import 'package:sqflite/sqflite.dart';

/// Slices 3 + 4 mirror (backend migration 0080):
///  - `local_supplier_item`: which packagings each supplier usually brings, with
///    last cost + recency, for the Receive supplier basket.
///  - `last_sale_qty` / `last_receive_qty` on `local_shop_item_unit`: the learned
///    usual quantity per packaging, for the quantity chips.
///
/// Both ride the items delta — `supplier_items` and the two unit fields are
/// applied by [LocalRepository.applyItemsPayload].
Future<void> applyLocalSupplierBasketAndQtyMigration(Database db) async {
  await db.execute('''
    CREATE TABLE local_supplier_item (
      party_id          TEXT NOT NULL,
      shop_item_unit_id TEXT NOT NULL,
      shop_id           TEXT NOT NULL,
      last_unit_cost    REAL,
      last_received_at  INTEGER,
      server_updated_at INTEGER NOT NULL,
      PRIMARY KEY (party_id, shop_item_unit_id)
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_local_supplier_item_basket '
    'ON local_supplier_item(shop_id, party_id, last_received_at DESC)',
  );
  await db.execute(
    'ALTER TABLE local_shop_item_unit ADD COLUMN last_sale_qty REAL',
  );
  await db.execute(
    'ALTER TABLE local_shop_item_unit ADD COLUMN last_receive_qty REAL',
  );
}
