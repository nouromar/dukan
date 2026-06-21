// Row-level DAO tests. The flutter_test_config setUp seeds a fresh
// in-memory AppDatabase per test, so we just construct the DAO
// against the singleton.

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/pending_post_dao.dart';

PendingPost _post(
  String id, {
  int attempts = 0,
  PendingPostState state = PendingPostState.pending,
  String? lastError,
  DateTime? queuedAt,
}) {
  return PendingPost(
    id: id,
    clientOpId: 'op-$id',
    shopId: 'shop-1',
    originalActorUserId: 'user-A',
    rpc: 'post_sale',
    params: <String, dynamic>{
      'lines': <Map<String, dynamic>>[
        {'shop_item_unit_id': 'siu-rice', 'quantity': 1, 'unit_price': 1.5},
      ],
      'paid_amount': 1.5,
    },
    queuedAt: queuedAt ?? DateTime.utc(2026, 6, 12, 12, 0, 0),
    attempts: attempts,
    lastError: lastError,
    state: state,
  );
}

void main() {
  late PendingPostDao dao;

  setUp(() {
    dao = PendingPostDao(AppDatabase.instance());
  });

  test('load returns empty on a fresh DB', () async {
    expect(await dao.load(), isEmpty);
  });

  test('insert + load round-trips a post', () async {
    await dao.insert(_post('a'));
    final got = await dao.load();
    expect(got, hasLength(1));
    expect(got.first.id, 'a');
    expect(got.first.clientOpId, 'op-a');
    expect(got.first.originalActorUserId, 'user-A');
    expect(got.first.params['paid_amount'], 1.5);
  });

  test('load orders by queued_at ASC', () async {
    await dao.insert(
      _post('b', queuedAt: DateTime.utc(2026, 6, 12, 12, 2, 0)),
    );
    await dao.insert(
      _post('a', queuedAt: DateTime.utc(2026, 6, 12, 12, 1, 0)),
    );
    final got = await dao.load();
    expect(got.map((p) => p.id), ['a', 'b']);
  });

  test('load excludes failed_permanent rows', () async {
    await dao.insert(_post('a'));
    await dao.insert(_post('b', state: PendingPostState.failedPermanent));
    final pending = await dao.load();
    expect(pending.map((p) => p.id), ['a']);
    final failed = await dao.loadFailedPermanent();
    expect(failed.map((p) => p.id), ['b']);
  });

  test('insert with duplicate (shop_id, client_op_id) throws', () async {
    await dao.insert(_post('a'));
    await expectLater(
      dao.insert(_post('a')),
      throwsA(isA<Object>()),
    );
  });

  test('updateAttempts bumps + records error', () async {
    await dao.insert(_post('a'));
    await dao.updateAttempts(
      id: 'a',
      attempts: 2,
      lastAttemptAt: DateTime.utc(2026, 6, 12, 12, 5, 0),
      lastError: 'connection reset',
    );
    final got = await dao.load();
    expect(got.first.attempts, 2);
    expect(got.first.lastError, 'connection reset');
    expect(
      got.first.lastAttemptAt,
      DateTime.utc(2026, 6, 12, 12, 5, 0),
    );
  });

  test('markFailedPermanent moves the row off the pending list', () async {
    await dao.insert(_post('a'));
    await dao.markFailedPermanent('a');
    expect(await dao.load(), isEmpty);
    final failed = await dao.loadFailedPermanent();
    expect(failed.map((p) => p.id), ['a']);
    expect(failed.first.state, PendingPostState.failedPermanent);
  });

  test('resetToPending puts the row back + zeroes attempts', () async {
    await dao.insert(_post('a', attempts: 7, lastError: 'boom'));
    await dao.markFailedPermanent('a');
    await dao.resetToPending('a');
    final got = await dao.load();
    expect(got, hasLength(1));
    expect(got.first.attempts, 0);
    expect(got.first.lastError, isNull);
    expect(got.first.state, PendingPostState.pending);
  });

  test('remove deletes one row by id', () async {
    await dao.insert(_post('a'));
    await dao.insert(_post('b'));
    await dao.remove('a');
    final got = await dao.load();
    expect(got.map((p) => p.id), ['b']);
  });

  test('save bulk-replaces the table', () async {
    await dao.insert(_post('stale'));
    await dao.save([_post('a'), _post('b')]);
    final got = await dao.load();
    expect(got.map((p) => p.id), ['a', 'b']);
  });

  test('countPending excludes failed rows', () async {
    await dao.insert(_post('a'));
    await dao.insert(_post('b', state: PendingPostState.failedPermanent));
    expect(await dao.countPending(), 1);
  });

  test('clear empties the table entirely', () async {
    await dao.insert(_post('a'));
    await dao.insert(_post('b', state: PendingPostState.failedPermanent));
    await dao.clear();
    expect(await dao.load(), isEmpty);
    expect(await dao.loadFailedPermanent(), isEmpty);
  });
}
