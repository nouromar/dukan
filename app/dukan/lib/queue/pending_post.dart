// One queued posting attempt. Stored durably (sqflite via
// PendingPostDao) so a posted sale survives an app kill mid-flight.
//
// Why durable: cashier hits SAVE on the counter, the immediate post
// fails on a network hiccup, the user backgrounds the app, the post
// is forgotten. The queue retries on its own. Server-enforced
// idempotency via client_op_id ensures duplicate sends are no-ops.

import 'package:flutter/foundation.dart';

/// Lifecycle states a queued post can be in.
///
///   * `pending` — eligible for the next drain cycle.
///   * `failedPermanent` — exhausted retry budget; surfaced in the
///     Storage & sync screen for manual retry or discard. Set in
///     Phase 2 once the cap lands; defined now so the schema is
///     stable.
enum PendingPostState {
  pending,
  failedPermanent,
}

String pendingPostStateToString(PendingPostState s) {
  switch (s) {
    case PendingPostState.pending:
      return 'pending';
    case PendingPostState.failedPermanent:
      return 'failed_permanent';
  }
}

PendingPostState pendingPostStateFromString(String? s) {
  switch (s) {
    case 'failed_permanent':
      return PendingPostState.failedPermanent;
    case 'pending':
    default:
      return PendingPostState.pending;
  }
}

@immutable
class PendingPost {
  const PendingPost({
    required this.id,
    required this.clientOpId,
    required this.shopId,
    required this.originalActorUserId,
    required this.rpc,
    required this.params,
    required this.queuedAt,
    this.schemaVersion = 1,
    this.attempts = 0,
    this.lastAttemptAt,
    this.lastError,
    this.state = PendingPostState.pending,
  });

  /// Local identifier used to de-dupe rows in the queue itself.
  /// Distinct from [clientOpId] — that one travels to the server.
  final String id;

  /// Idempotency key the server uses to short-circuit duplicate
  /// posts (set on each posting RPC's `p_client_op_id`).
  final String clientOpId;

  final String shopId;

  /// `auth.uid()` at enqueue time. Carried so a future audit-stamping
  /// pass (Phase 5) can attribute the post to the user who originally
  /// rang it up, even if a different user is signed in when the
  /// queue actually drains. Stored from day one so the schema is
  /// stable; the executor doesn't read it yet.
  final String originalActorUserId;

  /// Which posting RPC this queued attempt represents.
  /// One of: 'post_sale' | 'post_receive' | 'post_payment' | 'post_expense'.
  final String rpc;

  /// JSON-serialisable parameters. The executor knows how to read
  /// them per RPC.
  final Map<String, dynamic> params;

  /// Schema version of the [params] map. The executor branches on
  /// this so an app upgrade can change the payload shape without
  /// breaking pre-existing queued posts.
  final int schemaVersion;

  final DateTime queuedAt;
  final int attempts;
  final DateTime? lastAttemptAt;
  final String? lastError;
  final PendingPostState state;

  PendingPost copyWith({
    int? attempts,
    DateTime? lastAttemptAt,
    String? lastError,
    PendingPostState? state,
  }) =>
      PendingPost(
        id: id,
        clientOpId: clientOpId,
        shopId: shopId,
        originalActorUserId: originalActorUserId,
        rpc: rpc,
        params: params,
        queuedAt: queuedAt,
        schemaVersion: schemaVersion,
        attempts: attempts ?? this.attempts,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        lastError: lastError ?? this.lastError,
        state: state ?? this.state,
      );

  @override
  String toString() =>
      'PendingPost(id: $id, rpc: $rpc, attempts: $attempts, '
      'state: ${pendingPostStateToString(state)}, '
      'lastError: $lastError)';
}
