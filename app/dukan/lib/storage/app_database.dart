// Application-wide singleton sqflite database. Opens lazily on first
// access and runs forward-only migrations up to the current schema
// version.
//
// File location: `${applicationDocumentsDirectory}/dukan.db`. iOS +
// Android put that in a no-backup area by default, so the queue and
// caches don't ride into device backups (they hold session-fresh
// data, not user content).
//
// Tests inject a path (typically `:memory:`) via `AppDatabase.openAt`
// to keep each test isolated. Production uses `AppDatabase.instance`,
// which opens the real path once and reuses the connection.

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'migrations/0001_initial.dart';
import 'migrations/0002_local_mirror.dart';
import 'migrations/0003_local_transaction_optimistic.dart';
import 'migrations/0004_local_unpaid_invoices.dart';
import 'migrations/0005_local_category_shop_id.dart';
import 'migrations/0006_local_shop_item_sale_recency.dart';
import 'migrations/0007_local_supplier_basket_and_qty.dart';

/// Current schema version. Increment when adding a migration; append
/// the migration to `_migrations` below in the matching slot.
const int kSchemaVersion = 7;

/// Ordered list of forward-only migrations. `_migrations[n - 1]` is
/// the migration that brings the DB from version n-1 to n.
final List<Future<void> Function(Database db)> _migrations = [
  applyInitialMigration,
  applyLocalMirrorMigration,
  applyLocalTransactionOptimisticMigration,
  applyLocalUnpaidInvoicesMigration,
  applyLocalCategoryShopIdMigration,
  applyLocalShopItemSaleRecencyMigration,
  applyLocalSupplierBasketAndQtyMigration,
];

class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  /// Underlying connection. Prefer the DAO classes (`PendingPostDao`,
  /// `CacheDao`, `DeviceConfigDao`) over reaching into this directly.
  Database get db => _db;

  static AppDatabase? _instance;
  static Future<AppDatabase>? _opening;

  /// Returns the process-wide database, opening it on first call.
  /// Idempotent — concurrent callers all await the same open future.
  static Future<AppDatabase> instance() async {
    if (_instance != null) return _instance!;
    _opening ??= _openProduction();
    final inst = await _opening!;
    _instance = inst;
    _opening = null;
    return inst;
  }

  static Future<AppDatabase> _openProduction() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'dukan.db');
    return openAt(path);
  }

  /// Open a database at [path]. Tests pass `:memory:` (or a temp
  /// path) and the production singleton uses the documents dir.
  static Future<AppDatabase> openAt(String path) async {
    final db = await openDatabase(
      path,
      version: kSchemaVersion,
      onCreate: (db, version) async {
        // Fresh install — run every migration in order so the schema
        // ends up at `version`. `onCreate` is called instead of
        // `onUpgrade` only on the very first open.
        for (var i = 0; i < version; i++) {
          await _migrations[i](db);
        }
      },
      onUpgrade: (db, from, to) async {
        for (var i = from; i < to; i++) {
          await _migrations[i](db);
        }
      },
    );
    return AppDatabase._(db);
  }

  /// Test helper. Closes the singleton and clears the instance so the
  /// next `instance()` call re-opens. Production callers should never
  /// need this — the connection is process-scoped.
  static Future<void> resetForTesting() async {
    final inst = _instance;
    _instance = null;
    _opening = null;
    if (inst != null) {
      await inst._db.close();
    }
  }

  /// Test helper. Installs [database] as the process-wide singleton
  /// so `instance()` returns it without touching the filesystem.
  /// Pair with [openTestDatabase] in the shared test harness.
  static void seedSingletonForTesting(AppDatabase database) {
    _instance = database;
    _opening = null;
  }

  Future<void> close() => _db.close();
}
