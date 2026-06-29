import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
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
        PaymentDetailScreen(shop: shop, paymentId: 'pay-1'),
        authController: auth,
        shopApi: api,
      ),
    );
    await tester.pumpAndSettle();
  }

  PaymentDetail payment({String direction = 'I', String? party = 'Ahmed'}) =>
      PaymentDetail(
        paymentId: 'pay-1',
        occurredAt: DateTime(2026, 6, 12),
        partyId: party == null ? null : 'p-1',
        partyName: party,
        direction: direction,
        amount: 50,
        paymentMethodCode: 'cash',
        notes: null,
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

  testWidgets('payment with no allocations shows the not-linked line', (
    tester,
  ) async {
    api.onGetPayment = (_, _) async => payment(direction: 'O', party: 'Hassan');
    api.onListPaymentAllocations = (_, _) async => const [];

    await pump(tester);

    expect(find.text(en.paymentOutLabel), findsOneWidget);
    expect(find.text(en.paymentDetailNoAllocations), findsOneWidget);
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
}
