// One queued posting attempt. Captured durably (SharedPreferences via
// PendingPostStore) so a posted sale survives an app kill mid-flight.
//
// Why durable: cashier hits SAVE on the counter, the immediate post
// fails on a network hiccup, the user backgrounds the app, the post
// is forgotten. The queue retries on its own. Server-enforced
// idempotency via client_op_id ensures duplicate sends are no-ops.

import 'package:flutter/foundation.dart';

@immutable
class PendingPost {
  const PendingPost({
    required this.id,
    required this.clientOpId,
    required this.shopId,
    required this.rpc,
    required this.params,
    required this.queuedAt,
    this.attempts = 0,
    this.lastAttemptAt,
    this.lastError,
  });

  factory PendingPost.fromJson(Map<String, dynamic> json) => PendingPost(
        id: json['id'] as String,
        clientOpId: json['client_op_id'] as String,
        shopId: json['shop_id'] as String,
        rpc: json['rpc'] as String,
        params: Map<String, dynamic>.from(json['params'] as Map),
        queuedAt: DateTime.parse(json['queued_at'] as String),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastAttemptAt: json['last_attempt_at'] == null
            ? null
            : DateTime.parse(json['last_attempt_at'] as String),
        lastError: json['last_error'] as String?,
      );

  /// Local identifier used to de-dupe rows in the queue itself.
  /// Distinct from [clientOpId] — that one travels to the server.
  final String id;

  /// Idempotency key the server uses to short-circuit duplicate
  /// posts (set on each posting RPC's `p_client_op_id`).
  final String clientOpId;

  final String shopId;

  /// Which posting RPC this queued attempt represents.
  /// One of: 'post_sale' | 'post_receive' | 'post_payment' | 'post_expense'.
  final String rpc;

  /// JSON-serialisable parameters. The executor knows how to read
  /// them per RPC.
  final Map<String, dynamic> params;

  final DateTime queuedAt;
  final int attempts;
  final DateTime? lastAttemptAt;
  final String? lastError;

  Map<String, dynamic> toJson() => {
        'id': id,
        'client_op_id': clientOpId,
        'shop_id': shopId,
        'rpc': rpc,
        'params': params,
        'queued_at': queuedAt.toIso8601String(),
        'attempts': attempts,
        if (lastAttemptAt != null)
          'last_attempt_at': lastAttemptAt!.toIso8601String(),
        if (lastError != null) 'last_error': lastError,
      };

  PendingPost copyWith({
    int? attempts,
    DateTime? lastAttemptAt,
    String? lastError,
  }) =>
      PendingPost(
        id: id,
        clientOpId: clientOpId,
        shopId: shopId,
        rpc: rpc,
        params: params,
        queuedAt: queuedAt,
        attempts: attempts ?? this.attempts,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        lastError: lastError ?? this.lastError,
      );

  @override
  String toString() =>
      'PendingPost(id: $id, rpc: $rpc, attempts: $attempts, '
      'lastError: $lastError)';
}
