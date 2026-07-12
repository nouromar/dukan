import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/scanner/scanner_settings.dart';

void main() {
  test('defaults match the v1 baseline', () {
    const d = ScannerSettings.defaults;
    expect(d.rearmMs, 800);
    expect(d.hidMaxInterKeyGapMs, 50);
    expect(d.hidMaxBurstWindowMs, 200);
    expect(d.hidMinBurstLength, 4);
    expect(d.soundEnabled, isTrue);
    expect(d.rearm, const Duration(milliseconds: 800));
    expect(d.hidMaxInterKeyGap, const Duration(milliseconds: 50));
    expect(d.hidMaxBurstWindow, const Duration(milliseconds: 200));
  });

  test('sound_enabled parses; defaults on; false honored', () {
    expect(ScannerSettings.fromJson(<String, dynamic>{}).soundEnabled, isTrue);
    expect(
      ScannerSettings.fromJson(<String, dynamic>{'sound_enabled': false})
          .soundEnabled,
      isFalse,
    );
    expect(
      ScannerSettings.fromJson(<String, dynamic>{'sound_enabled': true})
          .soundEnabled,
      isTrue,
    );
  });

  test('fromJson parses every knob', () {
    final s = ScannerSettings.fromJson(<String, dynamic>{
      'rearm_ms': 1200,
      'hid_max_inter_key_gap_ms': 80,
      'hid_max_burst_window_ms': 250,
      'hid_min_burst_length': 6,
    });
    expect(s.rearmMs, 1200);
    expect(s.hidMaxInterKeyGapMs, 80);
    expect(s.hidMaxBurstWindowMs, 250);
    expect(s.hidMinBurstLength, 6);
  });

  test('fromJson tolerates missing keys (uses defaults)', () {
    final s = ScannerSettings.fromJson(<String, dynamic>{'rearm_ms': 1500});
    expect(s.rearmMs, 1500);
    expect(s.hidMaxInterKeyGapMs, 50);
    expect(s.hidMaxBurstWindowMs, 200);
    expect(s.hidMinBurstLength, 4);
  });

  test('fromJson on null returns defaults', () {
    expect(ScannerSettings.fromJson(null), ScannerSettings.defaults);
  });

  test('fromJson tolerates num values (jsonb returns dynamic)', () {
    final s = ScannerSettings.fromJson(<String, dynamic>{
      'rearm_ms': 1200.0,
      'hid_min_burst_length': 5.0,
    });
    expect(s.rearmMs, 1200);
    expect(s.hidMinBurstLength, 5);
  });

  test('install + resetForTesting round-trip', () {
    expect(ScannerSettings.current, ScannerSettings.defaults);
    ScannerSettings.install(const ScannerSettings(rearmMs: 1500));
    expect(ScannerSettings.current.rearmMs, 1500);
    ScannerSettings.resetForTesting();
    expect(ScannerSettings.current, ScannerSettings.defaults);
  });

  test('equality is structural', () {
    const a = ScannerSettings(rearmMs: 800);
    const b = ScannerSettings();
    expect(a, equals(b));
    expect(a, isNot(equals(const ScannerSettings(rearmMs: 1000))));
  });
}
