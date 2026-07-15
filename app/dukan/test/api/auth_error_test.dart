import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/auth_error.dart';

void main() {
  group('isAuthReject', () {
    test('AuthException is an auth reject', () {
      expect(isAuthReject(const AuthException('token expired')), isTrue);
    });

    test('PostgrestException PGRST301/302 (expired/missing JWT) is an auth reject', () {
      expect(isAuthReject(const PostgrestException(message: 'JWT expired', code: 'PGRST301')), isTrue);
      expect(isAuthReject(const PostgrestException(message: 'no JWT', code: 'PGRST302')), isTrue);
    });

    test('PostgrestException whose message mentions JWT is an auth reject', () {
      expect(isAuthReject(const PostgrestException(message: 'invalid JWT signature')), isTrue);
    });

    test('a genuine business reject is NOT an auth reject', () {
      expect(
        isAuthReject(const PostgrestException(message: 'insufficient stock', code: 'P0001')),
        isFalse,
      );
    });

    test('a non-Postgrest/non-Auth error is NOT an auth reject', () {
      expect(isAuthReject(Exception('socket closed')), isFalse);
    });
  });

  group('withAuthRetry', () {
    test('returns the result and never refreshes when the call succeeds', () async {
      var runs = 0, refreshes = 0;
      final out = await withAuthRetry<String>(
        () async { runs++; return 'ok'; },
        refresh: () async { refreshes++; },
      );
      expect(out, 'ok');
      expect(runs, 1);
      expect(refreshes, 0);
    });

    test('refreshes once and retries on an auth reject, then succeeds', () async {
      var runs = 0, refreshes = 0;
      final out = await withAuthRetry<String>(
        () async {
          runs++;
          if (runs == 1) throw const PostgrestException(message: 'JWT expired', code: 'PGRST301');
          return 'second';
        },
        refresh: () async { refreshes++; },
      );
      expect(out, 'second');
      expect(runs, 2);
      expect(refreshes, 1);
    });

    test('does NOT retry a genuine business reject', () async {
      var runs = 0, refreshes = 0;
      await expectLater(
        withAuthRetry<String>(
          () async { runs++; throw const PostgrestException(message: 'insufficient stock', code: 'P0001'); },
          refresh: () async { refreshes++; },
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(runs, 1);
      expect(refreshes, 0);
    });

    test('rethrows the ORIGINAL auth error when the refresh itself fails', () async {
      const original = PostgrestException(message: 'JWT expired', code: 'PGRST301');
      Object? caught;
      try {
        await withAuthRetry<String>(
          () async { throw original; },
          refresh: () async { throw StateError('refresh token gone'); },
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, same(original)); // not the StateError from refresh
    });

    test('propagates a second failure after the retry', () async {
      var runs = 0;
      await expectLater(
        withAuthRetry<String>(
          () async {
            runs++;
            throw const PostgrestException(message: 'JWT expired', code: 'PGRST301');
          },
          refresh: () async {},
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(runs, 2); // original + one retry, then gives up
    });
  });
}
