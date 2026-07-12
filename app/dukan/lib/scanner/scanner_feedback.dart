// Audio + haptic policy for scan events. Centralised so every entry
// point (camera viewfinder, HID listener, multi-scan) gives the
// cashier the same cue — see docs/scanner.md §9.
//
// V1 policy (haptics always fire; the beep is gated by
// ScannerSettings.soundEnabled so a shop can run silent):
//   success     → medium-impact haptic + alert beep.
//   duplicate   → selection-click haptic + soft click (multi-scan "+1").
//   unknown     → light vibrate ONLY in multi-scan mode; otherwise
//                  silent (the inline pill is the cue). No tone — a
//                  same-as-success tone would be ambiguous.
//   error       → vibrate (camera busy, permission denied mid-scan).
//
// The beep uses the platform's own SystemSound (zero deps, no asset).
// [soundPlayer] is an injection seam so tests can assert what plays.

import 'package:flutter/services.dart';

import 'package:dukan/scanner/scanner_settings.dart';

class ScannerFeedback {
  ScannerFeedback._();

  /// Plays a platform system sound. Overridable in tests.
  static Future<void> Function(SystemSoundType) soundPlayer = SystemSound.play;

  static Future<void> _beep(SystemSoundType type) async {
    if (!ScannerSettings.current.soundEnabled) return;
    await soundPlayer(type);
  }

  static Future<void> success() async {
    await HapticFeedback.mediumImpact();
    await _beep(SystemSoundType.alert);
  }

  static Future<void> duplicate() async {
    await HapticFeedback.selectionClick();
    await _beep(SystemSoundType.click);
  }

  static Future<void> unknownInMultiScan() => HapticFeedback.lightImpact();

  static Future<void> error() => HapticFeedback.vibrate();
}
