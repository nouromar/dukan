import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/shared/party_picker_sheet.dart';

import 'fakes.dart';
import 'wrap.dart';

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    en = lookupAppLocalizations(const Locale('en'));
  });

  /// Pump a scaffold whose body has a button that opens the picker sheet.
  /// Returns a function that lets the test read what showPartyPicker
  /// resolved to after the sheet was dismissed.
  Future<PartySearchResult? Function()> pumpHostAndOpenSheet(
    WidgetTester tester,
  ) async {
    PartySearchResult? captured;
    var opened = false;
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  final result =
                      await showPartyPicker(context, shop: fakeShop(), typeCode: 'customer');
                  captured = result;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        authController: auth, shopApi: api,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    opened = true;
    expect(opened, isTrue);
    return () => captured;
  }

  testWidgets('lists customers from searchParties with debt label', (
    tester,
  ) async {
    api.onSearchParties = (_, _, type, _) async {
      expect(type, 'customer');
      return [
        fakeCustomer(name: 'Ahmed', receivable: 12.5),
        fakeCustomer(id: 'p2', name: 'Asha', receivable: 0),
      ];
    };

    await pumpHostAndOpenSheet(tester);

    expect(find.text('Ahmed'), findsOneWidget);
    expect(find.text(en.customerPickerOwesLabel('\$12.50')), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text(en.customerPickerNoDebtLabel), findsOneWidget);
  });

  testWidgets('tapping a customer pops the sheet and returns that party', (
    tester,
  ) async {
    api.onSearchParties = (_, _, _, _) async => [
      fakeCustomer(name: 'Ahmed', receivable: 12.5),
    ];

    final readResult = await pumpHostAndOpenSheet(tester);
    await tester.tap(find.text('Ahmed'));
    await tester.pumpAndSettle();

    final captured = readResult();
    expect(captured, isNotNull);
    expect(captured!.name, 'Ahmed');
  });

  testWidgets('shows empty message when no customers and no query', (
    tester,
  ) async {
    api.onSearchParties = (_, _, _, _) async => const [];

    await pumpHostAndOpenSheet(tester);

    expect(find.text(en.customerPickerEmptyMessage), findsOneWidget);
  });

  testWidgets(
    '+ NEW CUSTOMER opens the add-party sheet and auto-selects on save',
    (tester) async {
      api.onSearchParties = (_, _, _, _) async => const [];
      String? capturedType;
      api.onCreateParty = (shopId, name, phone, typeCode) async {
        capturedType = typeCode;
        return 'new-party-123';
      };

      final readResult = await pumpHostAndOpenSheet(tester);
      await tester.tap(find.text(en.customerNewButton));
      await tester.pumpAndSettle();

      // Form shown — name field labelled and focused.
      expect(find.text(en.partyNewCustomerTitle), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, en.partyNewNameLabel),
        'Ahmed',
      );
      await tester.tap(find.widgetWithText(FilledButton, en.partyNewSaveButton));
      await tester.pumpAndSettle();

      // Created as a customer; auto-selected (returned from the picker).
      expect(capturedType, 'customer');
      final picked = readResult();
      expect(picked, isNotNull);
      expect(picked!.id, 'new-party-123');
      expect(picked.name, 'Ahmed');
      expect(picked.typeCode, 'customer');
    },
  );

  testWidgets('+ NEW CUSTOMER empty name shows a validation message', (
    tester,
  ) async {
    api.onSearchParties = (_, _, _, _) async => const [];

    await pumpHostAndOpenSheet(tester);
    await tester.tap(find.text(en.customerNewButton));
    await tester.pumpAndSettle();
    // Tap SAVE without entering a name.
    await tester.tap(find.widgetWithText(FilledButton, en.partyNewSaveButton));
    await tester.pumpAndSettle();

    expect(find.text(en.partyNewNameRequiredMessage), findsOneWidget);
  });

  // The provider has to follow the sheet through the root Navigator. This
  // is a regression guard for the bug class we hit in the OTP/template
  // crashes.
  testWidgets('sheet sees AuthController via .value re-export', (tester) async {
    api.onSearchParties = (_, _, _, _) async => [fakeCustomer()];

    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showPartyPicker(context, shop: fakeShop(), typeCode: 'customer'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        authController: auth, shopApi: api,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // If the provider weren't in scope the sheet would have thrown; instead
    // the searchParties call succeeded and rendered.
    expect(find.byType(Provider).evaluate, isNotNull);
    expect(find.text('Ahmed'), findsOneWidget);
  });
}
