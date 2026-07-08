import 'package:sqflite/sqflite.dart';

/// `local_bono`: an on-device cache of captured bono images, keyed by the
/// client-minted document id, so bonos are viewable offline (View bono renders
/// from the cached bytes) and so an offline-captured bono survives until its
/// deferred upload drains. The JPEG bytes live in the `bytes` BLOB — kept in
/// sqflite (not a file on disk) so the compressed image (~150–300 KB) rides the
/// same durable, no-backup store as the queue and drains cleanly under the
/// widget-test DB factory.
///
/// `uploaded = 0` means these bytes are the ONLY copy (a pending upload) and
/// must never be evicted; `uploaded = 1` is a re-fetchable cache entry that
/// eviction may drop oldest-first when over the size cap.
Future<void> applyLocalBonoMigration(Database db) async {
  await db.execute('''
    CREATE TABLE local_bono (
      document_id TEXT PRIMARY KEY,
      shop_id     TEXT NOT NULL,
      ext         TEXT NOT NULL,
      size_bytes  INTEGER NOT NULL,
      cached_at   INTEGER NOT NULL,
      uploaded    INTEGER NOT NULL DEFAULT 0,
      bytes       BLOB NOT NULL
    )
  ''');
  // Eviction scans oldest uploaded entries first.
  await db.execute(
    'CREATE INDEX idx_local_bono_evict ON local_bono(uploaded, cached_at)',
  );
}
