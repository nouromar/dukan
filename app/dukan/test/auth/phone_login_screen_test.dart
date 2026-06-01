import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/auth/phone_login_screen.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(const PhoneLoginScreen(), authController: auth),
    );
  }

  testWidgets('SEND CODE calls AuthController.sendOtp with the entered phone', (
    tester,
  ) async {
    String? captured;
    auth.onSendOtp = (rawPhone) async {
      captured = rawPhone;
    };

    await pumpLogin(tester);
    await tester.enterText(find.byType(TextField), '+252612345678');
    await tester.tap(find.widgetWithText(FilledButton, en.sendOtpButton));
    await tester.pumpAndSettle();

    expect(captured, '+252612345678');
  });

  testWidgets('AuthInputException surfaces an actionable error snackbar', (
    tester,
  ) async {
    auth.onSendOtp = (_) async {
      throw const AuthInputException(AuthInputIssue.invalidPhone);
    };

    await pumpLogin(tester);
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.widgetWithText(FilledButton, en.sendOtpButton));
    await tester.pump();

    expect(find.text(en.invalidPhoneMessage), findsOneWidget);
  });

  testWidgets('AuthException shows the generic OTP-send failed message', (
    tester,
  ) async {
    auth.onSendOtp = (_) async {
      throw const AuthException('upstream down');
    };

    await pumpLogin(tester);
    await tester.enterText(find.byType(TextField), '+252612345678');
    await tester.tap(find.widgetWithText(FilledButton, en.sendOtpButton));
    await tester.pump();

    expect(find.text(en.sendOtpFailedMessage), findsOneWidget);
  });
}
