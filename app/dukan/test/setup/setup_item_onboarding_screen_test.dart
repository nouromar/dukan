import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/setup/setup_item_onboarding_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    // Onboarding screen is for shops that have not yet dismissed.
    shop = fakeShop(onboardingDismissedAt: null);
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pumpOnboarding(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        SetupItemOnboardingScreen(shop: shop),
        authController: auth,
        shopApi: api,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the getting-started instructions + start button', (
    tester,
  ) async {
    await pumpOnboarding(tester);

    expect(find.text(en.setupGuideIntro), findsOneWidget);
    expect(find.text(en.setupGuideStep1Title), findsOneWidget);
    expect(find.text(en.setupGuideStep2Title), findsOneWidget);
    expect(find.text(en.setupGuideStep3Title), findsOneWidget);
    expect(find.text(en.setupGuideStep4Title), findsOneWidget);
    expect(find.text(en.setupGuideFootnote), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, en.setupOnboardingSkipButton),
      findsOneWidget,
    );
    // Pure instructions — no tappable navigation cards (the old cards had a
    // trailing chevron; the numbered steps don't).
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets(
    'tap START SELLING calls dismissOnboarding(shopId) and refreshSelectedShop',
    (tester) async {
      await pumpOnboarding(tester);

      await tester.tap(
        find.widgetWithText(FilledButton, en.setupOnboardingSkipButton),
      );
      await tester.pumpAndSettle();

      expect(api.dismissOnboardingCalls, [shop.id]);
      expect(auth.refreshSelectedShopCalls, 1);
    },
  );

  testWidgets('guide mode (from the menu): GOT IT closes without dismissing', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(
        // A host with a button that pushes the guide, so we can verify it pops.
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SetupItemOnboardingScreen(shop: shop, asGuide: true),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        authController: auth,
        shopApi: api,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Guide shows the steps + a GOT IT button (not START SELLING).
    expect(find.text(en.setupGuideStep1Title), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, en.setupGuideDoneButton),
    );
    await tester.pumpAndSettle();

    // Popped back to the host; onboarding was NOT dismissed.
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(SetupItemOnboardingScreen), findsNothing);
    expect(api.dismissOnboardingCalls, isEmpty);
  });
}
