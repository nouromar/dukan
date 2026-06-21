// Simple key/value store for device-local configuration. The
// hierarchical config layer (Phase 3) reads from here as the LAST
// override in its resolution chain (defaults → org → shop → device).
//
// Phase 1 uses this for the one-shot SharedPreferences migration
// flag (`migrated_from_shared_prefs_v1`). Future phases will store
// user-toggleable overrides like "Sync only on Wi-Fi" here.

import 'package:sqflite/sqflite.dart';

import 'package:dukan/storage/app_database.dart';

class DeviceConfigDao {
  DeviceConfigDao(this._database, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// Future-typed so the DAO can be constructed synchronously while
  /// sqflite finishes opening. main.dart awaits the open before
  /// runApp, so methods resolve instantly in practice.
  final Future<AppDatabase> _database;
  final DateTime Function() _clock;

  Future<Database> get _db => _database.then((d) => d.db);

  /// Returns the value for [key] or null when missing.
  Future<String?> get(String key) async {
    final rows = await (await _db).query(
      'device_config',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// Insert or replace.
  Future<void> set(String key, String value) async {
    await (await _db).insert(
      'device_config',
      {
        'key': key,
        'value': value,
        'set_at': _clock().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Drop the row at [key]. No-op when missing.
  Future<void> remove(String key) async {
    await (await _db).delete('device_config', where: 'key = ?', whereArgs: [key]);
  }

  /// Snapshot of every key/value pair. Used by the config resolver
  /// (Phase 3) to populate its device-override layer in one query.
  Future<Map<String, String>> loadAll() async {
    final rows = await (await _db).query('device_config');
    return {
      for (final r in rows) (r['key'] as String): (r['value'] as String),
    };
  }

  /// Wipe the table. Test-only.
  Future<void> clear() async {
    await (await _db).delete('device_config');
  }
}
