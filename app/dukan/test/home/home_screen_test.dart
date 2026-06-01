import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/home/home_screen.dart';
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

  testWidgets('renders the shop chip + four daily actions when a shop is selected', (
    tester,
  ) async {
    final shop = fakeShop(name: 'Hodan Shop');

    await tester.pumpWidget(
      wrapWithApp(
        HomeScreen(shop: shop, onSignOut: () {}),
        authController: auth,
      ),
    );

    expect(find.text(en.activeShopLabel('Hodan Shop')), findsOneWidget);
    expect(find.text(en.sale), findsOneWidget);
    expect(find.text(en.receive), findsOneWidget);
    expect(find.text(en.payment), findsOneWidget);
    expect(find.text(en.expense), findsOneWidget);
  });

  testWidgets('settings + sign-out icons appear when shop and onSignOut are set', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(
        HomeScreen(shop: fakeShop(), onSignOut: () {}),
        authController: auth,
      ),
    );

    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.byIcon(Icons.logout), findsOneWidget);
  });

  testWidgets('sign-out icon hidden when onSignOut is null', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        HomeScreen(shop: fakeShop()),
        authController: auth,
      ),
    );

    expect(find.byIcon(Icons.logout), findsNothing);
  });
}
