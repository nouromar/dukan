// Heuristic tests for HidScanListener. We drive synthetic
// KeyDownEvent values via debugHandle and a stubbed clock so the
// timing window is deterministic — no real time, no real
// HardwareKeyboard registration.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/scanner/hid_listener.dart';
import 'package:dukan/scanner/scan_event.dart';

KeyDownEvent _down(String char, {LogicalKeyboardKey? key, Duration? at}) {
  return KeyDownEvent(
    logicalKey: key ?? LogicalKeyboardKey.digit0,
    physicalKey: PhysicalKeyboardKey.digit0,
    character: char,
    timeStamp: at ?? Duration.zero,
  );
}

KeyDownEvent _enter() => KeyDownEvent(
      logicalKey: LogicalKeyboardKey.enter,
      physicalKey: PhysicalKeyboardKey.enter,
      timeStamp: Duration.zero,
    );

void main() {
  group('HidScanListener', () {
    late HidScanListener listener;
    late List<ScanEvent> events;
    late DateTime now;

    void tick([int millis = 20]) {
      now = now.add(Duration(milliseconds: millis));
    }

    setUp(() {
      now = DateTime(2026, 6, 11, 9, 0, 0);
      events = <ScanEvent>[];
      listener = HidScanListener(
        onScan: events.add,
        isActive: () => true,
      )..setClockForTesting(() => now);
    });

    test('emits a ScanEvent for a sub-200ms burst terminated by Enter', () {
      const code = '5901234123457';
      for (final ch in code.split('')) {
        listener.debugHandle(_down(ch));
        tick(10); // 10ms between keys → well under 50ms gap
      }
      // Enter arrives within the same burst window
      final consumed = listener.debugHandle(_enter());
      expect(consumed, isTrue, reason: 'Enter on a burst should be consumed');
      expect(events, hasLength(1));
      expect(events.single.code, code);
      expect(events.single.source, ScanSource.hid);
    });

    test('does NOT emit when keys arrive too slowly (human typing)', () {
      // Each gap is 80ms — above the 50ms inter-key threshold.
      for (final ch in '12345'.split('')) {
        listener.debugHandle(_down(ch));
        tick(80);
      }
      final consumed = listener.debugHandle(_enter());
      expect(consumed, isFalse, reason: 'slow typing should pass through');
      expect(events, isEmpty);
    });

    test('does NOT emit for runs shorter than minBurstLength', () {
      for (final ch in 'abc'.split('')) {
        listener.debugHandle(_down(ch));
        tick(10);
      }
      listener.debugHandle(_enter());
      expect(events, isEmpty);
    });

    test('does NOT emit when isActive returns false', () {
      bool active = false;
      final inactiveListener = HidScanListener(
        onScan: events.add,
        isActive: () => active,
      )..setClockForTesting(() => now);
      for (final ch in '1234567890123'.split('')) {
        inactiveListener.debugHandle(_down(ch));
        tick(10);
      }
      inactiveListener.debugHandle(_enter());
      expect(events, isEmpty);
      // Now flip active for a new burst and confirm dispatch resumes.
      active = true;
      for (final ch in '7654321'.split('')) {
        inactiveListener.debugHandle(_down(ch));
        tick(10);
      }
      inactiveListener.debugHandle(_enter());
      expect(events, hasLength(1));
      expect(events.single.code, '7654321');
    });

    test('numpad Enter terminates a burst', () {
      for (final ch in '1234567890123'.split('')) {
        listener.debugHandle(_down(ch));
        tick(10);
      }
      final consumed = listener.debugHandle(KeyDownEvent(
        logicalKey: LogicalKeyboardKey.numpadEnter,
        physicalKey: PhysicalKeyboardKey.numpadEnter,
        timeStamp: Duration.zero,
      ));
      expect(consumed, isTrue);
      expect(events.single.code, '1234567890123');
    });

    test('non-printable keys do not enter the burst buffer', () {
      // Three printable then Shift then more printable. The Shift drop
      // doesn't break the burst; the run is still contiguous printable.
      for (final ch in '123'.split('')) {
        listener.debugHandle(_down(ch));
        tick(10);
      }
      // Synthesize a Shift-like event with no character.
      listener.debugHandle(KeyDownEvent(
        logicalKey: LogicalKeyboardKey.shift,
        physicalKey: PhysicalKeyboardKey.shiftLeft,
        timeStamp: Duration.zero,
      ));
      tick(10);
      for (final ch in '4567'.split('')) {
        listener.debugHandle(_down(ch));
        tick(10);
      }
      listener.debugHandle(_enter());
      expect(events.single.code, '1234567');
    });

    test('buffer is cleared after a burst, second burst dispatches', () {
      for (final ch in '1111'.split('')) {
        listener.debugHandle(_down(ch));
        tick(10);
      }
      listener.debugHandle(_enter());
      expect(events.single.code, '1111');

      for (final ch in '22222'.split('')) {
        listener.debugHandle(_down(ch));
        tick(10);
      }
      listener.debugHandle(_enter());
      expect(events, hasLength(2));
      expect(events.last.code, '22222');
    });
  });
}
