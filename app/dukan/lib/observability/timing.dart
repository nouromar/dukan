// Speed-audit instrumentation. Markers record elapsed times for the
// daily flows so the audit recording captures the actual numbers
// without us having to read frame-by-frame timestamps off a video.
//
// Gated by !kReleaseMode: in debug + profile mode markers fire and
// flash a SnackBar at end-of-flow; in a release build (pilot APK)
// the calls compile down to early-returns and the SnackBar code is
// tree-shaken. Pilot devices pay zero runtime cost.
//
// Use:
//   Timing.startFlow('sale.cash.1');
//   ... cashier interacts ...
//   Timing.mark('search.results');
//   ...
//   Timing.mark('save.tapped');
//   ...
//   Timing.endFlow(context, budgetMillis: 5000);
//
// endFlow logs to console and shows a SnackBar like:
//   "sale.cash.1: 3142ms ✓ (budget 5000ms)"
//
// The flow name is the line we compare against the speed contract;
// the marks in between help locate which segment ate the budget when
// a flow misses.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class _TimingMark {
  _TimingMark(this.label, this.elapsedMs);
  final String label;
  final int elapsedMs;
}

class Timing {
  Timing._();

  /// Markers are active in debug + profile, disabled in release.
  /// Tree-shaken at compile time when [kReleaseMode] is true.
  static const bool enabled = !kReleaseMode;

  static Stopwatch? _watch;
  static String? _currentFlow;
  static final List<_TimingMark> _marks = <_TimingMark>[];

  /// Begin a new flow. Resets the clock and marks list. Calling
  /// twice without endFlow overwrites — the most recent startFlow
  /// wins.
  static void startFlow(String name) {
    if (!enabled) return;
    _watch = Stopwatch()..start();
    _currentFlow = name;
    _marks.clear();
    debugPrint('[timing] $name START');
  }

  /// Record an intermediate timing for the current flow. No-op when
  /// no flow is active.
  static void mark(String label) {
    if (!enabled) return;
    final watch = _watch;
    if (watch == null) return;
    final ms = watch.elapsedMilliseconds;
    _marks.add(_TimingMark(label, ms));
    debugPrint('[timing] $_currentFlow $label ${ms}ms');
  }

  /// End the current flow. Surfaces a SnackBar in debug + profile
  /// when [context] is provided and still mounted. The SnackBar's
  /// duration is short — long enough to read, not long enough to
  /// interfere with the next flow.
  ///
  /// [budgetMillis] is the speed-contract target this flow should
  /// hit. When provided, the SnackBar appends ✓ or ✗ for at-a-glance
  /// pass/fail.
  static void endFlow(
    BuildContext? context, {
    int? budgetMillis,
  }) {
    if (!enabled) return;
    final watch = _watch;
    if (watch == null) return;
    final total = watch.elapsedMilliseconds;
    final flow = _currentFlow ?? '(no flow)';
    final passed = budgetMillis == null ? null : total <= budgetMillis;
    final passMark = passed == null
        ? ''
        : passed
            ? ' ✓'
            : ' ✗';
    final budgetTail = budgetMillis == null ? '' : ' (budget ${budgetMillis}ms)';
    final message = '$flow: ${total}ms$passMark$budgetTail';
    debugPrint('[timing] END $message');
    for (final m in _marks) {
      debugPrint('[timing]   · ${m.label} @ ${m.elapsedMs}ms');
    }
    _watch = null;
    _currentFlow = null;
    _marks.clear();
    if (context != null) {
      // Defer to next frame so the caller's setState (cart clear,
      // route pop, etc.) lands first and the SnackBar overlays the
      // already-fresh UI.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
            backgroundColor: passed == false
                ? Colors.red.shade700
                : Colors.green.shade700,
          ),
        );
      });
    }
  }

  /// Reset state without emitting a SnackBar. Useful when a flow is
  /// cancelled mid-way and we don't want the next startFlow to be
  /// confused by lingering state. Visible-for-testing too.
  @visibleForTesting
  static void reset() {
    if (!enabled) return;
    _watch = null;
    _currentFlow = null;
    _marks.clear();
  }
}
