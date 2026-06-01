import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/products/products_screen.dart';

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

  Future<void> pumpProducts(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        ProductsScreen(shop: shop),
        authController: auth,
        shopApi: api,
      ),
    );
  }

  testWidgets('shows loading then empty state when search returns nothing', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => const [];

    await pumpProducts(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text(en.productsEmptyMessage), findsOneWidget);
  });

  testWidgets('renders activated + catalog sections with correct headers', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(name: 'Bariis Basmati'),
      fakeCatalogCandidate(name: 'Caano qalaylan'),
    ];

    await pumpProducts(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.productsInYourShop), findsOneWidget);
    expect(find.text(en.productsFromCatalog), findsOneWidget);
    expect(find.text('Bariis Basmati'), findsOneWidget);
    expect(find.text('Caano qalaylan'), findsOneWidget);
  });

  testWidgets('activated item shows stock label and sale price', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(
        name: 'Bariis Basmati',
        baseUnitLabel: 'Kg',
        salePrice: 1.5,
        currentStock: 50,
      ),
    ];

    await pumpProducts(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.productsStockLabel('50', 'Kg')), findsOneWidget);
    // _formatPrice renders non-integer values with two decimals.
    expect(find.text('1.50'), findsOneWidget);
  });

  testWidgets('activated item with no stock shows "no stock" label', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => [
      fakeActivatedItem(currentStock: 0),
    ];

    await pumpProducts(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.productsNoStock), findsOneWidget);
  });

  testWidgets('tap ADD on catalog candidate calls ensureShopItem and refreshes', (
    tester,
  ) async {
    String? activatedCatalogId;
    var searchCalls = 0;
    api.onSearchItems = (_, _, _, _, _, _) async {
      searchCalls++;
      return [fakeCatalogCandidate(catalogItemId: 'catalog-pasta')];
    };
    api.onEnsureShopItem = (_, catalogId) async {
      activatedCatalogId = catalogId;
      return 'new-item-id';
    };

    await pumpProducts(tester);
    await tester.pumpAndSettle();

    final initialSearches = searchCalls;
    await tester.tap(find.text(en.productsAddToShopButton));
    await tester.pumpAndSettle();

    expect(activatedCatalogId, 'catalog-pasta');
    expect(searchCalls, greaterThan(initialSearches),
        reason: 'list should refresh after add');
  });

  testWidgets('search input filters results after debounce', (tester) async {
    final queries = <String>[];
    api.onSearchItems = (_, query, _, _, _, _) async {
      queries.add(query);
      return query.contains('rice')
          ? [fakeActivatedItem(name: 'Bariis Basmati')]
          : [];
    };

    await pumpProducts(tester);
    await tester.pumpAndSettle();
    expect(queries, ['']);

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
    api.onSearchItems = (_, _, _, _, _, _) async => const [];

    await pumpProducts(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'xyz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text(en.productsSearchEmptyMessage('xyz')), findsOneWidget);
  });

  testWidgets('search error shows retry, which re-fetches', (tester) async {
    var attempts = 0;
    api.onSearchItems = (_, _, _, _, _, _) async {
      attempts++;
      if (attempts == 1) throw Exception('network down');
      return const <ItemSearchResult>[];
    };

    // Suppress the FlutterError.reportError that the screen calls so the
    // test doesn't fail on the reported error.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = originalOnError);

    await pumpProducts(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.productsLoadFailedMessage), findsOneWidget);
    await tester.tap(find.text(en.tryAgain));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text(en.productsLoadFailedMessage), findsNothing);
    expect(find.text(en.productsEmptyMessage), findsOneWidget);
  });

  testWidgets('tap "+ NEW ITEM" shows the not-yet-available toast', (
    tester,
  ) async {
    api.onSearchItems = (_, _, _, _, _, _) async => const [];

    await pumpProducts(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.productsNewItemButton));
    await tester.pump(); // SnackBar animation

    expect(find.text(en.productsNewItemUnavailable), findsOneWidget);
  });
}
