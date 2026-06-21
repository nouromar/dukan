// Generic key/value cache backed by the `cache_entry` sqflite table.
// Every entry tracks its serialized size and last-read timestamp so
// the LRU + size-budget eviction (Phase 2) can run as the cache
// grows.
//
// Reads update `last_read_at` so a frequently-touched entry is
// promoted out of LRU eviction candidacy. Writes auto-stamp
// `written_at` and compute `size_bytes` from the encoded JSON
// length.
//
// All values are stored as TEXT (JSON). Callers serialize before
// `put()` and decode after `get()` — keeps the DAO type-agnostic.

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/storage_defaults.dart';

class CacheEntry {
  const CacheEntry({
    required this.key,
    required this.valueJson,
    required this.writtenAt,
    required this.expiresAt,
    required this.sizeBytes,
    required this.lastReadAt,
  });

  final String key;
  final String valueJson;
  final DateTime writtenAt;
  final DateTime? expiresAt;
  final int sizeBytes;
  final DateTime lastReadAt;

  bool isExpired(DateTime now) =>
      expiresAt != null && now.isAfter(expiresAt!);
}

class CacheDao {
  CacheDao(
    this._database, {
    DateTime Function()? clock,
    int? budgetBytes,
    this.configResolver,
  })  : _clock = clock ?? DateTime.now,
        _explicitBudgetBytes = budgetBytes;

  /// Future-typed so the DAO can be constructed synchronously while
  /// sqflite finishes opening. main.dart awaits the open before
  /// runApp, so methods resolve instantly in practice.
  final Future<AppDatabase> _database;
  final DateTime Function() _clock;

  /// Optional config layer (Phase 3). When set, the cache budget
  /// comes from `cacheBudgetMb` (defaults → org → shop → device).
  /// Tests pass `budgetBytes:` explicitly; production wires the
  /// resolver.
  final ConfigResolver? configResolver;
  final int? _explicitBudgetBytes;

  int get _budgetBytes {
    if (_explicitBudgetBytes != null) return _explicitBudgetBytes;
    final r = configResolver;
    if (r != null) {
      return r.resolve(ConfigKeys.cacheBudgetMb) * 1024 * 1024;
    }
    return kCacheBudgetBytes;
  }

  Future<Database> get _db => _database.then((d) => d.db);

  /// Fetch the entry under [key]. Returns null when missing OR when
  /// the entry has expired — expired entries are deleted lazily on
  /// read so the table doesn't accumulate dead rows.
  ///
  /// Updates `last_read_at` on a hit so LRU eviction prefers stale
  /// entries.
  Future<CacheEntry?> get(String key) async {
    final db = await _db;
    final rows = await db.query(
      'cache_entry',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    // Corruption tolerance: if the row can't be decoded into a
    // CacheEntry (e.g. value_json field type changed, written_at
    // missing), delete the bad row and treat as miss. Logged to
    // Sentry so we know if it's recurring.
    CacheEntry entry;
    try {
      entry = _rowToEntry(rows.first);
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan storage',
        context: ErrorDescription('cache_entry row corrupt — deleting'),
      ));
      await db.delete('cache_entry', where: 'key = ?', whereArgs: [key]);
      return null;
    }
    if (entry.isExpired(_clock())) {
      await db.delete('cache_entry', where: 'key = ?', whereArgs: [key]);
      return null;
    }
    await db.update(
      'cache_entry',
      {'last_read_at': _clock().millisecondsSinceEpoch},
      where: 'key = ?',
      whereArgs: [key],
    );
    return entry;
  }

  /// Insert or replace the entry at [key]. Pass [ttl] to set an
  /// `expires_at`; null means no expiry.
  ///
  /// After the write, if total cache size exceeds [_budgetBytes],
  /// runs eviction in this order:
  ///   1. Delete all expired rows.
  ///   2. If still over budget, delete by `last_read_at ASC` until
  ///      under budget.
  Future<void> put(
    String key,
    String valueJson, {
    Duration? ttl,
  }) async {
    final now = _clock();
    final expires = ttl == null ? null : now.add(ttl);
    final db = await _db;
    await db.insert(
      'cache_entry',
      {
        'key': key,
        'value_json': valueJson,
        'written_at': now.millisecondsSinceEpoch,
        'expires_at': expires?.millisecondsSinceEpoch,
        'size_bytes': valueJson.length,
        'last_read_at': now.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _enforceBudget();
  }

  Future<void> _enforceBudget() async {
    final total = await totalBytes();
    if (total <= _budgetBytes) return;
    // Expired-first sweep; cheap and often enough on its own.
    await evictExpired();
    await evictLruUntil(_budgetBytes);
  }

  /// Drop a single entry by [key]. No-op when missing.
  Future<void> remove(String key) async {
    await (await _db).delete('cache_entry', where: 'key = ?', whereArgs: [key]);
  }

  /// Total bytes used by all cache entries — used by the Phase 2
  /// budget enforcement and the (Phase 4) Storage & sync UI.
  Future<int> totalBytes() async {
    final rows = await (await _db).rawQuery(
      'SELECT COALESCE(SUM(size_bytes), 0) AS s FROM cache_entry',
    );
    return (rows.first['s'] as int?) ?? 0;
  }

  /// Summary for the Storage & sync screen (Phase 4). Computed in
  /// one query so the UI can poll cheaply.
  Future<({int totalBytes, int entryCount})> stats() async {
    final rows = await (await _db).rawQuery(
      'SELECT COALESCE(SUM(size_bytes), 0) AS s, COUNT(*) AS c FROM cache_entry',
    );
    final row = rows.first;
    return (
      totalBytes: (row['s'] as int?) ?? 0,
      entryCount: (row['c'] as int?) ?? 0,
    );
  }

  /// Eagerly remove every expired row. Returns the number deleted.
  /// Phase 2 wires this to fire on cache writes; for now exposed
  /// for tests / explicit cleanup paths.
  Future<int> evictExpired() async {
    return (await _db).delete(
      'cache_entry',
      where: 'expires_at IS NOT NULL AND expires_at < ?',
      whereArgs: [_clock().millisecondsSinceEpoch],
    );
  }

  /// LRU eviction: while total size > [maxBytes], delete the
  /// least-recently-read entries one by one. Returns the number
  /// evicted. Phase 2 wires this to fire on every successful `put()`
  /// if budget is exceeded.
  Future<int> evictLruUntil(int maxBytes) async {
    var deleted = 0;
    while (true) {
      final total = await totalBytes();
      if (total <= maxBytes) return deleted;
      final victim = await (await _db).query(
        'cache_entry',
        orderBy: 'last_read_at ASC',
        limit: 1,
      );
      if (victim.isEmpty) return deleted;
      await (await _db).delete(
        'cache_entry',
        where: 'key = ?',
        whereArgs: [victim.first['key']],
      );
      deleted++;
    }
  }

  /// Wipe every cache entry. Used by the "Free up space" button in
  /// the Storage & sync UI (Phase 4) and by tests.
  Future<void> clear() async {
    await (await _db).delete('cache_entry');
  }

  CacheEntry _rowToEntry(Map<String, dynamic> row) => CacheEntry(
        key: row['key'] as String,
        valueJson: row['value_json'] as String,
        writtenAt:
            DateTime.fromMillisecondsSinceEpoch(row['written_at'] as int, isUtc: true),
        expiresAt: row['expires_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['expires_at'] as int, isUtc: true),
        sizeBytes: (row['size_bytes'] as int?) ?? 0,
        lastReadAt:
            DateTime.fromMillisecondsSinceEpoch(row['last_read_at'] as int, isUtc: true),
      );
}
