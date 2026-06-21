// Stale-while-revalidate cache for the Sale history screen.
//
// Caches ONLY the default-filter first-page fetch (no party
// filter, default date range, hideVoided default). Filtered views
// skip the cache — there are too many combinations to key
// usefully.
//
// Per-shop key. TTL from ConfigKeys.cacheTtlHistoryS (default
// 300s — history goes stale fast as new sales come in).

import 'dart:convert';

import 'package:dukan/api/types.dart';
import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';

class SaleHistoryCache {
  SaleHistoryCache._();

  static const Duration _kDefaultTtl = Duration(minutes: 5);

  static Duration _resolveTtl(ConfigResolver? resolver) {
    if (resolver == null) return _kDefaultTtl;
    final seconds = resolver.resolve(ConfigKeys.cacheTtlHistoryS);
    return Duration(seconds: seconds);
  }

  static String _key(String shopId) => 'sale_history:$shopId';

  static Future<List<SaleSummary>?> get(String shopId) async {
    final dao = CacheDao(AppDatabase.instance());
    final entry = await dao.get(_key(shopId));
    if (entry == null) return null;
    try {
      final raw = jsonDecode(entry.valueJson) as List<dynamic>;
      return raw
          .map((r) => SaleSummary.fromJson(r as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      await dao.remove(_key(shopId));
      return null;
    }
  }

  static Future<void> put(
    String shopId,
    List<SaleSummary> sales, {
    ConfigResolver? resolver,
  }) async {
    try {
      final dao = CacheDao(AppDatabase.instance(), configResolver: resolver);
      final encoded = jsonEncode(sales.map(_toJson).toList());
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

  static Map<String, dynamic> _toJson(SaleSummary s) => {
        'txn_id': s.txnId,
        'occurred_at': s.occurredAt.toIso8601String(),
        'posted_at': s.postedAt?.toIso8601String(),
        'party_id': s.partyId,
        'party_name': s.partyName,
        'total_amount': s.totalAmount,
        'paid_amount': s.paidAmount,
        'payment_method_code': s.paymentMethodCode,
        'is_voided': s.isVoided,
        'reversal_txn_id': s.reversalTxnId,
        'voided_at': s.voidedAt?.toIso8601String(),
      };
}
