import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/products/catalog_picker_screen.dart';
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

  testWidgets('renders the three onboarding cards + skip button', (
    tester,
  ) async {
    await pumpOnboarding(tester);

    expect(find.text(en.setupOnboardingAddItemsTitle), findsOneWidget);
    expect(find.text(en.setupOnboardingSetPricesTitle), findsOneWidget);
    expect(find.text(en.setupOnboardingBrowseCatalogTitle), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, en.setupOnboardingSkipButton),
      findsOneWidget,
    );
  });

  testWidgets(
    'tap SKIP calls dismissOnboarding(shopId) and refreshSelectedShop',
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

  testWidgets(
    'tapping "Browse the catalog" pushes the catalog screen AND dismisses on return',
    (tester) async {
      await pumpOnboarding(tester);

      // Tap the browse-catalog card.
      await tester.tap(find.text(en.setupOnboardingBrowseCatalogTitle));
      await tester.pumpAndSettle();

      // The catalog picker is mounted.
      expect(find.byType(CatalogPickerScreen), findsOneWidget);

      // Pop back to the onboarding screen — the onboarding screen
      // then dismisses + refreshes.
      Navigator.of(tester.element(find.byType(CatalogPickerScreen))).pop();
      await tester.pumpAndSettle();

      expect(api.dismissOnboardingCalls, [shop.id]);
      expect(auth.refreshSelectedShopCalls, 1);
    },
  );
}
