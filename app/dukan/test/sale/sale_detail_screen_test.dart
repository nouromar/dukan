import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/sale/sale_detail_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

SaleSummary _header({
  String txnId = 'sale-1',
  String? partyName,
  double total = 12.5,
  double paid = 0,
  bool voided = false,
  DateTime? postedAt,
}) {
  return SaleSummary(
    txnId: txnId,
    occurredAt: DateTime(2026, 6, 3, 14, 32),
    postedAt: postedAt ?? DateTime.now(),
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

  Future<void> pumpDetail(WidgetTester tester, {String txnId = 'sale-1'}) async {
    await tester.pumpWidget(
      wrapWithApp(
        SaleDetailScreen(shop: shop, txnId: txnId),
        authController: auth,
        shopApi: api,
      ),
    );
  }

  testWidgets('renders lines + total + paid for a recent posted sale',
      (tester) async {
    api.onGetSale = (_, _) async => _header(
      partyName: 'Ahmed',
      total: 6.5,
      paid: 0,
    );
    api.onGetSaleLines = (_, _) async => const [
      SaleLineDetail(
        lineNo: 1,
        itemId: 'i1',
        itemName: 'Bariis',
        quantity: 3,
        unitLabel: 'kg',
        unitAmount: 1.5,
        lineTotal: 4.5,
      ),
      SaleLineDetail(
        lineNo: 2,
        itemId: 'i2',
        itemName: 'Sonkor',
        quantity: 2,
        unitLabel: 'kg',
        unitAmount: 1.0,
        lineTotal: 2.0,
      ),
    ];

    await pumpDetail(tester);
    await tester.pumpAndSettle();

    expect(find.text('Bariis'), findsOneWidget);
    expect(find.text('Sonkor'), findsOneWidget);
    expect(find.text(en.saleDetailTotalLabel), findsOneWidget);
    // VOID action available (posted within 7 days, not voided).
    expect(
      find.widgetWithText(TextButton, en.saleDetailVoidButton),
      findsOneWidget,
    );
  });

  testWidgets(
      'mixed sale shows time-of-sale cash + debt rows below total',
      (tester) async {
    api.onGetSale = (_, _) async => _header(
      partyName: 'Ahmed',
      total: 10,
      paid: 4,
    );
    api.onGetSaleLines = (_, _) async => const [];

    await pumpDetail(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.saleDetailCashLabel), findsOneWidget);
    expect(find.text(en.saleDetailDebtLabel), findsOneWidget);
    // Cash $4 + Debt $6 against a $10 total.
    expect(find.text('\$4'), findsOneWidget);
    expect(find.text('\$6'), findsOneWidget);
  });

  testWidgets('voided sale shows banner + hides VOID button', (tester) async {
    api.onGetSale = (_, _) async => _header(
      partyName: 'Ahmed',
      total: 6.5,
      voided: true,
    );
    api.onGetSaleLines = (_, _) async => const [];

    await pumpDetail(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.saleDetailVoidedHeader), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, en.saleDetailVoidButton),
      findsNothing,
    );
  });

  testWidgets('outside 7-day window hides the VOID button', (tester) async {
    api.onGetSale = (_, _) async => _header(
      partyName: 'Ahmed',
      postedAt: DateTime.now().subtract(const Duration(days: 8)),
    );
    api.onGetSaleLines = (_, _) async => const [];

    await pumpDetail(tester);
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextButton, en.saleDetailVoidButton),
      findsNothing,
    );
  });

  testWidgets(
    'refund checkbox + adjustable amount → voidSale called with refundAmount',
    (tester) async {
      // Mixed sale: $10 total, $6 paid in cash. Default refund = $6,
      // cashier adjusts to $4.
      api.onGetSale = (_, _) async => _header(
        partyName: 'Ahmed',
        total: 10,
        paid: 6,
      );
      api.onGetSaleLines = (_, _) async => const [
        SaleLineDetail(
          lineNo: 1,
          itemId: 'i1',
          itemName: 'Bariis',
          quantity: 1,
          unitLabel: 'kg',
          unitAmount: 10,
          lineTotal: 10,
        ),
      ];
      num? capturedRefund;
      api.onVoidSale = (_, _, _, refundAmount) async {
        capturedRefund = refundAmount;
        return 'rev-id';
      };

      await pumpDetail(tester);
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(TextButton, en.saleDetailVoidButton),
      );
      await tester.pumpAndSettle();

      // Refund checkbox is on by default because paid > 0, default
      // refund = paid amount (\$6).
      expect(find.byType(Checkbox), findsOneWidget);
      // Cashier overrides to \$4.
      await tester.enterText(find.byType(TextField), '4');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, en.saleVoidConfirmYes),
      );
      await tester.pumpAndSettle();

      expect(capturedRefund, 4);
    },
  );

  testWidgets(
    'refund > paid blocks the confirm button',
    (tester) async {
      api.onGetSale = (_, _) async => _header(
        partyName: 'Ahmed',
        total: 10,
        paid: 6,
      );
      api.onGetSaleLines = (_, _) async => const [];

      await pumpDetail(tester);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(TextButton, en.saleDetailVoidButton),
      );
      await tester.pumpAndSettle();

      // Type a refund > paid.
      await tester.enterText(find.byType(TextField), '10');
      await tester.pump();

      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.saleVoidConfirmYes),
      );
      expect(confirm.onPressed, isNull);
    },
  );

  testWidgets('VOID flow: tap → confirm → voidSale called, pops with true',
      (tester) async {
    api.onGetSale = (_, _) async => _header(partyName: 'Ahmed');
    api.onGetSaleLines = (_, _) async => const [
      SaleLineDetail(
        lineNo: 1,
        itemId: 'i1',
        itemName: 'Bariis',
        quantity: 1,
        unitLabel: 'kg',
        unitAmount: 12.5,
        lineTotal: 12.5,
      ),
    ];
    String? capturedTxnId;
    api.onVoidSale = (_, txnId, _, _) async {
      capturedTxnId = txnId;
      return 'rev-id';
    };

    // Host that launches the detail screen so we can read what it pops.
    bool? poppedWith;
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) =>
                          SaleDetailScreen(shop: shop, txnId: 'sale-1'),
                    ),
                  );
                  poppedWith = result;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        authController: auth,
        shopApi: api,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(TextButton, en.saleDetailVoidButton),
    );
    await tester.pumpAndSettle();
    // Confirm dialog.
    expect(find.text(en.saleVoidConfirmTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, en.saleVoidConfirmYes));
    await tester.pumpAndSettle();

    expect(capturedTxnId, 'sale-1');
    expect(poppedWith, isTrue);
  });
}
