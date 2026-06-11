import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/products/catalog_picker_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeShopApi api;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    api = FakeShopApi();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  Future<void> pumpPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        CatalogPickerScreen(shop: shop),
        shopApi: api,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'lists activated + unactivated rows; activated has badge + disabled checkbox',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeActivatedItem(
          shopItemId: 'si-rice',
          itemId: 'item-rice',
          displayName: 'Bariis Basmati',
        ),
        fakeCatalogCandidate(
          itemId: 'item-milk',
          displayName: 'Caano qalalan',
        ),
      ];

      await pumpPicker(tester);

      // Both rows visible.
      expect(find.text('Bariis Basmati'), findsOneWidget);
      expect(find.text('Caano qalalan'), findsOneWidget);

      // The activated row carries the "already added" badge.
      expect(
        find.text(en.catalogPickerActivatedBadge),
        findsOneWidget,
      );

      // Two checkboxes, one disabled (activated row), one enabled.
      final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox))
          .toList();
      expect(checkboxes, hasLength(2));
      final disabledCount =
          checkboxes.where((c) => c.onChanged == null).length;
      expect(disabledCount, 1);
    },
  );

  testWidgets(
    'selecting N items reveals "ADD N ITEMS" button at the bottom',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeCatalogCandidate(itemId: 'item-1', displayName: 'A'),
        fakeCatalogCandidate(itemId: 'item-2', displayName: 'B'),
      ];

      await pumpPicker(tester);

      // No bottom bar yet.
      expect(
        find.widgetWithText(FilledButton, en.catalogPickerAddButton(1)),
        findsNothing,
      );

      // Select one row.
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, en.catalogPickerAddButton(1)),
        findsOneWidget,
      );

      // Select the second row.
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, en.catalogPickerAddButton(2)),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping ADD calls ensureShopItem once per selected itemId, then pops + shows success toast',
    (tester) async {
      api.onSearchItems = (_, _, _, _, _, _) async => [
        fakeCatalogCandidate(itemId: 'item-1', displayName: 'A'),
        fakeCatalogCandidate(itemId: 'item-2', displayName: 'B'),
        fakeCatalogCandidate(itemId: 'item-3', displayName: 'C'),
      ];
      final ensured = <String>[];
      api.onEnsureShopItem = (_, itemId) async {
        ensured.add(itemId);
        return 'shop-item-$itemId';
      };

      // Push from a host so we can observe the pop.
      await tester.pumpWidget(
        wrapWithApp(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CatalogPickerScreen(shop: shop),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          shopApi: api,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Select two rows.
      await tester.tap(find.text('A'));
      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();

      // Tap ADD.
      await tester.tap(
        find.widgetWithText(FilledButton, en.catalogPickerAddButton(2)),
      );
      await tester.pumpAndSettle();

      // ensureShopItem called once per selected itemId.
      expect(ensured, containsAll(<String>['item-1', 'item-3']));
      expect(ensured, hasLength(2));

      // Popped back to the host.
      expect(find.text('open'), findsOneWidget);

      // Success toast.
      expect(find.text(en.catalogPickerAddedToast(2)), findsOneWidget);
    },
  );
}
