import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';

void main() {
  late CacheDao dao;
  late DateTime now;

  setUp(() {
    now = DateTime.utc(2026, 6, 21, 12, 0, 0);
    dao = CacheDao(AppDatabase.instance(), clock: () => now);
  });

  test('get returns null when missing', () async {
    expect(await dao.get('k'), isNull);
  });

  test('put + get round-trips', () async {
    await dao.put('k', '{"x":1}');
    final entry = await dao.get('k');
    expect(entry, isNotNull);
    expect(entry!.valueJson, '{"x":1}');
    expect(entry.sizeBytes, '{"x":1}'.length);
  });

  test('TTL is honoured — expired reads return null + delete the row',
      () async {
    await dao.put('k', 'value', ttl: const Duration(minutes: 1));
    // Fast-forward past expiry.
    now = now.add(const Duration(minutes: 2));
    expect(await dao.get('k'), isNull);
    // Subsequent reads stay empty (row was deleted on the expired get).
    expect(await dao.get('k'), isNull);
  });

  test('get updates last_read_at so LRU sees fresh access', () async {
    final first = DateTime.utc(2026, 6, 21, 12, 0, 0);
    final later = DateTime.utc(2026, 6, 21, 12, 5, 0);
    now = first;
    await dao.put('k', 'v');
    now = later;
    final entry = await dao.get('k');
    expect(entry, isNotNull);
    // Issue another get to confirm the stamp moved.
    final reread = await dao.get('k');
    expect(reread!.lastReadAt, later);
  });

  test('totalBytes sums size_bytes across entries', () async {
    await dao.put('a', '1234');
    await dao.put('b', '12345678');
    expect(await dao.totalBytes(), 4 + 8);
  });

  test('evictExpired removes only expired rows', () async {
    await dao.put('expired', 'v', ttl: const Duration(minutes: 1));
    await dao.put('keep', 'v', ttl: const Duration(hours: 1));
    now = now.add(const Duration(minutes: 2));
    final deleted = await dao.evictExpired();
    expect(deleted, 1);
    expect(await dao.get('expired'), isNull);
    expect(await dao.get('keep'), isNotNull);
  });

  test('evictLruUntil drops oldest reads first', () async {
    now = DateTime.utc(2026, 6, 21, 12, 0, 0);
    await dao.put('old', '0123456789'); // 10 bytes
    now = DateTime.utc(2026, 6, 21, 12, 1, 0);
    await dao.put('mid', '0123456789'); // 10 bytes
    now = DateTime.utc(2026, 6, 21, 12, 2, 0);
    await dao.put('new', '0123456789'); // 10 bytes
    // Budget = 20 → evict 1 entry (the oldest).
    final deleted = await dao.evictLruUntil(20);
    expect(deleted, 1);
    expect(await dao.get('old'), isNull);
    expect(await dao.get('mid'), isNotNull);
    expect(await dao.get('new'), isNotNull);
  });

  test('remove deletes one entry; clear empties the table', () async {
    await dao.put('a', 'v');
    await dao.put('b', 'v');
    await dao.remove('a');
    expect(await dao.get('a'), isNull);
    expect(await dao.get('b'), isNotNull);
    await dao.clear();
    expect(await dao.get('b'), isNull);
  });

  test('stats reports total bytes + entry count', () async {
    expect(await dao.stats(), (totalBytes: 0, entryCount: 0));
    await dao.put('a', '1234');
    await dao.put('b', '12345678');
    expect(await dao.stats(), (totalBytes: 12, entryCount: 2));
  });

  test('put auto-evicts (expired first, then LRU) when over budget',
      () async {
    // Budget of 25 bytes — small enough to force eviction.
    final tight = CacheDao(
      AppDatabase.instance(),
      clock: () => now,
      budgetBytes: 25,
    );
    // Two entries, neither expired.
    now = DateTime.utc(2026, 6, 21, 12, 0, 0);
    await tight.put('oldRead', '0123456789'); // 10
    now = DateTime.utc(2026, 6, 21, 12, 1, 0);
    await tight.put('newRead', '0123456789'); // 10
    // 20 bytes total, under budget — both remain.
    expect(await tight.get('oldRead'), isNotNull);
    // Reading promotes 'oldRead' past 'newRead' in LRU order.
    now = DateTime.utc(2026, 6, 21, 12, 2, 0);
    await tight.get('oldRead');
    // Third put pushes total to 30 — over budget. Eviction runs.
    now = DateTime.utc(2026, 6, 21, 12, 3, 0);
    await tight.put('third', '0123456789'); // 10
    // 'newRead' was the least-recently-read, so it gets evicted.
    expect(await tight.get('newRead'), isNull);
    expect(await tight.get('oldRead'), isNotNull);
    expect(await tight.get('third'), isNotNull);
  });

  test('put evicts expired before touching healthy entries', () async {
    final tight = CacheDao(
      AppDatabase.instance(),
      clock: () => now,
      budgetBytes: 25,
    );
    // Expiring entry.
    await tight.put('willExpire', '0123456789',
        ttl: const Duration(minutes: 1));
    await tight.put('keep', '0123456789');
    // Fast-forward so willExpire is expired.
    now = now.add(const Duration(minutes: 2));
    // Trigger eviction by another put.
    await tight.put('newEntry', '0123456789');
    // Expired one was deleted; both healthy entries remain (we have
    // budget for two 10-byte entries).
    expect(await tight.get('willExpire'), isNull);
    expect(await tight.get('keep'), isNotNull);
    expect(await tight.get('newEntry'), isNotNull);
  });
}
