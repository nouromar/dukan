import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/products/products_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

ShopItemSummary _shopItem({
  String shopItemId = 'si-1',
  String? itemId = 'i-1',
  String displayName = 'Bariis Basmati',
  String? categoryName,
  String baseUnitCode = 'kg',
  String baseUnitLabel = 'Kg',
  double currentStock = 50,
  int unitCount = 1,
  bool isActive = true,
  String? defaultReceivePackagingLabel,
  double? defaultReceiveConversion,
}) => ShopItemSummary(
  shopItemId: shopItemId,
  itemId: itemId,
  displayName: displayName,
  categoryName: categoryName,
  baseUnitCode: baseUnitCode,
  baseUnitLabel: baseUnitLabel,
  currentStock: currentStock,
  unitCount: unitCount,
  isActive: isActive,
  defaultReceivePackagingLabel: defaultReceivePackagingLabel,
  defaultReceiveConversion: defaultReceiveConversion,
);

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

  Future<void> pumpProducts(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        ProductsScreen(shop: shop),
        authController: auth,
        shopApi: api,
      ),
    );
  }

  testWidgets('shows loading then empty state when listShopItems returns nothing', (
    tester,
  ) async {
    api.onListShopItems = (_, _, _, _) async => const [];

    await pumpProducts(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text(en.productsEmptyMessage), findsOneWidget);
  });

  testWidgets('renders shop items returned by listShopItems', (
    tester,
  ) async {
    api.onListShopItems = (_, _, _, _) async => [
      _shopItem(displayName: 'Bariis Basmati'),
      _shopItem(shopItemId: 'si-2', itemId: 'i-2', displayName: 'Sonkor'),
    ];

    await pumpProducts(tester);
    await tester.pumpAndSettle();

    expect(find.text('Bariis Basmati'), findsOneWidget);
    expect(find.text('Sonkor'), findsOneWidget);
  });

  testWidgets('activated item shows stock label in base unit', (
    tester,
  ) async {
    api.onListShopItems = (_, _, _, _) async => [
      _shopItem(
        displayName: 'Bariis Basmati',
        baseUnitLabel: 'Kg',
        currentStock: 50,
      ),
    ];

    await pumpProducts(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('50Kg'),
      findsOneWidget,
    );
  });

  testWidgets('stock renders in the default receive packaging when set', (
    tester,
  ) async {
    // 155kg on hand, restocked in 25kg sacks. The list tile is compact —
    // whole-packaging count only ("6 Sack"), not the full sized+remainder
    // form that would overflow the narrow trailing slot.
    api.onListShopItems = (_, _, _, _) async => [
      _shopItem(
        displayName: 'Bariis Basmati',
        baseUnitLabel: 'kg',
        currentStock: 155,
        defaultReceivePackagingLabel: '25 Sack',
        defaultReceiveConversion: 25,
      ),
    ];

    await pumpProducts(tester);
    await tester.pumpAndSettle();

    expect(find.text('6 Sack'), findsOneWidget);
    // Not the raw base-unit rendering, nor the long compound form.
    expect(find.text('155kg'), findsNothing);
    expect(find.text('6 Sack(25kg) + 5kg'), findsNothing);
  });

  // TODO(v2): rewrite for new activation semantics — T#145
  // The "no stock" badge has been merged into the stock label; an item
  // with currentStock=0 just renders "0 Kg in stock". A future screen
  // refresh may re-introduce a dedicated no-stock affordance.

  // TODO(v2): rewrite for new activation semantics — T#145
  // The "+ ADD" button on catalog candidates moved off the products
  // screen entirely. Catalog activation now lives in `CatalogPickerScreen`
  // (sibling task). The products list only shows shop_items the shop has
  // already activated.

  testWidgets('search input filters results after debounce', (tester) async {
    final queries = <String?>[];
    api.onListShopItems = (_, _, query, _) async {
      queries.add(query);
      return (query ?? '').contains('rice')
          ? [_shopItem(displayName: 'Bariis Basmati')]
          : const <ShopItemSummary>[];
    };

    await pumpProducts(tester);
    await tester.pumpAndSettle();
    // First load uses no query (null).
    expect(queries, [null]);

    await tester.enterText(find.byType(TextField).first, 'rice');
    // Debounce is 250ms in the screen.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(queries.last, 'rice');
    expect(find.text('Bariis Basmati'), findsOneWidget);
  });

  testWidgets('search-empty state shows the query-specific message', (
    tester,
  ) async {
    api.onListShopItems = (_, _, _, _) async => const [];

    await pumpProducts(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'xyz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text(en.productsSearchEmptyMessage('xyz')), findsOneWidget);
  });

  testWidgets('search error shows retry, which re-fetches', (tester) async {
    var attempts = 0;
    api.onListShopItems = (_, _, _, _) async {
      attempts++;
      if (attempts == 1) throw Exception('network down');
      return const <ShopItemSummary>[];
    };

    // Suppress the FlutterError.reportError that the screen calls so the
    // test doesn't fail on the reported error.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = originalOnError);

    await pumpProducts(tester);
    await tester.pumpAndSettle();

    // #372: error text now includes the raw exception, so match
    // by prefix instead of exact text.
    expect(
      find.textContaining(en.productsLoadFailedMessage),
      findsOneWidget,
    );
    await tester.tap(find.text(en.tryAgain));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text(en.productsLoadFailedMessage), findsNothing);
    expect(find.text(en.productsEmptyMessage), findsOneWidget);
  });

  // TODO(v2): rewrite for new activation semantics — T#145
  // "+ NEW ITEM" now opens the ShopItemEditorScreen; there is no toast.
  // Test covering the new editor wiring belongs in a sibling task
  // (T#151 / T#155).

  // ---- Phase B: redesign — headline + sort + packed row ----------------

  testWidgets(
    'headline tile shows totals + low + no-price counts',
    (tester) async {
      api.onListShopItems = (_, _, _, _) async => [
            const ShopItemSummary(
              shopItemId: 'a',
              itemId: null,
              displayName: 'A',
              categoryName: null,
              baseUnitCode: 'kg',
              baseUnitLabel: 'Kg',
              currentStock: 100,
              unitCount: 1,
              isActive: true,
              defaultSalePrice: 1.0,
              anyPriceSet: true,
            ),
            const ShopItemSummary(
              shopItemId: 'b',
              itemId: null,
              displayName: 'B',
              categoryName: null,
              baseUnitCode: 'kg',
              baseUnitLabel: 'Kg',
              currentStock: 0, // low (< 1)
              unitCount: 1,
              isActive: true,
              defaultSalePrice: null,
              anyPriceSet: false, // no price
            ),
          ];
      await pumpProducts(tester);
      await tester.pumpAndSettle();
      expect(find.text(en.productsHeadline(2, 1, 1)), findsOneWidget);
    },
  );

  testWidgets(
    'sort dropdown switches between Name and Stock (low first)',
    (tester) async {
      api.onListShopItems = (_, _, _, _) async => [
            const ShopItemSummary(
              shopItemId: 'a',
              itemId: null,
              displayName: 'AAA',
              categoryName: null,
              baseUnitCode: 'kg',
              baseUnitLabel: 'Kg',
              currentStock: 100,
              unitCount: 1,
              isActive: true,
            ),
            const ShopItemSummary(
              shopItemId: 'z',
              itemId: null,
              displayName: 'ZZZ',
              categoryName: null,
              baseUnitCode: 'kg',
              baseUnitLabel: 'Kg',
              currentStock: 0,
              unitCount: 1,
              isActive: true,
            ),
          ];
      await pumpProducts(tester);
      await tester.pumpAndSettle();

      // Default sort is alphabetical → AAA before ZZZ.
      var aPos = tester.getTopLeft(find.text('AAA')).dy;
      var zPos = tester.getTopLeft(find.text('ZZZ')).dy;
      expect(aPos, lessThan(zPos));

      // Switch to Stock (low first) — ZZZ has currentStock 0, AAA 100.
      // The DropdownButton is parameterised over a private enum so
      // byType doesn't work — match by widget predicate instead.
      await tester
          .tap(find.byWidgetPredicate((w) => w is DropdownButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.productsSortByStockLow).last);
      await tester.pumpAndSettle();

      aPos = tester.getTopLeft(find.text('AAA')).dy;
      zPos = tester.getTopLeft(find.text('ZZZ')).dy;
      expect(zPos, lessThan(aPos));
    },
  );
}
