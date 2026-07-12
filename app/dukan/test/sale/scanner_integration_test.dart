import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/sale/cart_controller.dart';
import 'package:dukan/sale/sale_screen.dart';
import 'package:dukan/scanner/scan_event.dart';
import 'package:dukan/scanner/scanner_sheet.dart';
import 'package:dukan/sync/local_repository.dart';

import '../shared/fakes.dart';
import '../shared/test_database.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late CartController cart;
  late ShopSummary shop;
  late AppLocalizations en;
  late VoidCallback restoreScanner;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    cart = CartController();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
    // Default override: no scan happens unless overridden by the test.
    restoreScanner = Scanner.overrideOpener((_) async => null);
  });

  tearDown(() {
    restoreScanner();
  });

  Future<void> pumpSale(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        SaleScreen(shop: shop),
        authController: auth,
        shopApi: api,
        cartController: cart,
      ),
    );
  }

  testWidgets('camera icon visible in the search bar', (tester) async {
    api.onSearchItems = (_, _, _, _, _, _) async => const <ItemSearchResult>[];
    await pumpSale(tester);
    await tester.pumpAndSettle();
    expect(
      find.byTooltip(en.scanCameraTooltip),
      findsOneWidget,
      reason: 'the camera icon should be the search-bar suffix',
    );
  });

  testWidgets(
    'scanned code that matches one shop_item adds it to the cart',
    (tester) async {
      // Stub the camera open with a fixed event so we drive the
      // matched-scan path without a real viewfinder.
      restoreScanner();
      restoreScanner = Scanner.overrideOpener(
        (_) async => const ScanEvent(
          code: '5901234123457',
          source: ScanSource.camera,
          symbology: 'ean13',
        ),
      );

      // searchItems for an empty query (initial fetch) returns nothing;
      // when called with the scanned code it returns the matching item.
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

      await pumpSale(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(en.scanCameraTooltip));
      await tester.pumpAndSettle();

      expect(cart.lines, hasLength(1));
      expect(cart.lines.values.first.displayName, 'Bariis Basmati');
    },
  );

  testWidgets(
    'scanned code with zero matches surfaces the unknown-barcode pill',
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

      await pumpSale(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(en.scanCameraTooltip));
      await tester.pumpAndSettle();

      expect(
        find.text(en.scanUnknownPillLabel('0000000000000')),
        findsOneWidget,
      );

      // Dismiss removes the pill.
      await tester.tap(find.byTooltip(en.scanUnknownDismissAction));
      await tester.pumpAndSettle();
      expect(
        find.text(en.scanUnknownPillLabel('0000000000000')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'offline (use_local_db): scan resolves from the mirror, no network call',
    (tester) async {
      // Seed a local mirror with Cola + a carton packaging carrying the code.
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
          SaleScreen(shop: shop),
          authController: auth,
          shopApi: api,
          cartController: cart,
          localRepository: repo,
          configResolver:
              FakeConfigResolver(values: const {'use_local_db': true}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(en.scanCameraTooltip));
      await tester.pumpAndSettle();

      // Added to the cart from the mirror — network search never called.
      expect(cart.lines, hasLength(1));
      expect(cart.lines.values.first.displayName, 'Cola');
      expect(searchCalled, isFalse,
          reason: 'offline scan must resolve locally, not via the network');
    },
  );

  testWidgets(
    'cancelled scan (null event) leaves the cart and pill untouched',
    (tester) async {
      // Default override already returns null. searchItems returns
      // nothing on initial fetch.
      api.onSearchItems = (_, _, _, _, _, _) async => const <ItemSearchResult>[];

      await pumpSale(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(en.scanCameraTooltip));
      await tester.pumpAndSettle();

      expect(cart.isEmpty, isTrue);
      expect(find.text(en.scanUnknownPillLabel('')), findsNothing);
    },
  );
}
