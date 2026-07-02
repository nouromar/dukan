// Persists the last-known capability codes per (user, shop) so the UI
// gates (edit product, adjust stock, void, etc.) survive offline.
//
// Capabilities are otherwise loaded ONLY from the
// `auth_user_shop_capabilities` RPC and reset to empty on failure, which
// disables every edit affordance in airplane mode (product edit, add,
// void…). Caching lets a shop that was loaded once online keep its edit
// UI available offline.
//
// This is safe: the cache only drives UI GATING. Every mutation still
// goes through a server RPC that re-checks authorization on drain, so a
// stale cached capability can't actually grant an unauthorized write —
// the server rejects it (the post parks). TTL is generous because
// capabilities are role-based and change rarely.
//
// Mirrors lib/auth/auth_state_cache.dart (same sqflite-backed CacheDao,
// per-(user,shop) key, swallow-on-error).

import 'dart:convert';

import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';

class CapabilitiesCache {
  CapabilitiesCache._();

  // Capabilities are stable (role-based); a long TTL keeps edits usable
  // through a long offline stretch. The server is still the real gate.
  static const Duration _kTtl = Duration(days: 30);

  static String _key(String userId, String shopId) =>
      'capabilities:$userId:$shopId';

  /// Last-known capability codes for [userId] at [shopId], or null when
  /// nothing is cached / the entry is corrupt or expired.
  static Future<Set<String>?> get(String userId, String shopId) async {
    try {
      final dao = CacheDao(AppDatabase.instance());
      final entry = await dao.get(_key(userId, shopId));
      if (entry == null) return null;
      final list = jsonDecode(entry.valueJson) as List;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return null;
    }
  }

  /// Persist [codes] for [userId] at [shopId]. Best-effort.
  static Future<void> put(
    String userId,
    String shopId,
    Set<String> codes,
  ) async {
    try {
      final dao = CacheDao(AppDatabase.instance());
      await dao.put(
        _key(userId, shopId),
        jsonEncode(codes.toList()),
        ttl: _kTtl,
      );
    } catch (_) {
      // Cache writes never block auth.
    }
  }
}
