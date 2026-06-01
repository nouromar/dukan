import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/auth/owner_onboarding_screen.dart';
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

  Future<void> pumpOnboarding(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(const OwnerOnboardingScreen(), authController: auth),
    );
  }

  testWidgets('CREATE SHOP passes both names to AuthController', (tester) async {
    String? businessName;
    String? shopName;
    auth.onCreateFirstShop = (b, s) async {
      businessName = b;
      shopName = s;
    };

    await pumpOnboarding(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Hodan Trading');
    await tester.enterText(fields.at(1), 'Main Shop');
    await tester.tap(find.widgetWithText(FilledButton, en.createShopButton));
    await tester.pumpAndSettle();

    expect(businessName, 'Hodan Trading');
    expect(shopName, 'Main Shop');
  });

  testWidgets('missing names surfaces the action-oriented snackbar', (
    tester,
  ) async {
    auth.onCreateFirstShop = (_, _) async {
      throw const AuthInputException(AuthInputIssue.missingShopNames);
    };

    await pumpOnboarding(tester);
    await tester.tap(find.widgetWithText(FilledButton, en.createShopButton));
    await tester.pump();

    expect(find.text(en.missingShopNamesMessage), findsOneWidget);
  });
}
