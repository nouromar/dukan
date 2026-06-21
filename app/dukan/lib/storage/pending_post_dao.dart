// Row-level access to the `pending_post` sqflite table. Replaces the
// SharedPreferences-backed PendingPostStore which had to rewrite the
// entire JSON blob on every mutation; this DAO inserts/deletes
// individual rows.
//
// Public API kept compatible with the old store (`load`, `save`,
// `clear`) plus row-level methods (`insert`, `remove`,
// `updateAttempts`, `markFailedPermanent`) so the
// OfflineQueueController can swap rewrite-all calls for targeted
// updates without changing its drain logic shape.

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/storage/app_database.dart';

class PendingPostDao {
  PendingPostDao(this._database);

  /// Held as a Future so callers can construct the DAO synchronously
  /// while the underlying sqflite open is still in flight. main.dart
  /// kicks off the open before runApp, so by the time a DAO method
  /// actually executes the future has long since resolved.
  final Future<AppDatabase> _database;

  Future<Database> get _db => _database.then((d) => d.db);

  /// All `pending`-state rows ordered by `queued_at` (oldest first).
  /// `failed_permanent` rows are EXCLUDED — they're surfaced via the
  /// separate [loadFailedPermanent] method so the drain loop never
  /// re-attempts them.
  Future<List<PendingPost>> load() async {
    final rows = await (await _db).query(
      'pending_post',
      where: 'state = ?',
      whereArgs: ['pending'],
      orderBy: 'queued_at ASC',
    );
    return rows.map(_rowToPost).toList(growable: false);
  }

  /// Rows in the `failed_permanent` state. Used by the (Phase 4)
  /// Storage & sync screen to expose manual retry / discard.
  Future<List<PendingPost>> loadFailedPermanent() async {
    final rows = await (await _db).query(
      'pending_post',
      where: 'state = ?',
      whereArgs: ['failed_permanent'],
      orderBy: 'queued_at ASC',
    );
    return rows.map(_rowToPost).toList(growable: false);
  }

  /// Insert a freshly-queued post. The (shop_id, client_op_id)
  /// uniqueness index will reject a second insert with the same
  /// client_op_id — that's the local-side mirror of the server's
  /// idempotency guarantee.
  Future<void> insert(PendingPost post) async {
    await (await _db).insert(
      'pending_post',
      _postToRow(post),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Bumps `attempts`, stamps `last_attempt_at`, records `last_error`.
  /// Called on every failed drain attempt.
  Future<void> updateAttempts({
    required String id,
    required int attempts,
    required DateTime lastAttemptAt,
    String? lastError,
  }) async {
    await (await _db).update(
      'pending_post',
      {
        'attempts': attempts,
        'last_attempt_at': lastAttemptAt.millisecondsSinceEpoch,
        'last_error': lastError,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Move a post to the terminal `failed_permanent` state. The
  /// drain loop stops retrying once a post hits this; the user can
  /// manually retry from the Storage & sync screen (Phase 4) which
  /// resets the state back to `pending`.
  Future<void> markFailedPermanent(String id) async {
    await (await _db).update(
      'pending_post',
      {'state': 'failed_permanent'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Reset a `failed_permanent` post back to `pending` so the next
  /// drain cycle re-attempts it. Resets the attempts counter and
  /// clears `last_error`.
  Future<void> resetToPending(String id) async {
    await (await _db).update(
      'pending_post',
      {
        'state': 'pending',
        'attempts': 0,
        'last_attempt_at': null,
        'last_error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Drop one row by [id]. Called when the post is successfully
  /// drained.
  Future<void> remove(String id) async {
    await (await _db).delete('pending_post', where: 'id = ?', whereArgs: [id]);
  }

  /// Empty the table. Test-only / sign-out wipe path. (Production
  /// sign-out does NOT call this — pending posts are preserved
  /// across sessions; see the §"sign-out flow" notes in the plan.)
  Future<void> clear() async {
    await (await _db).delete('pending_post');
  }

  /// Count of `pending`-state rows. Used by the queue size cap.
  Future<int> countPending() async {
    final row = await (await _db).rawQuery(
      "SELECT COUNT(*) AS c FROM pending_post WHERE state = 'pending'",
    );
    return (row.first['c'] as int?) ?? 0;
  }

  /// Drop the single oldest `pending` row (by `queued_at`) and
  /// return it so the caller can log the dropped payload to Sentry
  /// before it vanishes. Returns null if no `pending` rows exist
  /// (caller would not have called this in that case, but be safe).
  ///
  /// Used by the Phase 2 size cap when [insert] would push the
  /// queue past [kQueueMaxPending].
  Future<PendingPost?> dropOldestPending() async {
    final db = await _db;
    final rows = await db.query(
      'pending_post',
      where: 'state = ?',
      whereArgs: ['pending'],
      orderBy: 'queued_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final victim = _rowToPost(rows.first);
    await db.delete(
      'pending_post',
      where: 'id = ?',
      whereArgs: [victim.id],
    );
    return victim;
  }

  /// Bulk overwrite of the queue contents. Wraps the writes in a
  /// transaction so the table is never observed half-populated.
  /// Primarily used by the one-shot SharedPreferences migration —
  /// production code path uses [insert] / [remove] per row.
  Future<void> save(List<PendingPost> posts) async {
    await (await _db).transaction((txn) async {
      await txn.delete('pending_post');
      for (final post in posts) {
        await txn.insert(
          'pending_post',
          _postToRow(post),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Serialization helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _postToRow(PendingPost post) => <String, dynamic>{
        'id': post.id,
        'client_op_id': post.clientOpId,
        'shop_id': post.shopId,
        'original_actor_user_id': post.originalActorUserId,
        'rpc': post.rpc,
        'schema_version': post.schemaVersion,
        'params_json': jsonEncode(post.params),
        'queued_at': post.queuedAt.millisecondsSinceEpoch,
        'attempts': post.attempts,
        'last_attempt_at': post.lastAttemptAt?.millisecondsSinceEpoch,
        'last_error': post.lastError,
        'state': pendingPostStateToString(post.state),
      };

  PendingPost _rowToPost(Map<String, dynamic> row) {
    // params_json corruption is treated as an empty map rather than
    // crashing the queue. Corrupt rows should be rare (we wrote them
    // ourselves) and dropping the params means the executor will
    // throw a "missing required param" error which surfaces in
    // last_error — visible signal vs. silent loss.
    Map<String, dynamic> params = const <String, dynamic>{};
    try {
      params = Map<String, dynamic>.from(
        jsonDecode(row['params_json'] as String) as Map,
      );
    } catch (_) {
      params = const <String, dynamic>{};
    }
    return PendingPost(
      id: row['id'] as String,
      clientOpId: row['client_op_id'] as String,
      shopId: row['shop_id'] as String,
      originalActorUserId: row['original_actor_user_id'] as String,
      rpc: row['rpc'] as String,
      schemaVersion: (row['schema_version'] as int?) ?? 1,
      params: params,
      queuedAt: DateTime.fromMillisecondsSinceEpoch(row['queued_at'] as int, isUtc: true),
      attempts: (row['attempts'] as int?) ?? 0,
      lastAttemptAt: row['last_attempt_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['last_attempt_at'] as int, isUtc: true),
      lastError: row['last_error'] as String?,
      state: pendingPostStateFromString(row['state'] as String?),
    );
  }
}
