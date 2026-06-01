import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/setup/shop_type_setup_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pumpSetup(WidgetTester tester, ShopSummary shop) async {
    await tester.pumpWidget(
      wrapWithApp(
        ShopTypeSetupScreen(shop: shop),
        authController: auth,
        shopApi: api,
      ),
    );
  }

  group('picker mode (setup_status: not_started)', () {
    final pickerShop = fakeShop(setupStatus: 'not_started');

    testWidgets('shows loading then templates list', (tester) async {
      api.onListAvailableTemplates = () async => [
        fakeTemplate(name: 'Grocery'),
        fakeTemplate(id: 't2', code: 'pharmacy', name: 'Pharmacy'),
      ];

      await pumpSetup(tester, pickerShop);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('Grocery'), findsOneWidget);
      expect(find.text('Pharmacy'), findsOneWidget);
    });

    testWidgets('shows empty message when no templates are available', (
      tester,
    ) async {
      api.onListAvailableTemplates = () async => const [];

      await pumpSetup(tester, pickerShop);
      await tester.pumpAndSettle();

      expect(find.text(en.templatesEmptyMessage), findsOneWidget);
    });

    testWidgets('USE THIS button is disabled until a template is selected', (
      tester,
    ) async {
      api.onListAvailableTemplates = () async => [fakeTemplate()];

      await pumpSetup(tester, pickerShop);
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.applyTemplateButton),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.text('Grocery'));
      await tester.pumpAndSettle();

      final after = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.applyTemplateButton),
      );
      expect(after.onPressed, isNotNull);
    });

    testWidgets('USE THIS calls applyTemplate then completeSetup', (
      tester,
    ) async {
      String? appliedTemplate;
      String? completedShop;
      api.onListAvailableTemplates =
          () async => [fakeTemplate(id: 't-grocery')];
      api.onApplyTemplate = (_, templateId) async {
        appliedTemplate = templateId;
      };
      api.onCompleteSetup = (shopId) async {
        completedShop = shopId;
      };

      await pumpSetup(tester, pickerShop);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grocery'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, en.applyTemplateButton));
      await tester.pumpAndSettle();

      expect(appliedTemplate, 't-grocery');
      expect(completedShop, pickerShop.id);
    });
  });

  group('resume mode (setup_status: template_applied)', () {
    final resumeShop = fakeShop(setupStatus: 'template_applied');

    testWidgets('shows "type chosen" card and FINISH SETUP button', (
      tester,
    ) async {
      await pumpSetup(tester, resumeShop);
      await tester.pumpAndSettle();

      expect(
        find.text(en.setupStepTemplateDone(resumeShop.name)),
        findsOneWidget,
      );
      expect(find.text(en.setupStepFinishButton), findsOneWidget);
    });

    testWidgets('FINISH SETUP calls completeSetup', (tester) async {
      String? completedShop;
      api.onCompleteSetup = (shopId) async {
        completedShop = shopId;
      };

      await pumpSetup(tester, resumeShop);
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(FilledButton, en.setupStepFinishButton),
      );
      await tester.pumpAndSettle();

      expect(completedShop, resumeShop.id);
    });
  });
}
