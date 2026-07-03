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

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// True when [id] is a UUID — i.e. a real server-assigned transaction id,
/// not the `{prefix}-{millis}-{rand}` client_op_id we use as the optimistic
/// placeholder for an offline-posted transaction the server hasn't seen yet.
///
/// Used to gate the VOID affordance: an offline-created transaction can't be
/// voided until it syncs (its placeholder id is neither a UUID nor the id the
/// server will eventually mint — passing it to a void RPC fails 22P02).
bool isServerAssignedId(String id) => _uuidPattern.hasMatch(id);

/// A random v4 UUID, for client-generated row ids that the backend
/// stores in a `uuid` column (e.g. an offline-created category id that
/// must match the server row on sync). Self-contained so we don't pull
/// the transitive `uuid` package into a direct dependency.
String generateUuidV4() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 10xx
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
