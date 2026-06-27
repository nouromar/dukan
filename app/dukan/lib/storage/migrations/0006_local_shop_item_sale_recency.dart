import 'package:sqflite/sqflite.dart';

/// Adds sale-recency columns to `local_shop_item` so the Sale item list can
/// rank "most / most-recently sold first" (backend migration 0079).
///
/// `last_sold_at` is epoch-ms (nullable until the item is sold). `sale_count`
/// mirrors the server's combined cross-device count from the items delta, and
/// is also bumped optimistically on a local sale for instant feedback; the next
/// sync overwrites it with the authoritative server value.
Future<void> applyLocalShopItemSaleRecencyMigration(Database db) async {
  await db
      .execute('ALTER TABLE local_shop_item ADD COLUMN last_sold_at INTEGER');
  await db.execute(
    'ALTER TABLE local_shop_item ADD COLUMN sale_count INTEGER NOT NULL DEFAULT 0',
  );
}
