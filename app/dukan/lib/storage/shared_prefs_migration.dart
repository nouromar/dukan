// One-shot migration that lifts the legacy SharedPreferences-backed
// state (queue + caches) into the sqflite database. Runs at app
// bootstrap before any consumer touches its DAO.
//
// Idempotency: the device_config row `migrated_from_shared_prefs_v1`
// flips to `'true'` on completion; subsequent launches see the flag
// and skip the migration entirely. The flag is written ONLY after
// the sqlite writes succeed and only after we've successfully
// removed the old keys — so a mid-migration crash retries on next
// launch with the old keys still intact.
//
// Failure handling: any thrown exception cancels the migration. We
// log to Sentry via the injected reporter callback and leave the
// SharedPreferences keys in place; the next launch retries. We do
// NOT mark the migration as done, so partial writes can be
// re-attempted (sqlite writes use replace semantics so re-running is
// safe).

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/storage/cache_dao.dart';
import 'package:dukan/storage/device_config_dao.dart';
import 'package:dukan/storage/pending_post_dao.dart';

const String kMigrationFlagKey = 'migrated_from_shared_prefs_v1';
const String _legacyQueueKey = 'pending_posts_v1';
const String _legacyAuthStatePrefix = 'auth_state:';
const String _legacyTodaySummaryPrefix = 'today_summary:';

/// Default TTL we stamp on legacy cache entries during the lift —
/// matches the Phase 3 `cache_ttl_today_summary_s` default (1 hour).
/// AuthState cache uses the same value; the previous implementation
/// had no TTL, so anything older than this will silently re-fetch
/// on first read post-migration.
const Duration _kLegacyCacheTtl = Duration(hours: 1);

typedef MigrationErrorReporter = void Function(
  Object error,
  StackTrace stackTrace,
  String context,
);

class SharedPrefsMigration {
  SharedPrefsMigration({
    required this.pendingPostDao,
    required this.cacheDao,
    required this.deviceConfigDao,
    required this.fallbackOriginalActorUserId,
    this.reportError,
  });

  final PendingPostDao pendingPostDao;
  final CacheDao cacheDao;
  final DeviceConfigDao deviceConfigDao;

  /// User id stamped on legacy queue entries that pre-date the
  /// `original_actor_user_id` column. Use the currently-signed-in
  /// user — they're the most likely person to have queued the posts.
  /// May be null when no session exists at bootstrap; in that case
  /// the migration is skipped (the legacy posts will be migrated
  /// when the user signs in).
  final String? fallbackOriginalActorUserId;

  final MigrationErrorReporter? reportError;

  /// Run the migration if it hasn't already. Returns `true` if the
  /// migration ran on this call, `false` if it was already done OR
  /// skipped (e.g. no current user to attribute legacy posts to).
  Future<bool> runIfNeeded() async {
    try {
      final alreadyDone = await deviceConfigDao.get(kMigrationFlagKey);
      if (alreadyDone == 'true') return false;

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      // Gather the legacy values BEFORE touching sqlite. If sqlite
      // writes fail, the SharedPreferences keys stay intact for the
      // next attempt.
      final legacyQueueRaw = prefs.getString(_legacyQueueKey);
      final legacyAuthStateKeys = keys
          .where((k) => k.startsWith(_legacyAuthStatePrefix))
          .toList(growable: false);
      final legacyTodayKeys = keys
          .where((k) => k.startsWith(_legacyTodaySummaryPrefix))
          .toList(growable: false);

      final nothingToMigrate = legacyQueueRaw == null &&
          legacyAuthStateKeys.isEmpty &&
          legacyTodayKeys.isEmpty;

      // No data → still mark the flag so we don't re-check on every
      // future launch.
      if (nothingToMigrate) {
        await deviceConfigDao.set(kMigrationFlagKey, 'true');
        return true;
      }

      // Queue lift requires a fallback user id to stamp on legacy
      // posts. Skip until a session exists; next launch retries.
      final actorId = fallbackOriginalActorUserId;
      if (legacyQueueRaw != null && actorId == null) {
        return false;
      }

      // Sqlite writes — any failure aborts before we delete the
      // legacy keys.
      if (legacyQueueRaw != null) {
        final posts = _parseLegacyQueue(
          legacyQueueRaw,
          fallbackActorUserId: actorId!,
        );
        if (posts.isNotEmpty) {
          await pendingPostDao.save(posts);
        }
      }

      for (final key in legacyAuthStateKeys) {
        final value = prefs.getString(key);
        if (value == null) continue;
        await cacheDao.put(key, value, ttl: _kLegacyCacheTtl);
      }
      for (final key in legacyTodayKeys) {
        final value = prefs.getString(key);
        if (value == null) continue;
        await cacheDao.put(key, value, ttl: _kLegacyCacheTtl);
      }

      // Sqlite writes confirmed — now safe to delete the legacy
      // keys + set the flag.
      if (legacyQueueRaw != null) {
        await prefs.remove(_legacyQueueKey);
      }
      for (final key in legacyAuthStateKeys) {
        await prefs.remove(key);
      }
      for (final key in legacyTodayKeys) {
        await prefs.remove(key);
      }
      await deviceConfigDao.set(kMigrationFlagKey, 'true');
      return true;
    } catch (error, stackTrace) {
      reportError?.call(error, stackTrace, 'shared_prefs_migration');
      return false;
    }
  }

  List<PendingPost> _parseLegacyQueue(
    String raw, {
    required String fallbackActorUserId,
  }) {
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((m) {
            final json = Map<String, dynamic>.from(m);
            return PendingPost(
              id: json['id'] as String,
              clientOpId: json['client_op_id'] as String,
              shopId: json['shop_id'] as String,
              // Legacy entries don't carry this. Stamp with the
              // current user — they're the one who almost certainly
              // queued the post.
              originalActorUserId:
                  json['original_actor_user_id'] as String? ??
                      fallbackActorUserId,
              rpc: json['rpc'] as String,
              params: Map<String, dynamic>.from(json['params'] as Map),
              queuedAt: DateTime.parse(json['queued_at'] as String),
              attempts: (json['attempts'] as num?)?.toInt() ?? 0,
              lastAttemptAt: json['last_attempt_at'] == null
                  ? null
                  : DateTime.parse(json['last_attempt_at'] as String),
              lastError: json['last_error'] as String?,
            );
          })
          .toList(growable: false);
    } catch (_) {
      // A corrupt legacy blob is dropped (same behaviour as the old
      // store) — we'd rather lose unparseable posts than crash the
      // migration.
      return const <PendingPost>[];
    }
  }
}
