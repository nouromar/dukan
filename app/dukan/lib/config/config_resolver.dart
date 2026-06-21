// Hierarchical config resolver. Precedence (lowest → highest):
//   1. App-coded default (ConfigKey.defaultValue)
//   2. Org-scoped override (platform_config row, org_id = caller's org)
//   3. Shop-scoped override (shop_setting row)
//   4. Device-scoped override (device_config row — toggled by the
//      cashier in the Storage & sync UI)
//
// Layers are loaded once per session (and reloaded on shop switch)
// into in-memory maps. `resolve()` is O(1) hash lookups + an
// `Object? -> T` parse.
//
// Failure semantics: a parse error on any layer falls through to the
// next layer (with a Sentry log). A failed RPC during `loadForSession`
// keeps the resolver usable — defaults still resolve. Never blocks
// app boot.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/config/config_keys.dart';
import 'package:dukan/storage/device_config_dao.dart';

class ConfigResolver extends ChangeNotifier {
  ConfigResolver({
    required this.shopApi,
    required this.deviceConfigDao,
    void Function(Object error, StackTrace stack, String hint)? reportError,
  }) : _reportError = reportError;

  final ShopApi shopApi;
  final DeviceConfigDao deviceConfigDao;
  final void Function(Object, StackTrace, String)? _reportError;

  Map<String, Object?> _orgValues = const <String, Object?>{};
  Map<String, Object?> _shopValues = const <String, Object?>{};
  Map<String, String> _deviceValues = const <String, String>{};

  /// True once `loadForSession` has populated at least the device
  /// layer. Callers that gate on "config ready" can watch this; most
  /// callers just `resolve()` and get defaults pre-load.
  bool _loaded = false;
  bool get loaded => _loaded;

  /// Walks the override chain and returns the resolved value. Always
  /// returns a value — falls back to `key.defaultValue` if nothing
  /// up the chain matches or parses cleanly.
  T resolve<T>(ConfigKey<T> key) {
    // Device — JSON-encoded strings (we store everything via
    // jsonEncode so device overrides round-trip with the same parse
    // pipeline as the server layers).
    final deviceRaw = _deviceValues[key.name];
    if (deviceRaw != null) {
      final parsed = _tryParse(key, _maybeJsonDecode(deviceRaw),
          layer: 'device');
      if (parsed != null) return parsed;
    }
    final shopRaw = _shopValues[key.name];
    if (shopRaw != null) {
      final parsed = _tryParse(key, shopRaw, layer: 'shop');
      if (parsed != null) return parsed;
    }
    final orgRaw = _orgValues[key.name];
    if (orgRaw != null) {
      final parsed = _tryParse(key, orgRaw, layer: 'org');
      if (parsed != null) return parsed;
    }
    return key.defaultValue;
  }

  T? _tryParse<T>(ConfigKey<T> key, Object? raw, {required String layer}) {
    try {
      return key.parse(raw);
    } catch (error, stack) {
      _reportError?.call(
        error,
        stack,
        'ConfigResolver.parse[$layer]:${key.name}',
      );
      return null;
    }
  }

  /// Best-effort JSON decode for the device-stored string. Device
  /// overrides should always be valid JSON (the resolver's
  /// `setDeviceOverride` calls `jsonEncode`), but if a raw scalar
  /// snuck in (test fixtures, manual SQL), fall back to the raw
  /// string.
  Object? _maybeJsonDecode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return s;
    }
  }

  /// Refresh all layers for the given shop. Safe to call repeatedly —
  /// each call replaces the in-memory snapshot. Catches RPC errors
  /// silently so a flaky network doesn't lock the resolver out of
  /// returning defaults.
  Future<void> loadForSession({
    required String shopId,
    Map<String, Object?> shopValues = const <String, Object?>{},
  }) async {
    Map<String, Object?> orgValues = const <String, Object?>{};
    try {
      final rows = await shopApi.getPlatformConfigForShop(shopId: shopId);
      orgValues = {for (final r in rows) r.key: r.value};
    } catch (error, stack) {
      _reportError?.call(
        error,
        stack,
        'ConfigResolver.loadForSession.platformConfig',
      );
      // Defaults are fine; press on.
    }
    Map<String, String> deviceValues = const <String, String>{};
    try {
      deviceValues = await deviceConfigDao.loadAll();
    } catch (error, stack) {
      _reportError?.call(
        error,
        stack,
        'ConfigResolver.loadForSession.deviceConfig',
      );
    }
    _orgValues = orgValues;
    _shopValues = shopValues;
    _deviceValues = deviceValues;
    _loaded = true;
    notifyListeners();
  }

  /// Set a device-level override. JSON-encodes the value so the
  /// resolver's read path round-trips through `jsonDecode` and feeds
  /// the same parser the org + shop layers use.
  Future<void> setDeviceOverride(String key, Object? value) async {
    await deviceConfigDao.set(key, jsonEncode(value));
    _deviceValues = {..._deviceValues, key: jsonEncode(value)};
    notifyListeners();
  }

  /// Clear a device-level override (the resolver falls through to
  /// the next layer below).
  Future<void> clearDeviceOverride(String key) async {
    await deviceConfigDao.remove(key);
    final next = Map<String, String>.from(_deviceValues)..remove(key);
    _deviceValues = next;
    notifyListeners();
  }

  /// Resets in-memory state. Used by tests + by sign-out to drop the
  /// resolved snapshot for the prior user. The next loadForSession
  /// repopulates.
  void reset() {
    _orgValues = const <String, Object?>{};
    _shopValues = const <String, Object?>{};
    _deviceValues = const <String, String>{};
    _loaded = false;
    notifyListeners();
  }
}
