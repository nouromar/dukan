// Stale-while-revalidate cache for Customers + Suppliers screens.
//
// Caches ONLY the default-view fetch per typeCode ('customer' /
// 'supplier'). Search-filtered or balance-filtered views skip
// the cache. Each type has its own key so the Customers and
// Suppliers screens don't cross-pollinate.
//
// TTL from ConfigKeys.cacheTtlPartiesS (default 3600s).

import 'dart:convert';

import 'package:dukan/api/types.dart';
import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';

class PartiesCache {
  PartiesCache._();

  static const Duration _kDefaultTtl = Duration(hours: 1);

  static Duration _resolveTtl(ConfigResolver? resolver) {
    if (resolver == null) return _kDefaultTtl;
    final seconds = resolver.resolve(ConfigKeys.cacheTtlPartiesS);
    return Duration(seconds: seconds);
  }

  static String _key(String shopId, String typeCode) =>
      'parties:$shopId:$typeCode';

  /// Last persisted parties list for the given [shopId] + [typeCode]
  /// ('customer' / 'supplier'), or null.
  static Future<List<PartySearchResult>?> get(
    String shopId,
    String typeCode,
  ) async {
    final dao = CacheDao(AppDatabase.instance());
    final entry = await dao.get(_key(shopId, typeCode));
    if (entry == null) return null;
    try {
      final raw = jsonDecode(entry.valueJson) as List<dynamic>;
      return raw
          .map((r) => PartySearchResult.fromJson(r as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      await dao.remove(_key(shopId, typeCode));
      return null;
    }
  }

  static Future<void> put(
    String shopId,
    String typeCode,
    List<PartySearchResult> parties, {
    ConfigResolver? resolver,
  }) async {
    try {
      final dao = CacheDao(AppDatabase.instance(), configResolver: resolver);
      final encoded = jsonEncode(parties.map(_toJson).toList());
      await dao.put(
        _key(shopId, typeCode),
        encoded,
        ttl: _resolveTtl(resolver),
      );
    } catch (_) {
      // Best-effort.
    }
  }

  /// Invalidate both customer + supplier caches for the shop.
  /// Called when we don't know which side moved (e.g. payment
  /// affects both directions).
  static Future<void> invalidateAll(String shopId) async {
    await Future.wait([
      invalidate(shopId, 'customer'),
      invalidate(shopId, 'supplier'),
    ]);
  }

  static Future<void> invalidate(String shopId, String typeCode) async {
    try {
      await CacheDao(AppDatabase.instance()).remove(_key(shopId, typeCode));
    } catch (_) {
      // Best-effort.
    }
  }

  static Map<String, dynamic> _toJson(PartySearchResult p) => {
        'id': p.id,
        'name': p.name,
        'phone': p.phone,
        'type_code': p.typeCode,
        'receivable': p.receivable,
        'payable': p.payable,
      };
}
