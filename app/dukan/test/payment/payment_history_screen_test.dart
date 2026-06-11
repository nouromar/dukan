import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/payment/payment_history_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

PaymentSummary _row({
  String paymentId = 'pay-1',
  double amount = 20,
  String direction = 'I',
  String? partyName = 'Ahmed',
  bool isRefund = false,
}) {
  return PaymentSummary(
    paymentId: paymentId,
    occurredAt: DateTime(2026, 6, 3, 14, 32),
    createdAt: DateTime(2026, 6, 3, 14, 32),
    amount: amount,
    direction: direction,
    partyId: partyName == null ? null : 'p-$paymentId',
    partyName: partyName,
    paymentMethodCode: 'cash',
    isRefund: isRefund,
  );
}

void main() {
  late FakeShopApi api;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    api = FakeShopApi();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(PaymentHistoryScreen(shop: shop), shopApi: api),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders inbound and outbound rows with arrow icons',
      (tester) async {
    api.onListPayments = (_, _, _) async => [
          _row(paymentId: 'p1', direction: 'I', partyName: 'Ahmed'),
          _row(paymentId: 'p2', direction: 'O', partyName: 'Acme Co'),
        ];

    await pump(tester);

    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(find.text('Ahmed'), findsOneWidget);
    expect(find.text('Acme Co'), findsOneWidget);
  });

  testWidgets('refund payments show the refund badge', (tester) async {
    api.onListPayments = (_, _, _) async => [
          _row(direction: 'O', partyName: 'Refund Customer', isRefund: true),
        ];

    await pump(tester);

    expect(find.text(en.paymentHistoryRefundBadge), findsOneWidget);
  });

  testWidgets('empty state renders the empty message', (tester) async {
    api.onListPayments = (_, _, _) async => const [];
    await pump(tester);
    expect(find.text(en.paymentHistoryEmptyMessage), findsOneWidget);
  });
}
