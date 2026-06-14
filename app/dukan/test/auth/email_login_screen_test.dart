import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/auth/email_login_screen.dart';
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

  Future<void> pumpForm(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        const Scaffold(body: EmailLoginForm()),
        authController: auth,
      ),
    );
  }

  testWidgets('SEND CODE calls AuthController.sendEmailOtp with the typed email',
      (tester) async {
    String? captured;
    auth.onSendEmailOtp = (rawEmail) async {
      captured = rawEmail;
    };

    await pumpForm(tester);
    await tester.enterText(find.byType(TextField), 'owner@example.com');
    await tester.tap(find.widgetWithText(FilledButton, en.sendEmailOtpButton));
    await tester.pumpAndSettle();

    expect(captured, 'owner@example.com');
  });

  testWidgets('invalidEmail AuthInputException surfaces the invalid-email message',
      (tester) async {
    auth.onSendEmailOtp = (_) async {
      throw const AuthInputException(AuthInputIssue.invalidEmail);
    };

    await pumpForm(tester);
    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.widgetWithText(FilledButton, en.sendEmailOtpButton));
    await tester.pump();

    expect(find.text(en.invalidEmailMessage), findsOneWidget);
  });

  testWidgets('Supabase "not allowed" error surfaces the no-account message',
      (tester) async {
    auth.onSendEmailOtp = (_) async {
      throw const AuthException('Signups not allowed for otp');
    };

    await pumpForm(tester);
    await tester.enterText(find.byType(TextField), 'stranger@example.com');
    await tester.tap(find.widgetWithText(FilledButton, en.sendEmailOtpButton));
    await tester.pump();

    expect(find.text(en.emailAccountNotFoundMessage), findsOneWidget);
  });

  testWidgets('other AuthException surfaces the generic email-send failed message',
      (tester) async {
    auth.onSendEmailOtp = (_) async {
      throw const AuthException('upstream down');
    };

    await pumpForm(tester);
    await tester.enterText(find.byType(TextField), 'owner@example.com');
    await tester.tap(find.widgetWithText(FilledButton, en.sendEmailOtpButton));
    await tester.pump();

    expect(find.text(en.sendEmailOtpFailedMessage), findsOneWidget);
  });
}
