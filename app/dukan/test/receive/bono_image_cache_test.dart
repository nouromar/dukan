import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/receive/bono_image_cache.dart';
import 'package:dukan/storage/app_database.dart';

import '../shared/test_database.dart';

Uint8List _bytes(int n, int fill) => Uint8List.fromList(List.filled(n, fill));

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await openTestDatabase();
  });

  test('put → bytesFor round-trips; has reflects presence', () async {
    final cache = BonoImageCache(database: Future.value(db));
    await cache.put(
      documentId: 'd1',
      shopId: 's',
      ext: 'jpg',
      bytes: _bytes(10, 7),
    );
    expect(await cache.has('d1'), isTrue);
    expect(await cache.bytesFor('d1'), _bytes(10, 7));
    expect(await cache.has('nope'), isFalse);
    expect(await cache.bytesFor('nope'), isNull);
  });

  test('deleteFor removes the entry', () async {
    final cache = BonoImageCache(database: Future.value(db));
    await cache.put(documentId: 'd1', shopId: 's', ext: 'jpg', bytes: _bytes(10, 1));
    await cache.deleteFor('d1');
    expect(await cache.has('d1'), isFalse);
  });

  test('evictToLimit drops oldest UPLOADED over the cap, keeps pending', () async {
    var now = DateTime(2026, 1, 1, 0, 0, 0);
    final cache = BonoImageCache(
      database: Future.value(db),
      maxBytes: 1000,
      clock: () => now,
    );

    // Two uploaded entries (400 each) + one pending (400) = 1200 > 1000.
    now = DateTime(2026, 1, 1, 0, 0, 0);
    await cache.put(documentId: 'u1', shopId: 's', ext: 'jpg', bytes: _bytes(400, 1));
    await cache.markUploaded('u1');
    now = DateTime(2026, 1, 1, 0, 0, 1);
    await cache.put(documentId: 'u2', shopId: 's', ext: 'jpg', bytes: _bytes(400, 2));
    await cache.markUploaded('u2');
    now = DateTime(2026, 1, 1, 0, 0, 2);
    await cache.put(documentId: 'p1', shopId: 's', ext: 'jpg', bytes: _bytes(400, 3));

    await cache.evictToLimit();

    // Oldest uploaded (u1) evicted → 800 ≤ 1000. u2 kept; pending p1 never evicted.
    expect(await cache.has('u1'), isFalse);
    expect(await cache.has('u2'), isTrue);
    expect(await cache.has('p1'), isTrue);
  });

  test('evictToLimit is a no-op under the cap', () async {
    final cache = BonoImageCache(database: Future.value(db), maxBytes: 1000);
    await cache.put(documentId: 'd1', shopId: 's', ext: 'jpg', bytes: _bytes(100, 1));
    await cache.markUploaded('d1');
    await cache.evictToLimit();
    expect(await cache.has('d1'), isTrue);
  });
}
