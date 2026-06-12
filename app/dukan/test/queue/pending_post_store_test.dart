import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/queue/pending_post_store.dart';

PendingPost _post(String id) => PendingPost(
      id: id,
      clientOpId: 'op-$id',
      shopId: 'shop-1',
      rpc: 'post_sale',
      params: const <String, dynamic>{
        'lines': <dynamic>[],
        'paid_amount': 0,
      },
      queuedAt: DateTime.utc(2026, 6, 12, 12, 0, 0),
    );

void main() {
  late PendingPostStore store;

  setUp(() {
    store = PendingPostStore();
  });

  test('readAll on a fresh store returns empty', () async {
    expect(await store.readAll(), isEmpty);
  });

  test('writeAll then readAll round-trips the posts', () async {
    final posts = [_post('a'), _post('b')];
    await store.writeAll(posts);
    final got = await store.readAll();
    expect(got.map((p) => p.id), ['a', 'b']);
  });

  test('writing an empty list clears the key', () async {
    await store.writeAll([_post('a')]);
    await store.writeAll(<PendingPost>[]);
    final got = await store.readAll();
    expect(got, isEmpty);
  });

  test('clear() empties the queue', () async {
    await store.writeAll([_post('a'), _post('b')]);
    await store.clear();
    expect(await store.readAll(), isEmpty);
  });

  test('corrupt JSON is silently dropped and returns empty', () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'pending_posts_v1': 'not json'},
    );
    expect(await store.readAll(), isEmpty);
    // Subsequent reads also empty -- the corrupt blob was removed.
    expect(await store.readAll(), isEmpty);
  });
}
