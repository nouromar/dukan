// Schema migration #0002 — local sqflite mirror tables for the
// offline-first architecture (#373).
//
// Each table mirrors a subset of the corresponding server table
// just enough to power daily-flow reads (Sale search + barcode,
// Receive search + supplier picker, Payment party picker,
// Expense category picker, history). The SyncEngine keeps these
// in step with the server via:
//   * `get_shop_full_sync` on a fresh device,
//   * `get_shop_*_delta` for ongoing catch-up,
//   * `postgres_changes` realtime stream for instant updates.
//
// `server_updated_at` is the server's `updated_at` timestamp
// stored as a Unix epoch ms int. The SyncEngine uses it for
// last-write-wins conflict resolution + as the cutoff for the
// next delta sync.
//
// `local_stock_projection` holds the in-flight stock effect of
// queued-but-not-yet-drained posts (Sale = negative delta,
// Receive = positive). UI math: displayed_stock =
// local_shop_item.current_stock - SUM(projection.delta).
//
// `local_sync_state` tracks per-resource last-synced timestamps
// + a boolean for "have we ever done the initial full sync".

import 'package:sqflite/sqflite.dart';

Future<void> applyLocalMirrorMigration(Database db) async {
  // -------------------------------------------------------------------
  // Items
  // -------------------------------------------------------------------
  await db.execute('''
    CREATE TABLE local_shop_item (
      shop_item_id       TEXT PRIMARY KEY,
      shop_id            TEXT NOT NULL,
      item_id            TEXT,
      display_name       TEXT NOT NULL,
      category_id        TEXT,
      base_unit_code     TEXT NOT NULL,
      current_stock      REAL NOT NULL DEFAULT 0,
      avg_cost           REAL NOT NULL DEFAULT 0,
      reorder_threshold  REAL,
      is_active          INTEGER NOT NULL DEFAULT 1,
      updated_at         INTEGER NOT NULL,
      server_updated_at  INTEGER NOT NULL
    )
  ''');
  await db.execute(
      'CREATE INDEX idx_local_shop_item_shop ON local_shop_item(shop_id, is_active)');
  await db.execute(
      'CREATE INDEX idx_local_shop_item_name ON local_shop_item(display_name COLLATE NOCASE)');

  // -------------------------------------------------------------------
  // Packagings
  // -------------------------------------------------------------------
  await db.execute('''
    CREATE TABLE local_shop_item_unit (
      shop_item_unit_id  TEXT PRIMARY KEY,
      shop_item_id       TEXT NOT NULL,
      unit_code          TEXT NOT NULL,
      packaging_label    TEXT NOT NULL,
      conversion_to_base REAL NOT NULL,
      sale_price         REAL,
      last_cost          REAL,
      is_default_sale    INTEGER NOT NULL DEFAULT 0,
      is_default_receive INTEGER NOT NULL DEFAULT 0,
      is_active          INTEGER NOT NULL DEFAULT 1,
      server_updated_at  INTEGER NOT NULL
    )
  ''');
  await db.execute(
      'CREATE INDEX idx_local_unit_item ON local_shop_item_unit(shop_item_id, is_active)');

  // -------------------------------------------------------------------
  // Aliases (fuzzy search)
  // -------------------------------------------------------------------
  await db.execute('''
    CREATE TABLE local_shop_item_alias (
      shop_item_id  TEXT NOT NULL,
      alias         TEXT NOT NULL,
      is_display    INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (shop_item_id, alias)
    )
  ''');
  await db.execute(
      'CREATE INDEX idx_local_alias ON local_shop_item_alias(alias COLLATE NOCASE)');

  // -------------------------------------------------------------------
  // Barcode index (O(1) scan lookup)
  // -------------------------------------------------------------------
  await db.execute('''
    CREATE TABLE local_shop_item_barcode (
      barcode            TEXT PRIMARY KEY,
      shop_item_unit_id  TEXT NOT NULL,
      is_primary         INTEGER NOT NULL DEFAULT 0
    )
  ''');

  // -------------------------------------------------------------------
  // Parties
  // -------------------------------------------------------------------
  await db.execute('''
    CREATE TABLE local_party (
      party_id           TEXT PRIMARY KEY,
      shop_id            TEXT NOT NULL,
      name               TEXT NOT NULL,
      phone              TEXT,
      type_code          TEXT NOT NULL,
      receivable         REAL NOT NULL DEFAULT 0,
      payable            REAL NOT NULL DEFAULT 0,
      is_active          INTEGER NOT NULL DEFAULT 1,
      server_updated_at  INTEGER NOT NULL
    )
  ''');
  await db.execute(
      'CREATE INDEX idx_local_party_type ON local_party(shop_id, type_code, is_active)');
  await db.execute(
      'CREATE INDEX idx_local_party_name ON local_party(name COLLATE NOCASE)');

  // -------------------------------------------------------------------
  // Expense categories (per-shop)
  // -------------------------------------------------------------------
  await db.execute('''
    CREATE TABLE local_expense_category (
      category_id  TEXT PRIMARY KEY,
      shop_id      TEXT NOT NULL,
      code         TEXT NOT NULL,
      name         TEXT NOT NULL,
      is_active    INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute(
      'CREATE INDEX idx_local_expense_category_shop ON local_expense_category(shop_id, is_active)');

  // -------------------------------------------------------------------
  // Reference data — units (global)
  // -------------------------------------------------------------------
  await db.execute('''
    CREATE TABLE local_unit (
      code           TEXT PRIMARY KEY,
      default_label  TEXT NOT NULL,
      is_active      INTEGER NOT NULL DEFAULT 1
    )
  ''');

  // -------------------------------------------------------------------
  // Reference data — product categories (global)
  // -------------------------------------------------------------------
  await db.execute('''
    CREATE TABLE local_category (
      category_id  TEXT PRIMARY KEY,
      code         TEXT NOT NULL,
      parent_id    TEXT,
      name         TEXT NOT NULL,
      sort_order   INTEGER NOT NULL DEFAULT 0,
      is_active    INTEGER NOT NULL DEFAULT 1
    )
  ''');

  // -------------------------------------------------------------------
  // Recent transactions for history offline
  // -------------------------------------------------------------------
  await db.execute('''
    CREATE TABLE local_transaction (
      txn_id            TEXT PRIMARY KEY,
      shop_id           TEXT NOT NULL,
      type_code         TEXT NOT NULL,
      occurred_at       INTEGER NOT NULL,
      total             REAL NOT NULL,
      party_id          TEXT,
      is_voided         INTEGER NOT NULL DEFAULT 0,
      server_updated_at INTEGER NOT NULL,
      payload_json      TEXT NOT NULL
    )
  ''');
  await db.execute(
      'CREATE INDEX idx_local_txn_shop_time ON local_transaction(shop_id, type_code, occurred_at DESC)');

  // -------------------------------------------------------------------
  // Stock projection (in-flight queue effect)
  // -------------------------------------------------------------------
  // pending_post_id refers to a row in `pending_post` (#363).
  // When the post drains or fails permanently, its projections
  // are deleted; current_stock comes back from the server's view
  // of the world via realtime / delta sync.
  await db.execute('''
    CREATE TABLE local_stock_projection (
      pending_post_id  TEXT NOT NULL,
      shop_item_id     TEXT NOT NULL,
      delta            REAL NOT NULL,
      PRIMARY KEY (pending_post_id, shop_item_id)
    )
  ''');
  await db.execute(
      'CREATE INDEX idx_proj_item ON local_stock_projection(shop_item_id)');

  // -------------------------------------------------------------------
  // Per-resource sync bookkeeping
  // -------------------------------------------------------------------
  // resource: 'items' | 'parties' | 'categories' | 'transactions'.
  // last_synced_at: epoch ms — passed as the cutoff to the next
  //   delta sync RPC for this resource.
  // full_sync_done: 1 once the first full_sync landed; gates the
  //   "no_local cold start" branch of the SyncEngine state
  //   machine.
  await db.execute('''
    CREATE TABLE local_sync_state (
      shop_id         TEXT NOT NULL,
      resource        TEXT NOT NULL,
      last_synced_at  INTEGER NOT NULL,
      full_sync_done  INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (shop_id, resource)
    )
  ''');
}
