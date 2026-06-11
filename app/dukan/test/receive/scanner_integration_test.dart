import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/receive/receive_screen.dart';
import 'package:dukan/scanner/scan_event.dart';
import 'package:dukan/scanner/scanner_sheet.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

PartySearchResult _hassan() => const PartySearchResult(
      id: 'sup-1',
      name: 'Hassan',
      phone: null,
      typeCode: 'supplier',
      receivable: 0,
      payable: 0,
    );

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late ReceiveController receive;
  late ShopSummary shop;
  late AppLocalizations en;
  late VoidCallback restoreScanner;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    receive = ReceiveController()..setSupplier(_hassan());
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
    // Default: cancelled scan unless overridden.
    restoreScanner = Scanner.overrideOpener((_) async => null);
  });

  tearDown(() => restoreScanner());

  Future<void> pumpReceive(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        ReceiveScreen(shop: shop),
        authController: auth,
        shopApi: api,
        receiveController: receive,
      ),
    );
  }

  testWidgets('camera icon visible in the receive search bar', (tester) async {
    api.onSearchItems = (_, _, _, _, _, _) async => const <ItemSearchResult>[];
    await pumpReceive(tester);
    await tester.pumpAndSettle();
    expect(find.byTooltip(en.scanCameraTooltip), findsOneWidget);
  });

  testWidgets(
    'matched scan pre-fills the line form with the matched packaging',
    (tester) async {
      restoreScanner();
      restoreScanner = Scanner.overrideOpener(
        (_) async => const ScanEvent(
          code: '5901234123457',
          source: ScanSource.camera,
          symbology: 'ean13',
        ),
      );
      api.onSearchItems = (_, query, _, _, _, _) async {
        if (query == '5901234123457') {
          return [
            fakeActivatedItem(
              shopItemId: 'si-rice',
              itemId: 'item-rice',
              defaultShopItemUnitId: 'siu-rice',
              displayName: 'Bariis Basmati',
              defaultUnitSalePrice: 1.5,
            ),
          ];
        }
        return const <ItemSearchResult>[];
      };

      await pumpReceive(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(en.scanCameraTooltip));
      await tester.pumpAndSettle();

      // The matched item should now be selected — its name renders in
      // the per-packaging form header.
      expect(find.text('Bariis Basmati'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'zero-match scan surfaces the receive unknown-barcode pill',
    (tester) async {
      restoreScanner();
      restoreScanner = Scanner.overrideOpener(
        (_) async => const ScanEvent(
          code: '0000000000000',
          source: ScanSource.camera,
          symbology: 'ean13',
        ),
      );
      api.onSearchItems = (_, _, _, _, _, _) async => const <ItemSearchResult>[];

      await pumpReceive(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(en.scanCameraTooltip));
      await tester.pumpAndSettle();

      expect(
        find.text(en.scanUnknownPillLabel('0000000000000')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip(en.scanUnknownDismissAction));
      await tester.pumpAndSettle();
      expect(
        find.text(en.scanUnknownPillLabel('0000000000000')),
        findsNothing,
      );
    },
  );
}
