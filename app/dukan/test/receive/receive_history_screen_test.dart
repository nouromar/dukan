import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/receive/receive_history_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

ReceiveSummary _receive({
  String txnId = 'rcv-1',
  String partyName = 'Hodan Beverages',
  double total = 100,
  bool voided = false,
}) {
  return ReceiveSummary(
    txnId: txnId,
    occurredAt: DateTime(2026, 6, 3, 9, 15),
    postedAt: DateTime(2026, 6, 3, 9, 15),
    partyId: 'p-$txnId',
    partyName: partyName,
    totalAmount: total,
    paidAmount: 0,
    paymentMethodCode: null,
    isVoided: voided,
    reversalTxnId: voided ? 'reversal-$txnId' : null,
    voidedAt: voided ? DateTime(2026, 6, 3, 10, 0) : null,
  );
}

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

  Future<void> pumpHistory(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        ReceiveHistoryScreen(shop: shop),
        authController: auth,
        shopApi: api,
      ),
    );
  }

  testWidgets('renders bonos with supplier subtitle', (tester) async {
    api.onListReceives = (_, _, _) async => [
      _receive(txnId: 'r1', partyName: 'Hodan Beverages'),
      _receive(txnId: 'r2', partyName: 'Hassan Wholesaler'),
    ];

    await pumpHistory(tester);
    await tester.pumpAndSettle();

    expect(
      find.text(en.receiveHistorySupplierLabel('Hodan Beverages')),
      findsOneWidget,
    );
    expect(
      find.text(en.receiveHistorySupplierLabel('Hassan Wholesaler')),
      findsOneWidget,
    );
  });

  testWidgets('voided bonos show the voided badge', (tester) async {
    api.onListReceives = (_, _, _) async => [
      _receive(voided: true),
    ];

    await pumpHistory(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.receiveHistoryVoidedBadge), findsOneWidget);
  });

  testWidgets('empty list shows the empty message', (tester) async {
    api.onListReceives = (_, _, _) async => const [];

    await pumpHistory(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.receiveHistoryEmptyMessage), findsOneWidget);
  });

  testWidgets('list_receives load failure shows the failure message',
      (tester) async {
    api.onListReceives = (_, _, _) async => throw StateError('boom');

    await pumpHistory(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.receiveHistoryLoadFailedMessage), findsOneWidget);
  });
}
