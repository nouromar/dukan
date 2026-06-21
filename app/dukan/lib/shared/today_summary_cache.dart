// Stale-while-revalidate cache for the Home Today card.
//
// Before: tapping Home (or returning from a Sale) mounts the Today
// card, fires getTodaySummary, and shows nothing until the RPC
// returns — 300-500ms of empty card every time.
//
// After: read the last known summary from the sqflite cache and
// render it immediately, then refetch in the background and animate
// the diff. The cashier always sees numbers. Cold start to "feels
// alive" drops to the engine boot time.
//
// Per-shop key so a multi-shop owner switching shops doesn't see
// another shop's last summary briefly. TTL applied at the
// CacheDao layer (default 1 hour — values older than that re-fetch
// silently on next read).

import 'dart:async';
import 'dart:convert';

import 'package:dukan/api/types.dart';
import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';

class TodaySummaryCache {
  TodaySummaryCache._();

  /// Hard-coded fallback TTL when no [ConfigResolver] is passed. Phase 3
  /// wired the resolver-fed `cache_ttl_today_summary_s` key; callers in
  /// production pass the resolver from the provider tree.
  static const Duration _kDefaultTtl = Duration(hours: 1);

  static Duration _resolveTtl(ConfigResolver? resolver) {
    if (resolver == null) return _kDefaultTtl;
    final seconds = resolver.resolve(ConfigKeys.cacheTtlTodaySummaryS);
    return Duration(seconds: seconds);
  }

  static String _key(String shopId) => 'today_summary:$shopId';

  /// Returns the last persisted summary for [shopId], or null when
  /// nothing's cached / the entry has expired.
  static Future<TodaySummary?> get(String shopId) async {
    final dao = CacheDao(AppDatabase.instance());
    final entry = await dao.get(_key(shopId));
    if (entry == null) return null;
    try {
      final json = jsonDecode(entry.valueJson) as Map<String, dynamic>;
      return TodaySummary(
        salesToday: (json['sales_today'] as num).toDouble(),
        receivablesTotal: (json['receivables_total'] as num).toDouble(),
        payablesTotal: (json['payables_total'] as num).toDouble(),
        lowStockCount: (json['low_stock_count'] as num).toInt(),
      );
    } catch (_) {
      // Corrupt JSON (shape changed between versions) — drop the row
      // so future reads start fresh.
      await dao.remove(_key(shopId));
      return null;
    }
  }

  /// Persist a fresh summary for [shopId]. Errors are swallowed:
  /// SWR caches are best-effort. Pass [resolver] from the provider
  /// tree so the TTL respects org/shop/device overrides; falls back
  /// to a 1h hard-coded default when null (tests and code paths that
  /// don't have a resolver in scope).
  static Future<void> put(
    String shopId,
    TodaySummary summary, {
    ConfigResolver? resolver,
  }) async {
    try {
      final dao = CacheDao(AppDatabase.instance(), configResolver: resolver);
      final json = <String, dynamic>{
        'sales_today': summary.salesToday,
        'receivables_total': summary.receivablesTotal,
        'payables_total': summary.payablesTotal,
        'low_stock_count': summary.lowStockCount,
      };
      await dao.put(_key(shopId), jsonEncode(json), ttl: _resolveTtl(resolver));
    } catch (_) {
      // Cache writes never block the caller.
    }
  }
}
