// Schema migration #0001 — establishes the three foundational tables
// for the local sqflite-backed storage layer:
//
//   * pending_post  — durable offline write queue.
//   * cache_entry   — generic KV cache with TTL + size tracking.
//   * device_config — per-device key/value overrides for the
//                     hierarchical config (Phase 3 reads these too).
//
// `original_actor_user_id` lands on pending_post NOW even though the
// queue executor doesn't pass it to the server yet — the
// audit-stamping work in Phase 5 just turns on the existing column,
// so there's no schema migration when it ships.
//
// `schema_version` per row lets the executor dispatch correctly when
// the app is upgraded with posts still in flight.

import 'package:sqflite/sqflite.dart';

/// All SQL statements that make up the v1 schema.
Future<void> applyInitialMigration(Database db) async {
  await db.execute('''
    CREATE TABLE pending_post (
      id                      TEXT PRIMARY KEY,
      client_op_id            TEXT NOT NULL,
      shop_id                 TEXT NOT NULL,
      original_actor_user_id  TEXT NOT NULL,
      rpc                     TEXT NOT NULL,
      schema_version          INTEGER NOT NULL DEFAULT 1,
      params_json             TEXT NOT NULL,
      queued_at               INTEGER NOT NULL,
      attempts                INTEGER NOT NULL DEFAULT 0,
      last_attempt_at         INTEGER,
      last_error              TEXT,
      state                   TEXT NOT NULL DEFAULT 'pending'
    )
  ''');
  await db.execute('''
    CREATE INDEX idx_pending_post_state_queued
      ON pending_post(state, queued_at)
  ''');
  await db.execute('''
    CREATE UNIQUE INDEX uq_pending_post_clientop
      ON pending_post(shop_id, client_op_id)
  ''');

  await db.execute('''
    CREATE TABLE cache_entry (
      key           TEXT PRIMARY KEY,
      value_json    TEXT NOT NULL,
      written_at    INTEGER NOT NULL,
      expires_at    INTEGER,
      size_bytes    INTEGER NOT NULL,
      last_read_at  INTEGER NOT NULL
    )
  ''');
  await db.execute('CREATE INDEX idx_cache_expires ON cache_entry(expires_at)');
  await db.execute('CREATE INDEX idx_cache_lru ON cache_entry(last_read_at)');

  await db.execute('''
    CREATE TABLE device_config (
      key     TEXT PRIMARY KEY,
      value   TEXT NOT NULL,
      set_at  INTEGER NOT NULL
    )
  ''');
}
