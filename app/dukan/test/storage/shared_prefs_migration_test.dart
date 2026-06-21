// One-shot migration tests. Seed SharedPreferences with the legacy
// keys, run the migration, assert the data landed in sqflite + the
// idempotency flag was set + the old keys were cleared.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';
import 'package:dukan/storage/device_config_dao.dart';
import 'package:dukan/storage/pending_post_dao.dart';
import 'package:dukan/storage/shared_prefs_migration.dart';

void main() {
  late PendingPostDao postDao;
  late CacheDao cacheDao;
  late DeviceConfigDao configDao;

  setUp(() {
    postDao = PendingPostDao(AppDatabase.instance());
    cacheDao = CacheDao(AppDatabase.instance());
    configDao = DeviceConfigDao(AppDatabase.instance());
  });

  Future<bool> _runMigration({
    String? actorUserId = 'user-A',
  }) async {
    final migration = SharedPrefsMigration(
      pendingPostDao: postDao,
      cacheDao: cacheDao,
      deviceConfigDao: configDao,
      fallbackOriginalActorUserId: actorUserId,
    );
    return migration.runIfNeeded();
  }

  test('first run: empty legacy state → flag set, no rows written',
      () async {
    final ran = await _runMigration();
    expect(ran, isTrue);
    expect(await configDao.get(kMigrationFlagKey), 'true');
    expect(await postDao.load(), isEmpty);
  });

  test('second run is a no-op (idempotent via flag)', () async {
    await _runMigration();
    // Seed something AFTER the flag was set; second run should ignore it.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'today_summary:shop-x': '{"sales_today":42}',
    });
    final ran = await _runMigration();
    expect(ran, isFalse);
    // Today summary key NOT migrated — flag short-circuited.
    expect(await cacheDao.get('today_summary:shop-x'), isNull);
  });

  test('lifts legacy pending queue into pending_post table', () async {
    final legacy = jsonEncode([
      {
        'id': 'q1',
        'client_op_id': 'op1',
        'shop_id': 'shop-A',
        'rpc': 'post_sale',
        'params': <String, dynamic>{
          'lines': <dynamic>[],
          'paid_amount': 0,
        },
        'queued_at': '2026-06-12T12:00:00.000Z',
      },
    ]);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pending_posts_v1': legacy,
    });
    final ran = await _runMigration();
    expect(ran, isTrue);
    final posts = await postDao.load();
    expect(posts, hasLength(1));
    expect(posts.first.id, 'q1');
    // Legacy entry had no original_actor_user_id; the migration
    // stamps it from the fallback (current signed-in user).
    expect(posts.first.originalActorUserId, 'user-A');
    // Old key cleared.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pending_posts_v1'), isNull);
  });

  test('lifts legacy auth_state and today_summary cache entries', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_state:user-1': '{"shops":[]}',
      'today_summary:shop-A': '{"sales_today":1}',
    });
    await _runMigration();
    expect(await cacheDao.get('auth_state:user-1'), isNotNull);
    expect(await cacheDao.get('today_summary:shop-A'), isNotNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_state:user-1'), isNull);
    expect(prefs.getString('today_summary:shop-A'), isNull);
  });

  test('queue lift is skipped (and flag NOT set) when no fallback user id',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pending_posts_v1': jsonEncode([
        {
          'id': 'q1',
          'client_op_id': 'op1',
          'shop_id': 'shop-A',
          'rpc': 'post_sale',
          'params': <String, dynamic>{},
          'queued_at': '2026-06-12T12:00:00.000Z',
        },
      ]),
    });
    final ran = await _runMigration(actorUserId: null);
    expect(ran, isFalse);
    expect(await configDao.get(kMigrationFlagKey), isNull);
    expect(await postDao.load(), isEmpty);
    // Old key INTACT so the next launch (with a session) can retry.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pending_posts_v1'), isNotNull);
  });
}
