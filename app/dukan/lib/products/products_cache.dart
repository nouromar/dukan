// Stale-while-revalidate cache for the Products screen.
//
// Caches ONLY the default-view fetch (no search query, no
// category filter). When the cashier opens Products, the list
// paints instantly from disk; a fresh fetch fires in the
// background and the list updates when it lands. Filtered /
// searched views skip the cache (per-query keys would balloon).
//
// Per-shop key. TTL from ConfigKeys.cacheTtlProductsS (default
// 1800s) — applied at the CacheDao layer.

import 'dart:convert';

import 'package:dukan/api/types.dart';
import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';

class ProductsCache {
  ProductsCache._();

  static const Duration _kDefaultTtl = Duration(minutes: 30);

  static Duration _resolveTtl(ConfigResolver? resolver) {
    if (resolver == null) return _kDefaultTtl;
    final seconds = resolver.resolve(ConfigKeys.cacheTtlProductsS);
    return Duration(seconds: seconds);
  }

  static String _key(String shopId) => 'products:$shopId';

  /// Last persisted product list, or null when nothing's cached /
  /// the entry expired.
  static Future<List<ShopItemSummary>?> get(String shopId) async {
    final dao = CacheDao(AppDatabase.instance());
    final entry = await dao.get(_key(shopId));
    if (entry == null) return null;
    try {
      final raw = jsonDecode(entry.valueJson) as List<dynamic>;
      return raw
          .map((r) => ShopItemSummary.fromJson(r as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      await dao.remove(_key(shopId));
      return null;
    }
  }

  /// Persist a fresh product list. Errors swallowed — SWR caches
  /// are best-effort.
  static Future<void> put(
    String shopId,
    List<ShopItemSummary> items, {
    ConfigResolver? resolver,
  }) async {
    try {
      final dao = CacheDao(AppDatabase.instance(), configResolver: resolver);
      final encoded = jsonEncode(items.map(_toJson).toList());
      await dao.put(_key(shopId), encoded, ttl: _resolveTtl(resolver));
    } catch (_) {
      // Never block the caller.
    }
  }

  /// Drop the cached entry for [shopId]. Called from posting flows
  /// after a successful save invalidates the cached list.
  static Future<void> invalidate(String shopId) async {
    try {
      await CacheDao(AppDatabase.instance()).remove(_key(shopId));
    } catch (_) {
      // Best-effort.
    }
  }

  /// Mirror of ShopItemSummary.fromJson — keeps the toJson local
  /// to the cache so we don't pollute the DTO with serialization
  /// it doesn't otherwise need.
  static Map<String, dynamic> _toJson(ShopItemSummary s) => {
        'shop_item_id': s.shopItemId,
        'item_id': s.itemId,
        'display_name': s.displayName,
        'category_name': s.categoryName,
        'base_unit_code': s.baseUnitCode,
        'base_unit_label': s.baseUnitLabel,
        'current_stock': s.currentStock,
        'reorder_threshold': s.reorderThreshold,
        'unit_count': s.unitCount,
        'is_active': s.isActive,
        'default_sale_price': s.defaultSalePrice,
        'any_price_set': s.anyPriceSet,
      };
}
