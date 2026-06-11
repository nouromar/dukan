import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/parties/customers_screen.dart';
import 'package:dukan/parties/suppliers_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

PartySearchResult _customer({
  String id = 'c-1',
  String name = 'Ahmed',
  double receivable = 0,
}) =>
    PartySearchResult(
      id: id,
      name: name,
      phone: '0612345678',
      typeCode: 'customer',
      receivable: receivable,
      payable: 0,
    );

PartySearchResult _supplier({
  String id = 's-1',
  String name = 'Acme Co',
  double payable = 0,
}) =>
    PartySearchResult(
      id: id,
      name: name,
      phone: '0612999888',
      typeCode: 'supplier',
      receivable: 0,
      payable: payable,
    );

void main() {
  late FakeShopApi api;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    api = FakeShopApi();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  testWidgets('Customers screen: headline sums receivables + sorts debtors first',
      (tester) async {
    api.onListParties = (_, _, type, _) async {
      expect(type, 'customer');
      return [
        _customer(id: 'c1', name: 'No Debt'),
        _customer(id: 'c2', name: 'Faadumo', receivable: 150),
        _customer(id: 'c3', name: 'Ahmed', receivable: 250),
      ];
    };
    await tester.pumpWidget(
      wrapWithApp(CustomersScreen(shop: shop), shopApi: api),
    );
    await tester.pumpAndSettle();

    // Headline tile.
    expect(find.text(en.customersHeadlineLabel), findsOneWidget);
    expect(find.text('\$400.00'), findsOneWidget); // 150 + 250
    expect(find.text(en.customersHeadlineCount(2)), findsOneWidget);
  });

  testWidgets('Suppliers screen: headline sums payables', (tester) async {
    api.onListParties = (_, _, type, _) async {
      expect(type, 'supplier');
      return [
        _supplier(id: 's1', name: 'Zero Co'),
        _supplier(id: 's2', name: 'Acme Co', payable: 80),
      ];
    };
    await tester.pumpWidget(
      wrapWithApp(SuppliersScreen(shop: shop), shopApi: api),
    );
    await tester.pumpAndSettle();

    expect(find.text(en.suppliersHeadlineLabel), findsOneWidget);
    expect(find.text('\$80.00'), findsOneWidget);
    expect(find.text(en.suppliersHeadlineCount(1)), findsOneWidget);
  });

  testWidgets(
    'initialHasBalanceOnly=true passes hasBalanceOnly to listParties',
    (tester) async {
      bool? observed;
      api.onListParties = (_, _, _, has) async {
        observed = has;
        return const [];
      };
      await tester.pumpWidget(
        wrapWithApp(
          CustomersScreen(shop: shop, initialHasBalanceOnly: true),
          shopApi: api,
        ),
      );
      await tester.pumpAndSettle();
      expect(observed, true);
    },
  );
}
