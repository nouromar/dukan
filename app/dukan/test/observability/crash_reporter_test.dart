import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/config/app_config.dart';
import 'package:dukan/observability/crash_reporter.dart';

void main() {
  group('AppConfig.hasSentry', () {
    test('false when DSN is empty', () {
      const cfg = AppConfig(
        supabaseUrl: '',
        supabaseAnonKey: '',
        sentryDsn: '',
        appEnvironment: '',
        appVersion: '',
      );
      expect(cfg.hasSentry, isFalse);
    });

    test('false when DSN is whitespace-only', () {
      const cfg = AppConfig(
        supabaseUrl: '',
        supabaseAnonKey: '',
        sentryDsn: '   ',
        appEnvironment: '',
        appVersion: '',
      );
      expect(cfg.hasSentry, isFalse);
    });

    test('true when DSN is provided', () {
      const cfg = AppConfig(
        supabaseUrl: '',
        supabaseAnonKey: '',
        sentryDsn: 'https://example@sentry.io/123',
        appEnvironment: 'dev',
        appVersion: '1.0.0',
      );
      expect(cfg.hasSentry, isTrue);
    });
  });

  group('CrashReporter (no-op when disabled)', () {
    // Most test runs don't have Sentry installed. The wrapper must be
    // safe to call from anywhere — setUser, clearUser, reportError
    // must not throw and must not require the SDK to be initialised.
    test('isEnabled defaults to false', () {
      expect(CrashReporter.isEnabled, isFalse);
    });

    test('setUser is a no-op when disabled', () {
      expect(
        () => CrashReporter.setUser(userId: 'u1', shopId: 's1'),
        returnsNormally,
      );
    });

    test('clearUser is a no-op when disabled', () {
      expect(() => CrashReporter.clearUser(), returnsNormally);
    });

    test('reportError is a no-op when disabled', () async {
      await expectLater(
        CrashReporter.reportError(
          StateError('test'),
          StackTrace.current,
          hint: 'unit test',
        ),
        completes,
      );
    });
  });
}
