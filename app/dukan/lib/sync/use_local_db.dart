// Tiny helper for screens to check whether to use the on-device
// sqflite mirror for daily-flow reads/writes (true) or talk to
// the server directly (false). Centralised so every screen
// branches the same way.
//
// Naming discipline (#382): "useLocalDb" names the feature
// toggle. The word "offline" elsewhere in copy refers to phone
// connectivity (no internet) — a separate axis. The app
// responds to connectivity loss differently depending on
// useLocalDb, but the toggle itself is purely about which data
// path the app uses.

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';

/// True when the app should use its on-device sqflite mirror for
/// daily-flow reads/writes; false when it should hit the server
/// for every operation.
///
/// Resolution precedence (highest first):
///   1. Explicit `use_local_db` override at device / shop / org
///      layer (bool).
///   2. Legacy `offline_mode` override at any layer (`'full'` →
///      true, `'light'` → false). One release of backwards
///      compatibility with rows set before `#382`. Drop in
///      `#385`.
///   3. Default: true.
bool resolveUseLocalDb(ConfigResolver resolver) {
  // 1. New key (highest precedence).
  final newOverride = resolver.rawOverride(ConfigKeys.useLocalDb.name);
  if (newOverride != null) {
    try {
      return ConfigKeys.useLocalDb.parse(newOverride);
    } catch (_) {
      // fall through to legacy / default
    }
  }
  // 2. Legacy `offline_mode` override — map `'full'` / `'light'`.
  final legacy = resolver.rawOverride('offline_mode');
  if (legacy is String) {
    if (legacy == 'light') return false;
    if (legacy == 'full') return true;
  }
  // 3. Default.
  return ConfigKeys.useLocalDb.defaultValue;
}

/// Widget-context wrapper around [resolveUseLocalDb]. Returns
/// false when no [ConfigResolver] is in scope (e.g. widget tests
/// that don't wire one). Tests that exercise the queue path must
/// wire a ConfigResolver with `use_local_db = true` (matches
/// production default).
bool useLocalDb(BuildContext context) {
  try {
    return resolveUseLocalDb(context.read<ConfigResolver>());
  } catch (_) {
    return false;
  }
}

/// Legacy alias for [useLocalDb] — kept for one release so any
/// path not yet renamed still compiles. Drop in `#385`.
@Deprecated('use useLocalDb(context) — see #382')
bool offlineModeFull(BuildContext context) => useLocalDb(context);
