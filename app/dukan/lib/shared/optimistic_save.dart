// Common shell for the optimistic-SAVE choreography used by Sale,
// Receive, Payment, and Expense screens. CLAUDE.md's speed contract
// requires that SAVE clears the UI before the post round-trip completes
// — the four screens each ran their own implementation of:
//
//   Timing.mark('save.tapped') → onClear() → Timing.mark('cleared')
//   → Timing.endFlow(context) → toast → Navigator.maybePop()
//
// They still own validation, controller-snapshot/restore, the RPC
// call itself, and per-screen failure modes (Sale's dual server-reject
// vs transient branch lives at the call site; the shell is unaware).

import 'package:flutter/material.dart';

import 'package:dukan/observability/timing.dart';

/// Run the optimistic-save UI sequence. Call this AFTER validation
/// passes and AFTER snapshotting any state the caller will need on
/// failure. The closure `onClear` should empty the screen's input
/// state (typically `controller.clearAll()` + text-controller clears)
/// — it runs between the two timing marks so cashier-felt latency
/// matches the actual UI clear.
///
/// Returns the ScaffoldMessengerState so the caller can use it for
/// post-clear toasts (e.g. background-post failure messages); the
/// reference is captured before maybePop in case the screen is
/// already off the back stack by the time the future settles.
ScaffoldMessengerState runOptimisticSaveShell({
  required BuildContext context,
  required String savedToast,
  required VoidCallback onClear,
}) {
  Timing.mark('save.tapped');
  final messenger = ScaffoldMessenger.of(context);
  onClear();
  Timing.mark('cleared');
  Timing.endFlow(context);
  messenger.showSnackBar(SnackBar(content: Text(savedToast)));
  Navigator.of(context).maybePop();
  return messenger;
}

/// Standard handling for a background-post failure: log via
/// FlutterError so Sentry / DevTools sees the stack, then surface a
/// localized failure toast through the captured messenger. Used by
/// the post-in-background helpers in Payment, Expense, and any other
/// screen with a simple "toast on any failure" policy. Sale has its
/// own dual-mode handler (PostgrestException → restore; transient →
/// enqueue) and does not route through here.
void reportBackgroundFailure({
  required Object error,
  required StackTrace stackTrace,
  required ScaffoldMessengerState messenger,
  required String library,
  required String context,
  required String failureMessage,
}) {
  FlutterError.reportError(FlutterErrorDetails(
    exception: error,
    stack: stackTrace,
    library: library,
    context: ErrorDescription(context),
  ));
  messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
}
