// Stale-while-revalidate cache for the Receive history screen.
//
// ReceiveSummary is a typedef alias for SaleSummary (same shape).
// Caches ONLY the default-filter first-page fetch. Per-shop key.
// TTL from ConfigKeys.cacheTtlHistoryS (default 300s).

import 'dart:convert';

import 'package:dukan/api/types.dart';
import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';

class ReceiveHistoryCache {
  ReceiveHistoryCache._();

  static const Duration _kDefaultTtl = Duration(minutes: 5);

  static Duration _resolveTtl(ConfigResolver? resolver) {
    if (resolver == null) return _kDefaultTtl;
    final seconds = resolver.resolve(ConfigKeys.cacheTtlHistoryS);
    return Duration(seconds: seconds);
  }

  static String _key(String shopId) => 'receive_history:$shopId';

  static Future<List<ReceiveSummary>?> get(String shopId) async {
    final dao = CacheDao(AppDatabase.instance());
    final entry = await dao.get(_key(shopId));
    if (entry == null) return null;
    try {
      final raw = jsonDecode(entry.valueJson) as List<dynamic>;
      return raw
          .map((r) => ReceiveSummary.fromJson(r as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      await dao.remove(_key(shopId));
      return null;
    }
  }

  static Future<void> put(
    String shopId,
    List<ReceiveSummary> receives, {
    ConfigResolver? resolver,
  }) async {
    try {
      final dao = CacheDao(AppDatabase.instance(), configResolver: resolver);
      final encoded = jsonEncode(receives.map(_toJson).toList());
      await dao.put(_key(shopId), encoded, ttl: _resolveTtl(resolver));
    } catch (_) {
      // Best-effort.
    }
  }

  static Future<void> invalidate(String shopId) async {
    try {
      await CacheDao(AppDatabase.instance()).remove(_key(shopId));
    } catch (_) {
      // Best-effort.
    }
  }

  static Map<String, dynamic> _toJson(ReceiveSummary r) => {
        'txn_id': r.txnId,
        'occurred_at': r.occurredAt.toIso8601String(),
        'posted_at': r.postedAt?.toIso8601String(),
        'party_id': r.partyId,
        'party_name': r.partyName,
        'total_amount': r.totalAmount,
        'paid_amount': r.paidAmount,
        'payment_method_code': r.paymentMethodCode,
        'is_voided': r.isVoided,
        'reversal_txn_id': r.reversalTxnId,
        'voided_at': r.voidedAt?.toIso8601String(),
      };
}
