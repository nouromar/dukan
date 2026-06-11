// Thin wrapper around sentry_flutter so the rest of the app stays
// decoupled from the SDK. No-ops cleanly when SENTRY_DSN is empty so
// tests, prototype mode, and developer builds don't need credentials.
//
// PII rule: we send only opaque IDs (user UUID, shop UUID). Never phone
// numbers, party names, item names, or anything else that could
// re-identify a Hargeisa shopkeeper or their customers in a hosted
// error-tracker.

import 'package:sentry_flutter/sentry_flutter.dart';

class CrashReporter {
  CrashReporter._();

  static bool _enabled = false;

  /// Marks Sentry as initialised. Called from main.dart after
  /// SentryFlutter.init succeeds. Until this is called, every method
  /// below is a no-op — keeps tests and prototype-mode runs quiet.
  static void install({required bool enabled}) {
    _enabled = enabled;
  }

  /// Whether Sentry was successfully initialised this session. Exposed
  /// for diagnostics; not a load-bearing signal — the methods below
  /// gate themselves.
  static bool get isEnabled => _enabled;

  /// Attach the current user + shop to subsequent events. Called from
  /// AuthBootstrap when the auth state or selected shop changes.
  static void setUser({String? userId, String? shopId}) {
    if (!_enabled) return;
    Sentry.configureScope((scope) {
      scope.setUser(userId == null ? null : SentryUser(id: userId));
      if (shopId == null) {
        scope.removeTag('shop_id');
      } else {
        scope.setTag('shop_id', shopId);
      }
    });
  }

  /// Drop user + shop context — called on sign-out so subsequent
  /// pre-auth errors aren't attributed to the previous session.
  static void clearUser() {
    if (!_enabled) return;
    Sentry.configureScope((scope) {
      scope.setUser(null);
      scope.removeTag('shop_id');
    });
  }

  /// Manually report a non-fatal error (e.g., a swallowed API failure
  /// the user shouldn't see). Fatal/unhandled errors are already
  /// captured by SentryFlutter's FlutterError + PlatformDispatcher
  /// integrations; this is for the case where we want telemetry
  /// without surfacing a crash to the cashier.
  static Future<void> reportError(
    Object error,
    StackTrace? stack, {
    String? hint,
  }) async {
    if (!_enabled) return;
    await Sentry.captureException(
      error,
      stackTrace: stack,
      hint: hint == null ? null : Hint.withMap({'context': hint}),
    );
  }
}
