// Server-enforced idempotency keys for posting RPCs. The backend uses
// `client_op_id` to dedupe re-tries (see migration 0009: unique index on
// (shop_id, client_op_id)). Format is `{prefix}-{millis}-{rand}` — the
// prefix tags which flow produced it for grep-readability in audit logs.

import 'dart:math' as math;

final _random = math.Random();

/// Returns an idempotency key safe to pass as `client_op_id` to any
/// posting RPC. Use the prefix of the flow that owns the post:
/// `'sale'`, `'receive'`, `'payment'`, `'expense'`.
String generateClientOpId(String prefix) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final r = _random.nextInt(1 << 32);
  return '$prefix-$ts-$r';
}
