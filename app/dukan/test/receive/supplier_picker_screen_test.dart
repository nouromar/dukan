import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/receive/receive_screen.dart';
import 'package:dukan/receive/supplier_picker_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

PartySearchResult fakeSupplier({
  String id = 'sup-1',
  String name = 'Hassan Wholesaler',
  double payable = 40,
}) => PartySearchResult(
  id: id,
  name: name,
  phone: '+252600000000',
  typeCode: 'supplier',
  receivable: 0,
  payable: payable,
);

void main() {
  late FakeAuthController auth;
  late FakeShopApi api;
  late ReceiveController receive;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    auth = FakeAuthController();
    api = FakeShopApi();
    receive = ReceiveController();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pumpPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        SupplierPickerScreen(shop: shop),
        authController: auth,
        shopApi: api,
        receiveController: receive,
      ),
    );
  }

  testWidgets('queries with type=supplier and lists results with payable', (
    tester,
  ) async {
    api.onSearchParties = (_, _, type, _) async {
      expect(type, 'supplier');
      return [
        fakeSupplier(name: 'Hassan Wholesaler', payable: 40),
        fakeSupplier(id: 'sup-2', name: 'Mahad Grains', payable: 0),
      ];
    };

    await pumpPicker(tester);
    await tester.pumpAndSettle();

    expect(find.text('Hassan Wholesaler'), findsOneWidget);
    expect(find.text(en.supplierPickerOwesLabel('\$40')), findsOneWidget);
    expect(find.text('Mahad Grains'), findsOneWidget);
    expect(find.text(en.supplierPickerNoBonosLabel), findsOneWidget);
  });

  testWidgets(
    'tapping a supplier sets it on the controller and pushReplaces to ReceiveScreen',
    (tester) async {
      api.onSearchParties = (_, _, _, _) async => [
        fakeSupplier(name: 'Hassan Wholesaler'),
      ];

      await pumpPicker(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hassan Wholesaler'));
      await tester.pumpAndSettle();

      expect(receive.supplier?.name, 'Hassan Wholesaler');
      expect(find.byType(ReceiveScreen), findsOneWidget);
      expect(find.byType(SupplierPickerScreen), findsNothing);
    },
  );

  testWidgets('empty results show the right message', (tester) async {
    api.onSearchParties = (_, _, _, _) async => const [];

    await pumpPicker(tester);
    await tester.pumpAndSettle();

    expect(find.text(en.supplierPickerEmptyMessage), findsOneWidget);
  });

  testWidgets('+ NEW SUPPLIER shows the not-yet-available dialog', (
    tester,
  ) async {
    api.onSearchParties = (_, _, _, _) async => const [];

    await pumpPicker(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.supplierNewButton));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(en.supplierNewUnavailable), findsOneWidget);
  });
}
