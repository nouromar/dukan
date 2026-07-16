import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/settings/settings_screen.dart';

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
    shop = fakeShop(
      name: 'Hodan Shop',
      currencyCode: 'USD',
      defaultLanguageCode: 'so',
      timezone: 'Africa/Mogadishu',
    );
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        SettingsScreen(shop: shop),
        authController: auth,
        shopApi: api,
      ),
    );
  }

  testWidgets('pre-fills form fields from the current shop', (tester) async {
    await pumpSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text('Hodan Shop'), findsOneWidget);
    expect(find.text('Africa/Mogadishu'), findsOneWidget);
  });

  testWidgets('save sends all four shop defaults to AuthController', (
    tester,
  ) async {
    Map<String, dynamic>? captured;
    api.onUpdateShopDefaults =
        (
          shopId, {
          name,
          currencyCode,
          defaultLanguageCode,
          timezone,
        }) async {
          captured = {
            'shopId': shopId,
            'name': name,
            'currencyCode': currencyCode,
            'defaultLanguageCode': defaultLanguageCode,
            'timezone': timezone,
          };
        };

    await pumpSettings(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, en.settingsSaveButton));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!['shopId'], shop.id);
    expect(captured!['name'], 'Hodan Shop');
    expect(captured!['currencyCode'], 'USD');
    expect(captured!['defaultLanguageCode'], 'so');
    expect(captured!['timezone'], 'Africa/Mogadishu');
  });

  testWidgets('currency is locked once the shop is set up', (tester) async {
    // fakeShop defaults setupStatus:'ready' — a set-up shop.
    await pumpSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.settingsCurrencyLockedHint), findsOneWidget);
    final currency = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).first,
    );
    expect(currency.onChanged, isNull,
        reason: 'currency dropdown disabled after setup');
  });

  testWidgets('currency stays editable before setup (not_started)', (
    tester,
  ) async {
    shop = fakeShop(setupStatus: 'not_started');
    await pumpSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.settingsCurrencyLockedHint), findsNothing);
    final currency = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).first,
    );
    expect(currency.onChanged, isNotNull,
        reason: 'currency editable pre-setup');
  });
}
