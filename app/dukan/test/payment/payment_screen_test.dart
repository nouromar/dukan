import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/payment/payment_controller.dart';
import 'package:dukan/payment/payment_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

PartySearchResult _ahmed() => const PartySearchResult(
  id: 'cust-1',
  name: 'Ahmed',
  phone: null,
  typeCode: 'customer',
  receivable: 40,
  payable: 0,
);

PartySearchResult _hassan() => const PartySearchResult(
  id: 'sup-1',
  name: 'Hassan',
  phone: null,
  typeCode: 'supplier',
  receivable: 0,
  payable: 120,
);

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late PaymentController payment;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    payment = PaymentController();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pumpPayment(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        PaymentScreen(shop: shop),
        authController: auth,
        shopApi: api,
        paymentController: payment,
      ),
    );
  }

  testWidgets(
    'customer → SAVE posts inbound payment with direction I',
    (tester) async {
      api.onSearchParties = (_, _, _, _) async => [_ahmed()];
      Map<String, dynamic>? captured;
      api.onPostPayment = (
        shopId,
        partyId,
        direction,
        amount,
        methodCode,
        clientOpId,
        notes,
      ) async {
        captured = {
          'partyId': partyId,
          'direction': direction,
          'amount': amount,
          'methodCode': methodCode,
        };
        return 'fake-payment';
      };

      await pumpPayment(tester);
      await tester.pumpAndSettle();

      // Default type is customer; pick Ahmed from the sheet.
      await tester.tap(find.text(en.paymentPickCustomerButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ahmed'));
      await tester.pumpAndSettle();

      // Type the amount (\$20 of the \$40 they owe).
      await tester.enterText(find.byType(TextField), '20');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, en.paymentSaveButton));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!['partyId'], 'cust-1');
      expect(captured!['direction'], 'I');
      expect(captured!['amount'], 20);
      expect(captured!['methodCode'], 'cash');
    },
  );

  testWidgets(
    'supplier → SAVE posts outbound payment with direction O',
    (tester) async {
      api.onSearchParties = (_, _, type, _) async {
        expect(type, 'supplier');
        return [_hassan()];
      };
      Map<String, dynamic>? captured;
      api.onPostPayment = (
        shopId,
        partyId,
        direction,
        amount,
        methodCode,
        clientOpId,
        notes,
      ) async {
        captured = {'partyId': partyId, 'direction': direction, 'amount': amount};
        return 'fake-payment';
      };

      await pumpPayment(tester);
      await tester.pumpAndSettle();

      // Flip to supplier mode.
      await tester.tap(find.text(en.paymentTypeSupplier));
      await tester.pumpAndSettle();

      await tester.tap(find.text(en.paymentPickSupplierButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hassan'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '50');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, en.paymentSaveButton));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!['partyId'], 'sup-1');
      expect(captured!['direction'], 'O');
      expect(captured!['amount'], 50);
    },
  );

  testWidgets('SAVE disabled until party + positive amount are set', (
    tester,
  ) async {
    await pumpPayment(tester);
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, en.paymentSaveButton),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets(
    'amount exceeding outstanding balance surfaces an error',
    (tester) async {
      api.onSearchParties = (_, _, _, _) async => [_ahmed()];
      var postCalled = false;
      api.onPostPayment = (_, _, _, _, _, _, _) async {
        postCalled = true;
        return 'should-not-happen';
      };

      await pumpPayment(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.paymentPickCustomerButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ahmed'));
      await tester.pumpAndSettle();

      // Type more than Ahmed's \$40 balance.
      await tester.enterText(find.byType(TextField), '100');
      await tester.pump();

      // SAVE should be disabled because amount > balance.
      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.paymentSaveButton),
      );
      expect(saveButton.onPressed, isNull);
      expect(postCalled, isFalse);
    },
  );

  testWidgets(
    'switching type clears the selected party (defensive)',
    (tester) async {
      api.onSearchParties = (_, _, _, _) async => [_ahmed()];

      await pumpPayment(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.paymentPickCustomerButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ahmed'));
      await tester.pumpAndSettle();

      // Ahmed should now be selected as the customer.
      expect(payment.party?.id, 'cust-1');

      // Flip to supplier — the customer-typed party can't carry over.
      await tester.tap(find.text(en.paymentTypeSupplier));
      await tester.pumpAndSettle();
      expect(payment.party, isNull);
      // Supplier-pick button is now visible (no party selected yet).
      expect(find.text(en.paymentPickSupplierButton), findsOneWidget);
    },
  );
}
