import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/receive/receive_screen.dart';
import 'package:dukan/scanner/multi_scan_sheet.dart';
import 'package:dukan/scanner/scan_event.dart';
import 'package:dukan/scanner/scanner_sheet.dart';
import 'package:dukan/sync/local_repository.dart';

import '../shared/fakes.dart';
import '../shared/test_database.dart';
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
  late VoidCallback restoreMultiScan;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    receive = ReceiveController()..setSupplier(_hassan());
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
    // Default: cancelled scan unless overridden.
    restoreScanner = Scanner.overrideOpener((_) async => null);
    restoreMultiScan = MultiScan.overrideOpener(
      (_, {required resolver}) async => null,
    );
  });

  tearDown(() {
    restoreScanner();
    restoreMultiScan();
  });

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
    expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
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
      await tester.tap(find.byIcon(Icons.qr_code_scanner));
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
      await tester.tap(find.byIcon(Icons.qr_code_scanner));
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

  testWidgets(
    'offline (use_local_db): scan pre-fills the line from the mirror, no network',
    (tester) async {
      final db = await openTestDatabase();
      final repo = LocalRepository(Future.value(db));
      await repo.applyItemsPayload({
        'items': [
          {
            'shop_item_id': 'si-cola',
            'shop_id': 'shop-1',
            'item_id': null,
            'display_name': 'Cola',
            'category_id': null,
            'base_unit_code': 'bottle',
            'current_stock': 40,
            'avg_cost': 0,
            'reorder_threshold': null,
            'sale_count': 0,
            'last_sold_at_ms': null,
            'is_active': true,
            'server_updated_at_ms': 1700000000000,
          },
        ],
        'units': [
          {
            'shop_item_unit_id': 'siu-carton',
            'shop_item_id': 'si-cola',
            'unit_code': 'carton',
            'packaging_label': 'Carton (12)',
            'conversion_to_base': 12,
            'sale_price': 5500,
            'last_cost': 3400,
            'is_default_sale': false,
            'is_default_receive': false,
            'is_active': true,
            'server_updated_at_ms': 1700000000000,
          },
        ],
        'aliases': const [],
        'barcodes': [
          {
            'barcode': '5000000000012',
            'shop_item_unit_id': 'siu-carton',
            'is_primary': true,
          },
        ],
      });

      var searchCalled = false;
      api.onSearchItems = (_, _, _, _, _, _) async {
        searchCalled = true;
        return const <ItemSearchResult>[];
      };

      restoreScanner();
      restoreScanner = Scanner.overrideOpener(
        (_) async => const ScanEvent(
          code: '5000000000012',
          source: ScanSource.camera,
          symbology: 'ean13',
        ),
      );

      await tester.pumpWidget(
        wrapWithApp(
          ReceiveScreen(shop: shop),
          authController: auth,
          shopApi: api,
          receiveController: receive,
          localRepository: repo,
          configResolver:
              FakeConfigResolver(values: const {'use_local_db': true}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.qr_code_scanner));
      await tester.pumpAndSettle();

      // The scanned item pre-fills the line composer, resolved from the mirror.
      expect(find.text('Cola'), findsAtLeastNWidgets(1));
      expect(searchCalled, isFalse,
          reason: 'offline scan must resolve locally, not via the network');
    },
  );

  testWidgets(
    'long-pressing the scan icon opens multi-scan and applies staged lines',
    (tester) async {
      restoreMultiScan();
      restoreMultiScan = MultiScan.overrideOpener(
        (_, {required resolver}) async => MultiScanResult(
          stagedLines: [
            StagedScanLine(
              shopItemId: 'si-rice',
              shopItemUnitId: 'siu-rice',
              itemId: 'item-rice',
              displayName: 'Bariis Basmati',
              packagingLabel: '25 Kg Bag',
              baseUnitLabel: 'Kg',
              quantity: 3,
              perUnitCost: 12,
            ),
          ],
          unknownCodes: const [],
        ),
      );
      api.onSearchItems = (_, _, _, _, _, _) async => const <ItemSearchResult>[];

      await pumpReceive(tester);
      await tester.pumpAndSettle();

      await tester.longPress(find.byIcon(Icons.qr_code_scanner));
      await tester.pumpAndSettle();

      expect(receive.lines.length, 1);
      final line = receive.lines.values.first;
      expect(line.shopItemUnitId, 'siu-rice');
      expect(line.quantity, 3);
      expect(line.lineTotal, 36);
    },
  );
}
