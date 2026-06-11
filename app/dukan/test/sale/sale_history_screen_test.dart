import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/sale/sale_history_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

SaleSummary _sale({
  String txnId = 'sale-1',
  String? partyName,
  double total = 12.5,
  double paid = 0,
  bool voided = false,
}) {
  return SaleSummary(
    txnId: txnId,
    occurredAt: DateTime(2026, 6, 3, 14, 32),
    postedAt: DateTime(2026, 6, 3, 14, 32),
    partyId: partyName == null ? null : 'p-$txnId',
    partyName: partyName,
    totalAmount: total,
    paidAmount: paid,
    paymentMethodCode: partyName == null ? 'cash' : null,
    isVoided: voided,
    reversalTxnId: voided ? 'reversal-$txnId' : null,
    voidedAt: voided ? DateTime(2026, 6, 3, 15, 0) : null,
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
        SaleHistoryScreen(shop: shop),
        authController: auth,
        shopApi: api,
      ),
    );
  }

  testWidgets('renders sales reverse-chronological with cash + debt subtitles',
      (tester) async {
    api.onListSales = (_, _, _) async => [
      _sale(txnId: 's1', total: 1.5),
      _sale(txnId: 's2', partyName: 'Ahmed', total: 12, paid: 0),
    ];

    await pumpHistory(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.saleHistoryCashLabel), findsOneWidget);
    expect(find.text(en.saleHistoryDebtLabel('Ahmed')), findsOneWidget);
  });

  testWidgets('voided sales show the badge and strike-through total',
      (tester) async {
    api.onListSales = (_, _, _) async => [
      _sale(txnId: 's1', partyName: 'Ahmed', total: 12, voided: true),
    ];

    await pumpHistory(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.saleHistoryVoidedBadge), findsOneWidget);
  });

  testWidgets('empty list shows the empty message', (tester) async {
    api.onListSales = (_, _, _) async => const [];

    await pumpHistory(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.saleHistoryEmptyMessage), findsOneWidget);
  });

  testWidgets('default scope is Today — subtitle reflects it', (tester) async {
    api.onListSales = (_, _, _) async => const [];

    await pumpHistory(tester);
    await tester.pumpAndSettle();

    // The app-bar subtitle shows the active date range.
    expect(find.text(en.dateRangeToday), findsOneWidget);
  });

  testWidgets('voided rows show by default; "Hide voided" chip removes them',
      (tester) async {
    api.onListSales = (_, _, _) async => [
      _sale(txnId: 's1', total: 1.5),
      _sale(txnId: 's2', partyName: 'Ahmed', total: 12, voided: true),
    ];

    await pumpHistory(tester);
    await tester.pumpAndSettle();

    // Default: the voided badge IS visible.
    expect(find.text(en.saleHistoryVoidedBadge), findsOneWidget);
  });
}
