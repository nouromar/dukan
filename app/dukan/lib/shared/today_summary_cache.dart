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
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';

class TodaySummaryCache {
  TodaySummaryCache._();

  /// Default freshness window. Phase 3 wires this to the hierarchical
  /// `cache_ttl_today_summary_s` config key; for now it's a hard-
  /// coded 1 hour.
  static const Duration _kDefaultTtl = Duration(hours: 1);

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
  /// SWR caches are best-effort.
  static Future<void> put(String shopId, TodaySummary summary) async {
    try {
      final dao = CacheDao(AppDatabase.instance());
      final json = <String, dynamic>{
        'sales_today': summary.salesToday,
        'receivables_total': summary.receivablesTotal,
        'payables_total': summary.payablesTotal,
        'low_stock_count': summary.lowStockCount,
      };
      await dao.put(_key(shopId), jsonEncode(json), ttl: _kDefaultTtl);
    } catch (_) {
      // Cache writes never block the caller.
    }
  }
}
