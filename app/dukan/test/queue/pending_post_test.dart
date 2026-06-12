import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/queue/pending_post.dart';

PendingPost _post({String id = 'p1', int attempts = 0, String? lastError}) {
  return PendingPost(
    id: id,
    clientOpId: 'op-$id',
    shopId: 'shop-1',
    rpc: 'post_sale',
    params: <String, dynamic>{
      'lines': [
        {
          'shop_item_unit_id': 'siu-rice',
          'quantity': 1,
          'unit_price': 1.5,
        }
      ],
      'paid_amount': 1.5,
    },
    queuedAt: DateTime.utc(2026, 6, 12, 12, 0, 0),
    attempts: attempts,
    lastAttemptAt: attempts == 0 ? null : DateTime.utc(2026, 6, 12, 12, 1, 0),
    lastError: lastError,
  );
}

void main() {
  test('toJson round-trips through fromJson', () {
    final original = _post(id: 'a', attempts: 2, lastError: 'boom');
    final restored = PendingPost.fromJson(original.toJson());
    expect(restored.id, original.id);
    expect(restored.clientOpId, original.clientOpId);
    expect(restored.shopId, original.shopId);
    expect(restored.rpc, original.rpc);
    expect(restored.params['paid_amount'], 1.5);
    expect(restored.queuedAt, original.queuedAt);
    expect(restored.attempts, 2);
    expect(restored.lastAttemptAt, original.lastAttemptAt);
    expect(restored.lastError, 'boom');
  });

  test('toJson omits null optional fields', () {
    final p = _post();
    final j = p.toJson();
    expect(j.containsKey('last_attempt_at'), isFalse);
    expect(j.containsKey('last_error'), isFalse);
  });

  test('copyWith bumps the attempt counter without changing identity', () {
    final p = _post();
    final next = p.copyWith(
      attempts: p.attempts + 1,
      lastAttemptAt: DateTime.utc(2026, 6, 12, 12, 5, 0),
      lastError: 'network down',
    );
    expect(next.id, p.id);
    expect(next.clientOpId, p.clientOpId);
    expect(next.attempts, 1);
    expect(next.lastError, 'network down');
    expect(next.queuedAt, p.queuedAt);
  });
}
