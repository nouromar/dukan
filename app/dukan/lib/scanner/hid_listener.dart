// Bluetooth-HID scanner detector. Cheap (~$20) BT scanners pair as
// keyboards and emit decoded codes as a burst of keystrokes followed
// by Enter. The OS routes those keystrokes to whatever text field is
// focused — same as a human typing — so we can't distinguish them
// from typed input without a heuristic.
//
// The heuristic per docs/scanner.md §12.2: when an Enter arrives,
// look back at the buffer; if the previous ≥ 4 printable keys
// arrived in a sub-200ms total window with each consecutive gap <
// 50ms, treat the run as a scan burst, emit a ScanEvent, consume
// the Enter so it doesn't fire any focused-field submit handler.
//
// Each screen attaches its own listener in initState and detaches in
// dispose. Bursts dispatch only when the registered screen is the
// current route — push another screen, and the underlying listener
// goes quiet (covers the case where Sale and Receive are both in the
// stack but only one is visible).

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:dukan/scanner/scan_event.dart';

class HidScanListener {
  HidScanListener({
    required this.onScan,
    required this.isActive,
    Duration maxInterKeyGap = const Duration(milliseconds: 50),
    Duration maxBurstWindow = const Duration(milliseconds: 200),
    int minBurstLength = 4,
  }) : _maxInterKeyGap = maxInterKeyGap,
       _maxBurstWindow = maxBurstWindow,
       _minBurstLength = minBurstLength;

  /// Fires once per detected burst.
  final void Function(ScanEvent event) onScan;

  /// Gate dispatch. Typically returns true when the screen's route is
  /// the current one (and `mounted`). When false, the listener buffers
  /// silently and emits nothing.
  final bool Function() isActive;

  final Duration _maxInterKeyGap;
  final Duration _maxBurstWindow;
  final int _minBurstLength;

  final List<_BufferedKey> _buffer = <_BufferedKey>[];

  bool _attached = false;

  void attach() {
    if (_attached) return;
    HardwareKeyboard.instance.addHandler(_handle);
    _attached = true;
  }

  void detach() {
    if (!_attached) return;
    HardwareKeyboard.instance.removeHandler(_handle);
    _attached = false;
    _buffer.clear();
  }

  /// Visible for testing — drives a synthetic key event without touching
  /// the global HardwareKeyboard singleton.
  bool debugHandle(KeyEvent event) => _handle(event);

  bool _handle(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final now = _now();

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final code = _drainBurst(now);
      if (code == null || !isActive()) {
        _buffer.clear();
        return false;
      }
      onScan(ScanEvent(code: code, source: ScanSource.hid));
      return true; // consume Enter
    }

    final ch = event.character;
    if (ch == null || ch.isEmpty || ch.codeUnitAt(0) < 0x20) {
      // Drop non-printable / modifier keys — anything that can't be
      // part of a barcode payload.
      return false;
    }
    _buffer.add(_BufferedKey(ch, now));
    // Trim aggressively so a slow-typed search query doesn't grow the
    // buffer without bound between bursts.
    while (_buffer.length > 64) {
      _buffer.removeAt(0);
    }
    return false;
  }

  String? _drainBurst(DateTime enterAt) {
    if (_buffer.isEmpty) return null;
    // Walk backwards: consecutive printables, each within
    // _maxInterKeyGap of the next, and the whole run inside
    // _maxBurstWindow ending at the Enter timestamp.
    final chars = <String>[];
    DateTime prev = enterAt;
    for (var i = _buffer.length - 1; i >= 0; i--) {
      final entry = _buffer[i];
      if (prev.difference(entry.at).abs() > _maxInterKeyGap) {
        break;
      }
      if (enterAt.difference(entry.at).abs() > _maxBurstWindow) {
        break;
      }
      chars.insert(0, entry.char);
      prev = entry.at;
    }
    _buffer.clear();
    if (chars.length < _minBurstLength) return null;
    return chars.join();
  }

  DateTime _now() => _clock?.call() ?? DateTime.now();

  DateTime Function()? _clock;

  /// Visible for testing — inject a deterministic clock so we don't
  /// depend on real time in heuristic tests.
  @visibleForTesting
  void setClockForTesting(DateTime Function()? clock) {
    _clock = clock;
  }
}

class _BufferedKey {
  _BufferedKey(this.char, this.at);
  final String char;
  final DateTime at;
}
