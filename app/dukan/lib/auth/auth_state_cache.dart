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
// SharedPreferences-backed SWR, per-user key so accounts on the same
// device don't see each other's shops, swallowing on schema-mismatch
// (drop + return null so the cold path runs).
//
// Sign-out clears the cache for the signed-out user.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:dukan/api/types.dart';

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

  static String _key(String userId) => 'auth_state:$userId';

  /// Returns the cached state for [userId], or null when there's
  /// nothing cached or the stored value is corrupt / stale-schema.
  /// A corrupt value is removed so the next put writes fresh JSON.
  static Future<CachedAuthState?> get(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
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
      await prefs.remove(_key(userId));
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
    final prefs = await SharedPreferences.getInstance();
    final json = <String, dynamic>{
      'shops': shops.map(_shopToJson).toList(),
      'currency_symbols': currencySymbols,
      'selected_shop_id': selectedShopId,
    };
    await prefs.setString(_key(userId), jsonEncode(json));
  }

  /// Drop the cached state for [userId]. Called on sign-out so a
  /// next sign-in by a different user on the same device doesn't
  /// briefly render the previous user's shops.
  static Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
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
