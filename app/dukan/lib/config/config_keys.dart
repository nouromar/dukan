// Typed catalog of hierarchical config keys. Read through
// `ConfigResolver`; the resolver walks the override chain (defaults →
// org → shop → device) and returns the strongly-typed value.
//
// Adding a new key here is the only place — the resolver, RPC, and
// table use the `name` as the wire key. Defaults MUST match the
// hard-coded constants in `storage_defaults.dart` so behavior is
// unchanged when nothing overrides.

import 'package:dukan/storage/storage_defaults.dart';

/// Default value plus a `parse` from the raw jsonb-decoded value
/// (which may be int, double, String, bool, num — whatever Postgres
/// serialized) into the typed `T` the caller expects.
class ConfigKey<T> {
  const ConfigKey({
    required this.name,
    required this.defaultValue,
    required this.parse,
  });

  /// Wire key — matches the `platform_config.key` column AND the
  /// `shop_setting.key` / `device_config.key` columns when those layers
  /// override it.
  final String name;
  final T defaultValue;

  /// Converts the raw decoded value into `T`. Resolver feeds the parser
  /// with whatever Postgres jsonb decoded to: numbers may arrive as int
  /// or double, strings as String, etc. Throw `FormatException` on
  /// truly unparseable input — the resolver catches it and falls
  /// through to the next override layer.
  final T Function(Object?) parse;
}

T _parseInt<T>(Object? raw) {
  if (raw is int) return raw as T;
  if (raw is num) return raw.toInt() as T;
  if (raw is String) {
    final n = int.tryParse(raw);
    if (n != null) return n as T;
  }
  throw FormatException('expected int, got ${raw.runtimeType}: $raw');
}

T _parseString<T>(Object? raw) {
  if (raw is String) return raw as T;
  throw FormatException('expected String, got ${raw.runtimeType}: $raw');
}

class ConfigKeys {
  // --- Queue mechanics --------------------------------------------------
  static const ConfigKey<int> queueMaxPending = ConfigKey<int>(
    name: 'queue_max_pending',
    defaultValue: kQueueMaxPending,
    parse: _parseInt,
  );

  static const ConfigKey<int> queueMaxAttempts = ConfigKey<int>(
    name: 'queue_max_attempts',
    defaultValue: kQueueMaxAttempts,
    parse: _parseInt,
  );

  static const ConfigKey<int> queueRetryInitialMs = ConfigKey<int>(
    name: 'queue_retry_initial_ms',
    defaultValue: 5000,
    parse: _parseInt,
  );

  static const ConfigKey<int> queueRetryMaxMs = ConfigKey<int>(
    name: 'queue_retry_max_ms',
    defaultValue: 1800000,
    parse: _parseInt,
  );

  static const ConfigKey<int> queueRetryMultiplier = ConfigKey<int>(
    name: 'queue_retry_multiplier',
    defaultValue: 3,
    parse: _parseInt,
  );

  // --- Cache mechanics --------------------------------------------------
  static const ConfigKey<int> cacheBudgetMb = ConfigKey<int>(
    name: 'cache_budget_mb',
    defaultValue: kCacheBudgetMb,
    parse: _parseInt,
  );

  static const ConfigKey<int> cacheTtlTodaySummaryS = ConfigKey<int>(
    name: 'cache_ttl_today_summary_s',
    defaultValue: 3600,
    parse: _parseInt,
  );

  static const ConfigKey<int> cacheTtlProductsS = ConfigKey<int>(
    name: 'cache_ttl_products_s',
    defaultValue: 1800,
    parse: _parseInt,
  );

  static const ConfigKey<int> cacheTtlPartiesS = ConfigKey<int>(
    name: 'cache_ttl_parties_s',
    defaultValue: 3600,
    parse: _parseInt,
  );

  /// Sale + Receive history caches share this TTL — both go stale
  /// fast as new posts come in. Default 5 min (300s).
  static const ConfigKey<int> cacheTtlHistoryS = ConfigKey<int>(
    name: 'cache_ttl_history_s',
    defaultValue: 300,
    parse: _parseInt,
  );

  /// Search-items results cache TTL. Not wired in Phase 5C — kept
  /// here so the platform_config table has the key when the cache
  /// arrives.
  static const ConfigKey<int> cacheTtlSearchItemsS = ConfigKey<int>(
    name: 'cache_ttl_search_items_s',
    defaultValue: 300,
    parse: _parseInt,
  );

  // --- Sync + alerts (owner-tunable) ------------------------------------
  /// 'auto' (default), 'wifi' (only sync on Wi-Fi), 'off' (manual only).
  static const ConfigKey<String> syncMode = ConfigKey<String>(
    name: 'sync_mode',
    defaultValue: 'auto',
    parse: _parseString,
  );

  static const ConfigKey<int> alertOfflineHours = ConfigKey<int>(
    name: 'alert_offline_hours',
    defaultValue: 24,
    parse: _parseInt,
  );

  static const ConfigKey<int> alertPendingThreshold = ConfigKey<int>(
    name: 'alert_pending_threshold',
    defaultValue: 20,
    parse: _parseInt,
  );
}
