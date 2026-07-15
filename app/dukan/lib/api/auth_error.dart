// Single source of truth for classifying Supabase auth/token failures and
// recovering from them with a session refresh.
//
// Why this exists: after ~1 hour the Supabase access token (JWT) expires. On a
// cold start / resume the very first authenticated call can race the background
// refresh and come back as a *transient* auth reject — PostgREST returns
// PGRST301/302 (HTTP 401) for a missing/expired JWT, and supabase-dart throws
// AuthException directly. Those must NOT be treated like a genuine server
// reject (a business-rule / constraint failure), which fails identically
// forever. The offline queue drain already refreshes-and-retries on this class
// (lib/queue/offline_queue_controller.dart); [withAuthRetry] extends the same
// discipline to the online direct-write path so a stale token can't hard-fail a
// sale/receive/payment/expense the way it did right after install.

import 'package:supabase_flutter/supabase_flutter.dart';

/// True when [error] is a transient auth/token failure (missing/expired JWT)
/// rather than a genuine server reject. Kept identical to the offline queue's
/// classifier so both paths agree on what "auth" means.
bool isAuthReject(Object error) {
  if (error is AuthException) return true;
  if (error is PostgrestException) {
    final code = error.code ?? '';
    if (code == 'PGRST301' || code == 'PGRST302') return true;
    if (error.message.toLowerCase().contains('jwt')) return true;
  }
  return false;
}

/// Runs [run]; if it throws a transient auth reject ([isAuthReject]), refreshes
/// the session once via [refresh] and retries [run] exactly once. Any non-auth
/// error is rethrown immediately, untouched, so genuine server rejects keep
/// their existing handling. If [refresh] itself fails (the refresh token is
/// gone → truly signed out) the ORIGINAL auth error is rethrown with its stack,
/// not the refresh error, so callers still see the auth reject.
///
/// Safe for writes: the posting RPCs are idempotent on `client_op_id`, so if
/// the first attempt actually reached the server before the 401 was surfaced,
/// the retry is deduped rather than double-posted.
Future<T> withAuthRetry<T>(
  Future<T> Function() run, {
  required Future<void> Function() refresh,
  bool Function(Object)? isAuth,
}) async {
  final auth = isAuth ?? isAuthReject;
  try {
    return await run();
  } catch (error, stack) {
    if (!auth(error)) rethrow;
    try {
      await refresh();
    } catch (_) {
      // Refresh failed — surface the original auth reject (with its stack),
      // not the refresh error, so upstream classification is unchanged.
      Error.throwWithStackTrace(error, stack);
    }
    // Retry once with the (hopefully) fresh token. A second failure — auth or
    // otherwise — propagates to the caller's normal handling.
    return await run();
  }
}
