// On-device cache of captured bono images, keyed by the client-minted document
// id. Two jobs: (1) hold an offline-captured bono until its deferred upload
// drains (these bytes are the ONLY copy — `uploaded = 0`), and (2) let View
// bono render the photo offline from the cached bytes instead of a signed URL.
//
// The compressed JPEG (~150–300 KB) is stored as a BLOB in the `local_bono`
// table (schema v8) rather than a file on disk: it rides the same durable,
// no-backup sqflite store as the queue, and (unlike real filesystem I/O) drains
// cleanly under the widget-test DB factory. Growth is bounded — once uploaded
// (`uploaded = 1`) an entry is re-fetchable from Storage, so eviction may drop
// it oldest-first over the size cap; a pending entry is never evicted.

import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'package:dukan/storage/app_database.dart';

/// ~50 MB ≈ 200 bonos at ~150–300 KB each.
const int kBonoCacheMaxBytes = 50 * 1024 * 1024;

class BonoImageCache {
  BonoImageCache({
    required Future<AppDatabase> database,
    int maxBytes = kBonoCacheMaxBytes,
    DateTime Function()? clock,
  })  : _database = database,
        _maxBytes = maxBytes,
        _clock = clock ?? DateTime.now;

  final Future<AppDatabase> _database;
  final int _maxBytes;
  final DateTime Function() _clock;

  Future<Database> get _db => _database.then((d) => d.db);

  /// Cache captured bytes (uploaded=0); replaces any prior copy for the id.
  Future<void> put({
    required String documentId,
    required String shopId,
    required String ext,
    required Uint8List bytes,
  }) async {
    await (await _db).insert(
      'local_bono',
      {
        'document_id': documentId,
        'shop_id': shopId,
        'ext': ext,
        'size_bytes': bytes.length,
        'cached_at': _clock().millisecondsSinceEpoch,
        'uploaded': 0,
        'bytes': bytes,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Cached bytes for a bono, or null if not cached. Used by View bono
  /// (offline render) and the drain executor (deferred upload).
  Future<Uint8List?> bytesFor(String documentId) async {
    final rows = await (await _db).query(
      'local_bono',
      columns: ['bytes'],
      where: 'document_id = ?',
      whereArgs: [documentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final blob = rows.first['bytes'];
    return blob is Uint8List ? blob : Uint8List.fromList(blob as List<int>);
  }

  Future<bool> has(String documentId) async {
    final rows = await (await _db).query(
      'local_bono',
      columns: ['document_id'],
      where: 'document_id = ?',
      whereArgs: [documentId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> markUploaded(String documentId) async {
    await (await _db).update(
      'local_bono',
      {'uploaded': 1},
      where: 'document_id = ?',
      whereArgs: [documentId],
    );
  }

  Future<void> deleteFor(String documentId) async {
    await (await _db)
        .delete('local_bono', where: 'document_id = ?', whereArgs: [documentId]);
  }

  /// Drop oldest UPLOADED entries until total cached size is under the cap.
  /// Pending (uploaded=0) entries are the only copy → never evicted.
  Future<void> evictToLimit() async {
    final db = await _db;
    final totalRow = await db.rawQuery(
      'SELECT COALESCE(SUM(size_bytes), 0) AS total FROM local_bono',
    );
    var total = (totalRow.first['total'] as int?) ?? 0;
    if (total <= _maxBytes) return;
    final evictable = await db.query(
      'local_bono',
      columns: ['document_id', 'size_bytes'],
      where: 'uploaded = 1',
      orderBy: 'cached_at ASC',
    );
    for (final row in evictable) {
      if (total <= _maxBytes) break;
      await db.delete('local_bono',
          where: 'document_id = ?', whereArgs: [row['document_id']]);
      total -= row['size_bytes'] as int;
    }
  }
}
