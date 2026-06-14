import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/auth/otp_verification_screen.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController(pendingPhone: '+252612345678');
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pumpOtp(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(const OtpVerificationScreen(), authController: auth),
    );
  }

  testWidgets('renders the pending phone in the body', (tester) async {
    await pumpOtp(tester);

    expect(
      find.text(en.verifyOtpBody('+252612345678')),
      findsOneWidget,
    );
  });

  testWidgets('VERIFY calls AuthController.verifyOtp with the entered code', (
    tester,
  ) async {
    String? capturedToken;
    auth.onVerifyOtp = (token) async {
      capturedToken = token;
    };

    await pumpOtp(tester);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.widgetWithText(FilledButton, en.verifyOtpButton));
    await tester.pumpAndSettle();

    expect(capturedToken, '123456');
  });

  testWidgets('AuthException shows the wrong/expired code snackbar', (
    tester,
  ) async {
    auth.onVerifyOtp = (_) async {
      throw const AuthException('invalid');
    };

    await pumpOtp(tester);
    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.widgetWithText(FilledButton, en.verifyOtpButton));
    await tester.pump();

    expect(find.text(en.verifyOtpFailedMessage), findsOneWidget);
  });

  testWidgets('"change phone number" clears the pending phone', (tester) async {
    await pumpOtp(tester);

    expect(auth.pendingPhone, '+252612345678');
    await tester.tap(find.widgetWithText(TextButton, en.changePhoneButton));
    await tester.pumpAndSettle();

    expect(auth.pendingPhone, isNull);
  });

  group('email path', () {
    setUp(() {
      auth = FakeAuthController(pendingEmail: 'owner@example.com');
    });

    testWidgets('renders the pending email in the body', (tester) async {
      await pumpOtp(tester);

      expect(
        find.text(en.verifyOtpBodyEmail('owner@example.com')),
        findsOneWidget,
      );
      expect(find.text(en.verifyOtpHeadlineEmail), findsOneWidget);
    });

    testWidgets('"change email" clears the pending email', (tester) async {
      await pumpOtp(tester);

      expect(auth.pendingEmail, 'owner@example.com');
      await tester.tap(find.widgetWithText(TextButton, en.changeEmailButton));
      await tester.pumpAndSettle();

      expect(auth.pendingEmail, isNull);
    });
  });
}
