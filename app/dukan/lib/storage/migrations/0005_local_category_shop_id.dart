import 'package:sqflite/sqflite.dart';

/// Adds `shop_id` to `local_category` so the per-shop custom product
/// categories introduced by backend migration 0076 can be mirrored
/// alongside the global ones. Global categories keep `shop_id` NULL.
Future<void> applyLocalCategoryShopIdMigration(Database db) async {
  await db.execute('ALTER TABLE local_category ADD COLUMN shop_id TEXT');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_local_category_shop '
    'ON local_category(shop_id, is_active)',
  );
}
