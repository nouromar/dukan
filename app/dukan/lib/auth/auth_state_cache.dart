// Stale-while-revalidate cache for the auth bootstrap layer.
//
// On a real iPhone 14 / hosted Supabase, the chain
//   Sentry init → Supabase init → claim_pending_invites → loadShops
// gates HomeScreen for ~2–3 seconds. This cache shortcuts the last
// two by letting AuthController paint the cached shop list + selected
// shop synchronously, so AuthRouter mounts HomeScreen on the next
// frame. The source of truth (loadShops) still runs unawaited and
// reconciles state when it returns.
//
// Mirrors the shape of lib/shared/today_summary_cache.dart — same
// sqflite-backed SWR, per-user key so accounts on the same device
// don't see each other's shops, swallowing on schema-mismatch
// (drop + return null so the cold path runs).
//
// Sign-out clears the cache for the signed-out user.

import 'dart:convert';

import 'package:dukan/api/types.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';

/// What's persisted: the shop list and the user's last-selected shop
/// id. Currency symbols ride along so `ShopSummary.fromJson` can
/// reconstitute the per-shop `currencySymbol` field without a
/// re-fetch of the currency reference table on read.
class CachedAuthState {
  const CachedAuthState({
    required this.shops,
    required this.currencySymbols,
    this.selectedShopId,
  });

  final List<ShopSummary> shops;
  final Map<String, String> currencySymbols;
  final String? selectedShopId;
}

class AuthStateCache {
  AuthStateCache._();

  /// The warm-paint entry must survive long enough that a cold start
  /// after the OS kills an idle app still paints Home instantly instead
  /// of blocking on loadShops. The old 1h TTL expired in lockstep with
  /// the ~1h Supabase JWT, so any reopen after ~an hour missed the cache
  /// AND hit an expired token → the "spinner after a couple hours" bug.
  ///
  /// Staleness is bounded by the background revalidation in
  /// AuthController.start()/loadShops (which replaces the shop list and
  /// re-checks access — a deactivated/removed user is still routed out
  /// within a second or two), NOT by this TTL. So a long backstop is
  /// safe: it's refreshed on every successful loadShops, meaning only a
  /// user dormant for >30 days falls back to the blocking cold path.
  static const Duration _kDefaultTtl = Duration(days: 30);

  static String _key(String userId) => 'auth_state:$userId';

  /// Returns the cached state for [userId], or null when there's
  /// nothing cached or the stored value is corrupt / stale-schema.
  /// A corrupt value is removed so the next put writes fresh JSON.
  static Future<CachedAuthState?> get(String userId) async {
    final dao = CacheDao(AppDatabase.instance());
    final entry = await dao.get(_key(userId));
    if (entry == null) return null;
    try {
      final json = jsonDecode(entry.valueJson) as Map<String, dynamic>;
      final symbolsRaw = (json['currency_symbols'] as Map?) ?? const {};
      final symbols = <String, String>{};
      symbolsRaw.forEach((key, value) {
        symbols[key.toString()] = value.toString();
      });
      final shopsRaw = (json['shops'] as List?) ?? const [];
      final shops = shopsRaw
          .map((row) => ShopSummary.fromJson(
                Map<String, dynamic>.from(row as Map),
                currencySymbols: symbols,
              ))
          .toList(growable: false);
      return CachedAuthState(
        shops: shops,
        currencySymbols: symbols,
        selectedShopId: json['selected_shop_id'] as String?,
      );
    } catch (_) {
      // Stored value is corrupt or from a previous schema — drop it.
      await dao.remove(_key(userId));
      return null;
    }
  }

  /// Persist the cached state for [userId]. Errors are swallowed:
  /// SWR caches are best-effort. Passing an empty `shops` list is a
  /// no-op — there's nothing useful to render-fast on the next mount.
  static Future<void> put(
    String userId, {
    required List<ShopSummary> shops,
    required Map<String, String> currencySymbols,
    String? selectedShopId,
  }) async {
    if (shops.isEmpty) return;
    try {
      final dao = CacheDao(AppDatabase.instance());
      final json = <String, dynamic>{
        'shops': shops.map(_shopToJson).toList(),
        'currency_symbols': currencySymbols,
        'selected_shop_id': selectedShopId,
      };
      await dao.put(_key(userId), jsonEncode(json), ttl: _kDefaultTtl);
    } catch (_) {
      // Cache writes never block sign-in.
    }
  }

  /// Drop the cached state for [userId]. Called on sign-out so a
  /// next sign-in by a different user on the same device doesn't
  /// briefly render the previous user's shops.
  static Future<void> clear(String userId) async {
    try {
      final dao = CacheDao(AppDatabase.instance());
      await dao.remove(_key(userId));
    } catch (_) {
      // Best-effort — a failed clear is recoverable on next put.
    }
  }

  static Map<String, dynamic> _shopToJson(ShopSummary shop) {
    // Mirrors the column projection of auth_controller.loadShops's
    // `from('shop').select(...)` so the same fromJson factory can
    // reconstitute the row without a special path.
    return <String, dynamic>{
      'id': shop.id,
      'name': shop.name,
      'setup_status': shop.setupStatus,
      'currency_code': shop.currencyCode,
      'default_language_code': shop.defaultLanguageCode,
      'timezone': shop.timezone,
      'onboarding_dismissed_at':
          shop.onboardingDismissedAt?.toIso8601String(),
      'hide_settlement_legs': shop.hideSettlementLegs,
      'scanner_settings': <String, dynamic>{
        'rearm_ms': shop.scannerSettings.rearmMs,
        'hid_max_inter_key_gap_ms':
            shop.scannerSettings.hidMaxInterKeyGapMs,
        'hid_max_burst_window_ms':
            shop.scannerSettings.hidMaxBurstWindowMs,
        'hid_min_burst_length':
            shop.scannerSettings.hidMinBurstLength,
      },
    };
  }
}
