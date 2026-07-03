import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/capabilities.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/payment/payment_detail_screen.dart';
import 'package:dukan/sale/sale_detail_screen.dart';

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
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        PaymentDetailScreen(shop: shop, paymentId: '00000000-0000-4000-8000-0000000000a1'),
        authController: auth,
        shopApi: api,
      ),
    );
    await tester.pumpAndSettle();
  }

  PaymentDetail payment({
    String direction = 'I',
    String? party = 'Ahmed',
    DateTime? createdAt,
    bool isVoided = false,
    bool isRefund = false,
    bool isSettlementLeg = false,
  }) =>
      PaymentDetail(
        paymentId: '00000000-0000-4000-8000-0000000000a1',
        occurredAt: DateTime(2026, 6, 12),
        createdAt: createdAt ?? DateTime.now(),
        partyId: party == null ? null : 'p-1',
        partyName: party,
        direction: direction,
        amount: 50,
        paymentMethodCode: 'cash',
        notes: null,
        isVoided: isVoided,
        isRefund: isRefund,
        isSettlementLeg: isSettlementLeg,
      );

  PostedAllocation saleAllocation() => PostedAllocation(
    transactionId: 'txn-1',
    amount: 20,
    occurredAt: DateTime(2026, 6, 10),
    txnType: 'sale',
  );

  testWidgets('inbound payment shows Money In, party, amount + settled sale', (
    tester,
  ) async {
    api.onGetPayment = (_, _) async => payment();
    api.onListPaymentAllocations = (_, _) async => [saleAllocation()];

    await pump(tester);

    expect(find.text(en.paymentInLabel), findsOneWidget);
    expect(find.text('Ahmed'), findsOneWidget);
    expect(find.text('\$50.00'), findsOneWidget); // payment amount
    expect(find.text(en.paymentDetailSettledHeader), findsOneWidget);
    expect(find.text('\$20.00'), findsOneWidget); // settled sale amount
  });

  testWidgets('party payment with no loaded allocations shows the plain '
      'effect line (never the old "not linked" jargon)', (
    tester,
  ) async {
    api.onGetPayment = (_, _) async => payment(direction: 'O', party: 'Hassan');
    api.onListPaymentAllocations = (_, _) async => const [];

    await pump(tester);

    expect(find.text(en.paymentOutLabel), findsOneWidget);
    // Money Out → "Reduced what you owe Hassan by $50.00."
    expect(
      find.text(en.paymentEffectOut('Hassan', '\$50.00')),
      findsOneWidget,
    );
  });

  testWidgets('tapping a settled sale opens its sale detail', (tester) async {
    api.onGetPayment = (_, _) async => payment();
    api.onListPaymentAllocations = (_, _) async => [saleAllocation()];
    api.onGetSale = (_, txnId) async => SaleSummary(
      txnId: txnId,
      occurredAt: DateTime(2026, 6, 10),
      postedAt: DateTime(2026, 6, 10),
      partyId: 'p-1',
      partyName: 'Ahmed',
      totalAmount: 20,
      paidAmount: 20,
      paymentMethodCode: null,
      isVoided: false,
      reversalTxnId: null,
      voidedAt: null,
    );
    api.onGetSaleLines = (_, _) async => const [];

    await pump(tester);
    await tester.tap(find.text('\$20.00'));
    await tester.pumpAndSettle();

    expect(find.byType(SaleDetailScreen), findsOneWidget);
  });

  group('void gating', () {
    setUp(() {
      auth = FakeAuthController(
        capabilities: Capabilities.forTesting(const ['payment.void']),
      );
    });

    testWidgets('owner within window sees VOID → confirm posts void_payment',
        (tester) async {
      api.onGetPayment = (_, _) async => payment();
      api.onListPaymentAllocations = (_, _) async => [saleAllocation()];
      await pump(tester);
      expect(find.text(en.paymentDetailVoidButton), findsOneWidget);
      await tester.tap(find.text(en.paymentDetailVoidButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.paymentVoidConfirmYes));
      await tester.pumpAndSettle();
      expect(api.voidPaymentCalls, contains('00000000-0000-4000-8000-0000000000a1'));
    });

    testWidgets('cashier without payment.void sees no VOID', (tester) async {
      auth = FakeAuthController(capabilities: Capabilities.forTesting(const []));
      api.onGetPayment = (_, _) async => payment();
      api.onListPaymentAllocations = (_, _) async => const [];
      await pump(tester);
      expect(find.text(en.paymentDetailVoidButton), findsNothing);
    });

    testWidgets('refund leg shows no VOID', (tester) async {
      api.onGetPayment = (_, _) async => payment(isRefund: true);
      api.onListPaymentAllocations = (_, _) async => const [];
      await pump(tester);
      expect(find.text(en.paymentDetailVoidButton), findsNothing);
    });

    testWidgets('at-till settlement leg shows no VOID + "From a cash sale"',
        (tester) async {
      api.onGetPayment = (_, _) async => payment(isSettlementLeg: true);
      api.onListPaymentAllocations = (_, _) async => const [];
      await pump(tester);
      expect(find.text(en.paymentDetailVoidButton), findsNothing);
      // Inbound leg → framed as the cash from a sale, not a "Paid for" list.
      expect(find.text(en.paymentFromSaleHeader), findsOneWidget);
      expect(find.text(en.paymentDetailSettledHeader), findsNothing);
    });

    testWidgets('already voided shows banner + no VOID', (tester) async {
      api.onGetPayment = (_, _) async => payment(isVoided: true);
      api.onListPaymentAllocations = (_, _) async => const [];
      await pump(tester);
      expect(find.text(en.paymentVoidedHeader), findsOneWidget);
      expect(find.text(en.paymentDetailVoidButton), findsNothing);
    });

    testWidgets('outside window shows the window-passed hint, no VOID',
        (tester) async {
      api.onGetPayment =
          (_, _) async => payment(createdAt: DateTime(2020, 1, 1));
      api.onListPaymentAllocations = (_, _) async => const [];
      await pump(tester);
      expect(find.text(en.paymentDetailVoidButton), findsNothing);
      expect(find.text(en.paymentVoidWindowPassedHint), findsOneWidget);
    });
  });
}
