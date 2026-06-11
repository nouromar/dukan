// Per-shop scanner tuning knobs. Source-of-truth lives in the shop
// row's scanner_settings jsonb column (populated from template_setting
// via apply_template per migration 0049). Mobile reads the parsed
// values via ShopSummary and stashes them in [ScannerSettings.current]
// so the viewfinder sheets and HID listener can read without
// threading the values through every call site.
//
// Defaults match the column DEFAULT in the migration and the
// constants the scanner code used before this layer was wired.
// Tests reset .current to .defaults via flutter_test_config.

import 'package:flutter/foundation.dart';

@immutable
class ScannerSettings {
  const ScannerSettings({
    this.rearmMs = 800,
    this.hidMaxInterKeyGapMs = 50,
    this.hidMaxBurstWindowMs = 200,
    this.hidMinBurstLength = 4,
  });

  /// The v1 baseline. Matches the migration's column default exactly.
  static const ScannerSettings defaults = ScannerSettings();

  factory ScannerSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    return ScannerSettings(
      rearmMs: _intOr(json['rearm_ms'], defaults.rearmMs),
      hidMaxInterKeyGapMs:
          _intOr(json['hid_max_inter_key_gap_ms'], defaults.hidMaxInterKeyGapMs),
      hidMaxBurstWindowMs:
          _intOr(json['hid_max_burst_window_ms'], defaults.hidMaxBurstWindowMs),
      hidMinBurstLength:
          _intOr(json['hid_min_burst_length'], defaults.hidMinBurstLength),
    );
  }

  static int _intOr(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return fallback;
  }

  final int rearmMs;
  final int hidMaxInterKeyGapMs;
  final int hidMaxBurstWindowMs;
  final int hidMinBurstLength;

  Duration get rearm => Duration(milliseconds: rearmMs);
  Duration get hidMaxInterKeyGap =>
      Duration(milliseconds: hidMaxInterKeyGapMs);
  Duration get hidMaxBurstWindow =>
      Duration(milliseconds: hidMaxBurstWindowMs);

  /// Process-global current settings. AuthController writes this on
  /// shop selection; the scanner sheets + HID listener read it at
  /// open/attach time. Static because most consumers can't easily
  /// thread a ShopSummary parameter through (the camera path opens
  /// via `Scanner.open(context)` — adding `settings:` to every call
  /// site is more noise than the global field).
  static ScannerSettings current = defaults;

  static void install(ScannerSettings settings) {
    current = settings;
  }

  /// Reset to defaults. Used by `flutter_test_config.dart` between
  /// tests so a previous test's override doesn't leak.
  @visibleForTesting
  static void resetForTesting() {
    current = defaults;
  }

  @override
  bool operator ==(Object other) =>
      other is ScannerSettings &&
      other.rearmMs == rearmMs &&
      other.hidMaxInterKeyGapMs == hidMaxInterKeyGapMs &&
      other.hidMaxBurstWindowMs == hidMaxBurstWindowMs &&
      other.hidMinBurstLength == hidMinBurstLength;

  @override
  int get hashCode => Object.hash(
        rearmMs,
        hidMaxInterKeyGapMs,
        hidMaxBurstWindowMs,
        hidMinBurstLength,
      );

  @override
  String toString() =>
      'ScannerSettings(rearm=${rearmMs}ms, hidGap=${hidMaxInterKeyGapMs}ms, '
      'hidWindow=${hidMaxBurstWindowMs}ms, hidMinLen=$hidMinBurstLength)';
}
