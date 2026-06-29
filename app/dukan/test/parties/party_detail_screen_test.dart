import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/parties/party_detail_screen.dart';
import 'package:dukan/payment/payment_controller.dart';
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
        PartyDetailScreen(shop: shop, partyId: 'p-1'),
        authController: auth,
        shopApi: api,
        paymentController: PaymentController(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('customer with outstanding receivable shows "They owe you"'
      ' label + PAY button enabled', (tester) async {
    api.onGetPartyDetail = (_, _, _) async => PartyDetail(
      header: const PartyDetailHeader(
        id: 'p-1',
        name: 'Cumar',
        phone: null,
        typeCode: 'customer',
        receivable: 25,
        payable: 0,
        isActive: true,
      ),
      sales: const [],
      receives: const [],
      payments: const [],
    );

    await pump(tester);

    expect(find.text('Cumar'), findsOneWidget);
    expect(find.text(en.partyDetailReceivableLabel), findsOneWidget);
    expect(find.text('\$25.00'), findsOneWidget);
    final payBtn = tester
        .widgetList<ButtonStyleButton>(
          find.ancestor(
            of: find.text(en.partyDetailPayButton),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        )
        .first;
    expect(payBtn.onPressed, isNotNull);
  });

  testWidgets('tapping a sale row opens the sale detail', (tester) async {
    api.onGetPartyDetail = (_, _, _) async => PartyDetail(
      header: const PartyDetailHeader(
        id: 'p-1',
        name: 'Cumar',
        phone: null,
        typeCode: 'customer',
        receivable: 25,
        payable: 0,
        isActive: true,
      ),
      sales: [
        PartyTxnRow(
          txnId: 'txn-1',
          occurredAt: DateTime(2026, 6, 12),
          totalAmount: 50,
          paidAmount: 0,
          isVoided: false,
        ),
      ],
      receives: const [],
      payments: const [],
    );
    api.onGetSale = (_, txnId) async => SaleSummary(
      txnId: txnId,
      occurredAt: DateTime(2026, 6, 12),
      postedAt: DateTime(2026, 6, 12),
      partyId: 'p-1',
      partyName: 'Cumar',
      totalAmount: 50,
      paidAmount: 0,
      paymentMethodCode: null,
      isVoided: false,
      reversalTxnId: null,
      voidedAt: null,
    );
    api.onGetSaleLines = (_, _) async => const [];

    await pump(tester);
    // The sale row ($50.00) is tappable and opens its sale detail.
    await tester.tap(find.text('\$50.00'));
    await tester.pumpAndSettle();

    expect(find.byType(SaleDetailScreen), findsOneWidget);
    expect(find.text(en.saleDetailTitle), findsOneWidget);
  });

  testWidgets('hide action soft-deletes the party (queued set_party_active)',
      (tester) async {
    api.onGetPartyDetail = (_, _, _) async => PartyDetail(
      header: const PartyDetailHeader(
        id: 'p-1',
        name: 'Cumar',
        phone: null,
        typeCode: 'customer',
        receivable: 0,
        payable: 0,
        isActive: true,
      ),
      sales: const [],
      receives: const [],
      payments: const [],
    );
    String? hiddenId;
    bool? hiddenActive;
    api.onSetPartyActive = (id, active) async {
      hiddenId = id;
      hiddenActive = active;
    };

    await pump(tester);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text(en.partyHideConfirmTitle), findsOneWidget);

    await tester.tap(find.text(en.partyHideConfirmYes));
    await tester.pumpAndSettle();

    // The queued post drained to set_party_active(p-1, isActive=false).
    expect(hiddenId, 'p-1');
    expect(hiddenActive, false);
  });

  testWidgets('customer with zero balance: PAY disabled', (tester) async {
    api.onGetPartyDetail = (_, _, _) async => PartyDetail(
      header: const PartyDetailHeader(
        id: 'p-1',
        name: 'Cumar',
        phone: null,
        typeCode: 'customer',
        receivable: 0,
        payable: 0,
        isActive: true,
      ),
      sales: const [],
      receives: const [],
      payments: const [],
    );

    await pump(tester);

    final payBtn = tester
        .widgetList<ButtonStyleButton>(
          find.ancestor(
            of: find.text(en.partyDetailPayButton),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        )
        .first;
    expect(payBtn.onPressed, isNull);
  });

  testWidgets('supplier shows "You owe them" label', (tester) async {
    api.onGetPartyDetail = (_, _, _) async => PartyDetail(
      header: const PartyDetailHeader(
        id: 'p-1',
        name: 'Alaab Keene',
        phone: '0612345678',
        typeCode: 'supplier',
        receivable: 0,
        payable: 80,
        isActive: true,
      ),
      sales: const [],
      receives: const [],
      payments: const [],
    );

    await pump(tester);

    expect(find.text('Alaab Keene'), findsOneWidget);
    expect(find.text('0612345678'), findsOneWidget);
    expect(find.text(en.partyDetailPayableLabel), findsOneWidget);
    expect(find.text('\$80.00'), findsOneWidget);
  });

  testWidgets('Pay on a supplier opens the Money Out page, supplier pre-filled',
      (tester) async {
    api.onGetPartyDetail = (_, _, _) async => PartyDetail(
      header: const PartyDetailHeader(
        id: 'p-1',
        name: 'Alaab Keene',
        phone: null,
        typeCode: 'supplier',
        receivable: 0,
        payable: 80,
        isActive: true,
      ),
      sales: const [],
      receives: const [],
      payments: const [],
    );

    await pump(tester);
    await tester.tap(find.text(en.partyDetailPayButton));
    await tester.pumpAndSettle();

    // Dedicated Money Out page with the supplier already selected — no
    // "pick supplier" prompt, no direction toggle.
    expect(find.text(en.paymentOutLabel), findsWidgets);
    expect(find.text(en.paymentPickSupplierButton), findsNothing);
    expect(find.text('Alaab Keene'), findsWidgets);
  });

  testWidgets('pencil → edit dialog → updateParty fires with new name',
      (tester) async {
    api.onGetPartyDetail = (_, _, _) async => PartyDetail(
      header: const PartyDetailHeader(
        id: 'p-1',
        name: 'Old Name',
        phone: '0612345678',
        typeCode: 'customer',
        receivable: 5,
        payable: 0,
        isActive: true,
      ),
      sales: const [],
      receives: const [],
      payments: const [],
    );

    await pump(tester);

    // Tap the pencil on the header card.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    // Dialog has two text fields — name + phone. Edit the name.
    await tester.enterText(find.byType(TextField).first, 'New Name');
    await tester.tap(find.widgetWithText(FilledButton, en.shopItemEditorSaveButton));
    await tester.pumpAndSettle();

    expect(api.updatePartyCalls, hasLength(1));
    expect(api.updatePartyCalls.first.name, 'New Name');
  });

  testWidgets(
    'audit edit cue renders when list_audit_entries returns a recent entry',
    (tester) async {
      api.onGetPartyDetail = (_, _, _) async => PartyDetail(
        header: const PartyDetailHeader(
          id: 'p-1',
          name: 'Cumar',
          phone: null,
          typeCode: 'customer',
          receivable: 0,
          payable: 0,
          isActive: true,
        ),
        sales: const [],
        receives: const [],
        payments: const [],
      );
      api.onListAuditEntriesForEntity = (_, _, _, _) async => [
        AuditEntry(
          id: 'a-1',
          actorUserId: null,
          actionCode: 'people.party.edit',
          occurredAt: DateTime.now().subtract(const Duration(minutes: 5)),
          reason: null,
          source: 'mobile',
        ),
      ];

      await pump(tester);

      expect(
        find.textContaining(en.relativeTimeMinutesAgo(5)),
        findsOneWidget,
      );
    },
  );
}
