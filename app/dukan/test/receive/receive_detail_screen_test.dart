import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/auth/capabilities.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/receive/receive_detail_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

ReceiveSummary _header({
  String txnId = '00000000-0000-4000-8000-0000000000d1',
  String partyName = 'Hodan Beverages',
  double total = 100,
  bool voided = false,
  DateTime? postedAt,
  String? documentPath,
}) {
  return ReceiveSummary(
    txnId: txnId,
    occurredAt: DateTime(2026, 6, 3, 9, 15),
    postedAt: postedAt ?? DateTime.now(),
    partyId: 'p-$txnId',
    partyName: partyName,
    totalAmount: total,
    paidAmount: 0,
    paymentMethodCode: null,
    isVoided: voided,
    reversalTxnId: voided ? 'reversal-$txnId' : null,
    voidedAt: voided ? DateTime(2026, 6, 3, 10, 0) : null,
    documentId: documentPath == null ? null : 'doc-$txnId',
    documentPath: documentPath,
  );
}

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    // Default to owner caps so the existing assertions (which expect
    // VOID to be visible) still hold. The cashier-mode test below
    // overrides this explicitly.
    auth = FakeAuthController(
      capabilities: Capabilities.forTesting(const ['receive.void']),
    );
    api = FakeShopApi();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pumpDetail(WidgetTester tester, {String txnId = '00000000-0000-4000-8000-0000000000d1'}) async {
    await tester.pumpWidget(
      wrapWithApp(
        ReceiveDetailScreen(shop: shop, txnId: txnId),
        authController: auth,
        shopApi: api,
      ),
    );
  }

  testWidgets('renders lines + total + supplier for a recent posted bono',
      (tester) async {
    api.onGetReceive = (_, _) async => _header(total: 100);
    api.onGetReceiveLines = (_, _) async => const [
      ReceiveLineDetail(
        lineNo: 1,
        itemId: 'i1',
        shopItemUnitId: 'siu-1',
        itemName: 'Caano',
        quantity: 2,
        unitLabel: 'Carton',
        unitAmount: 40,
        lineTotal: 80,
        packagingLabel: 'Carton',
      ),
      ReceiveLineDetail(
        lineNo: 2,
        itemId: 'i2',
        shopItemUnitId: 'siu-2',
        itemName: 'Shaah',
        quantity: 1,
        unitLabel: 'Box',
        unitAmount: 20,
        lineTotal: 20,
        packagingLabel: 'Box',
      ),
    ];

    await pumpDetail(tester);
    await tester.pumpAndSettle();

    expect(find.text('Caano'), findsOneWidget);
    expect(find.text('Shaah'), findsOneWidget);
    expect(find.text(en.receiveDetailTotalLabel), findsOneWidget);
    // Supplier label visible.
    expect(
      find.text(en.receiveHistorySupplierLabel('Hodan Beverages')),
      findsOneWidget,
    );
    // VOID action available (posted within 24 h, not voided).
    expect(
      find.widgetWithText(TextButton, en.receiveDetailVoidButton),
      findsOneWidget,
    );
  });

  testWidgets('voided bono shows banner + hides VOID button', (tester) async {
    api.onGetReceive = (_, _) async => _header(voided: true);
    api.onGetReceiveLines = (_, _) async => const [];

    await pumpDetail(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.receiveDetailVoidedHeader), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, en.receiveDetailVoidButton),
      findsNothing,
    );
  });

  testWidgets('outside 24-hour window hides the VOID button', (tester) async {
    api.onGetReceive = (_, _) async => _header(
      postedAt: DateTime.now().subtract(const Duration(hours: 25)),
    );
    api.onGetReceiveLines = (_, _) async => const [];

    await pumpDetail(tester);
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextButton, en.receiveDetailVoidButton),
      findsNothing,
    );
  });

  testWidgets(
    'confirm → voidReceive called with the bono txn id, pops with true',
    (tester) async {
      api.onGetReceive = (_, _) async => _header();
      api.onGetReceiveLines = (_, _) async => const [
        ReceiveLineDetail(
          lineNo: 1,
          itemId: 'i1',
          shopItemUnitId: 'siu-1',
          itemName: 'Caano',
          quantity: 1,
          unitLabel: 'Carton',
          unitAmount: 100,
          lineTotal: 100,
          packagingLabel: 'Carton',
        ),
      ];
      String? capturedTxnId;
      api.onVoidReceive = (_, txnId, _) async {
        capturedTxnId = txnId;
        return 'reversal-id';
      };

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
                            ReceiveDetailScreen(shop: shop, txnId: '00000000-0000-4000-8000-0000000000d1'),
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
        find.widgetWithText(TextButton, en.receiveDetailVoidButton),
      );
      await tester.pumpAndSettle();

      // Confirm dialog with the "mistakes only" hint.
      expect(find.text(en.receiveVoidConfirmTitle), findsOneWidget);
      expect(find.text(en.receiveVoidMistakesOnlyHint), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, en.receiveVoidConfirmYes),
      );
      await tester.pumpAndSettle();

      expect(capturedTxnId, '00000000-0000-4000-8000-0000000000d1');
      expect(poppedWith, isTrue);
    },
  );

  testWidgets('cancel dialog → voidReceive not called', (tester) async {
    api.onGetReceive = (_, _) async => _header();
    api.onGetReceiveLines = (_, _) async => const [];

    await pumpDetail(tester);
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(TextButton, en.receiveDetailVoidButton),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(TextButton, en.receiveVoidConfirmNo),
    );
    await tester.pumpAndSettle();

    expect(api.voidReceiveCalls, isEmpty);
  });

  testWidgets(
    'cashier role hides VOID even when within the 24-hour window',
    (tester) async {
      auth.setCapabilities(Capabilities.empty());
      api.onGetReceive = (_, _) async => _header();
      api.onGetReceiveLines = (_, _) async => const [];

      await pumpDetail(tester);
      await tester.pumpAndSettle();

      // Window says yes, capability says no → button stays hidden.
      expect(
        find.widgetWithText(TextButton, en.receiveDetailVoidButton),
        findsNothing,
      );
    },
  );

  ReceiveSummary offlineReceive({required DateTime occurredAt}) => ReceiveSummary(
        txnId: '00000000-0000-4000-8000-0000000000d1',
        occurredAt: occurredAt,
        postedAt: null, // not yet synced (serverUpdatedAtMs == 0)
        partyId: 'p-1',
        partyName: 'Hodan Beverages',
        totalAmount: 100,
        paidAmount: 0,
        paymentMethodCode: null,
        isVoided: false,
        reversalTxnId: null,
        voidedAt: null,
      );

  testWidgets('unsynced offline receive (UUID id, no postedAt) still shows '
      'VOID within the window (0100 gate switch)', (tester) async {
    api.onGetReceive =
        (_, _) async => offlineReceive(occurredAt: DateTime.now());
    await pumpDetail(tester);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextButton, en.receiveDetailVoidButton),
      findsOneWidget,
    );
  });

  testWidgets('backdated unsynced receive (outside window) hides VOID',
      (tester) async {
    api.onGetReceive =
        (_, _) async => offlineReceive(occurredAt: DateTime(2020, 1, 1));
    await pumpDetail(tester);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextButton, en.receiveDetailVoidButton),
      findsNothing,
    );
  });

  testWidgets('receive with an attached bono shows "View bono"', (tester) async {
    api.onGetReceive =
        (_, _) async => _header(documentPath: 'shop/documents/d1/image.jpg');
    api.onGetReceiveLines = (_, _) async => const [];
    await pumpDetail(tester);
    await tester.pumpAndSettle();
    expect(find.text(en.receiveDetailViewBonoButton), findsOneWidget);
  });

  testWidgets('receive without a bono hides "View bono"', (tester) async {
    api.onGetReceive = (_, _) async => _header(); // documentPath null
    api.onGetReceiveLines = (_, _) async => const [];
    await pumpDetail(tester);
    await tester.pumpAndSettle();
    expect(find.text(en.receiveDetailViewBonoButton), findsNothing);
  });

  testWidgets('tapping "View bono" signs a URL for the stored path', (
    tester,
  ) async {
    final signed = <String>[];
    api.onGetReceive =
        (_, _) async => _header(documentPath: 'shop/documents/d1/image.jpg');
    api.onGetReceiveLines = (_, _) async => const [];
    // Return null so no full-screen Image.network is pushed in the test; we
    // just assert the sign call fired for the right path.
    api.onSignBonoUrl = (path) async {
      signed.add(path);
      return null;
    };

    await pumpDetail(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.receiveDetailViewBonoButton));
    await tester.pumpAndSettle();

    expect(signed, ['shop/documents/d1/image.jpg']);
    expect(find.text(en.receiveDetailBonoUnavailable), findsOneWidget);
  });
}
