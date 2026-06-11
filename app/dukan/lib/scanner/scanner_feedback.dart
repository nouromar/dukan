// Audio + haptic policy for scan events. Centralised so every entry
// point (camera viewfinder, HID listener, multi-scan) gives the
// cashier the same cue — see docs/scanner.md §9.
//
// V1 policy:
//   success     → medium-impact haptic. Audio beep deferred until
//                  we wire a tiny on-device sample (or fall back to
//                  the platform success-feedback). HapticFeedback is
//                  immediate and free.
//   duplicate   → selection-click haptic (multi-scan "+1" feedback).
//   unknown     → light vibrate ONLY in multi-scan mode; otherwise
//                  silent (the inline pill is the cue).
//   error       → vibrate (camera busy, permission denied mid-scan).
//
// Future work: wire SystemSound.play(SystemSoundType.click) when the
// platform offers a softer alternative; ship a custom .wav asset
// later if user research validates it.

import 'package:flutter/services.dart';

class ScannerFeedback {
  ScannerFeedback._();

  static Future<void> success() => HapticFeedback.mediumImpact();

  static Future<void> duplicate() => HapticFeedback.selectionClick();

  static Future<void> unknownInMultiScan() => HapticFeedback.lightImpact();

  static Future<void> error() => HapticFeedback.vibrate();
}
