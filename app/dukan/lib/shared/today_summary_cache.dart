// Stale-while-revalidate cache for the Home Today card.
//
// Before: tapping Home (or returning from a Sale) mounts the Today
// card, fires getTodaySummary, and shows nothing until the RPC
// returns — 300-500ms of empty card every time.
//
// After: read the last known summary from SharedPreferences and
// render it immediately, then refetch in the background and animate
// the diff. The cashier always sees numbers. Cold start to "feels
// alive" drops to the engine boot time.
//
// Persisted because cold starts are common in real shops (battery
// saver, app kills). Per-shop key so a multi-shop owner switching
// shops doesn't see another shop's last summary briefly.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:dukan/api/types.dart';

class TodaySummaryCache {
  TodaySummaryCache._();

  static String _key(String shopId) => 'today_summary:$shopId';

  /// Returns the last persisted summary for [shopId], or null when
  /// nothing's been cached.
  static Future<TodaySummary?> get(String shopId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(shopId));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return TodaySummary(
        salesToday: (json['sales_today'] as num).toDouble(),
        receivablesTotal: (json['receivables_total'] as num).toDouble(),
        payablesTotal: (json['payables_total'] as num).toDouble(),
        lowStockCount: (json['low_stock_count'] as num).toInt(),
      );
    } catch (_) {
      // Stored value is corrupt or from a previous schema — drop it.
      await prefs.remove(_key(shopId));
      return null;
    }
  }

  /// Persist a fresh summary for [shopId]. Errors are swallowed:
  /// SWR caches are best-effort.
  static Future<void> put(String shopId, TodaySummary summary) async {
    final prefs = await SharedPreferences.getInstance();
    final json = <String, dynamic>{
      'sales_today': summary.salesToday,
      'receivables_total': summary.receivablesTotal,
      'payables_total': summary.payablesTotal,
      'low_stock_count': summary.lowStockCount,
    };
    await prefs.setString(_key(shopId), jsonEncode(json));
  }
}
