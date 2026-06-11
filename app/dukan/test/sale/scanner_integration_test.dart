import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/sale/cart_controller.dart';
import 'package:dukan/sale/sale_screen.dart';
import 'package:dukan/scanner/scan_event.dart';
import 'package:dukan/scanner/scanner_sheet.dart';

import '../shared/fakes.dart';
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
