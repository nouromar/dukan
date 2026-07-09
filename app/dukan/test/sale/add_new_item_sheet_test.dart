import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/sale/add_new_item_sheet.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/pending_post_dao.dart';

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
    // Default suggestions: kg base + 25-Kg bag packaging in same group,
    // plus a packet base. Covers both sold-in-base + sold-packaged
    // paths without needing per-test plumbing.
    api.onFetchNewItemOptions = (_, _) async => const NewItemOptions(
          baseUnits: [
            BaseUnitOption(unitCode: 'kg', unitLabel: 'Kg', uses: 3),
            BaseUnitOption(
              unitCode: 'packet',
              unitLabel: 'Packet',
              uses: 5,
            ),
          ],
          packagedUnits: [
            PackagedUnitSuggestion(
              unitCode: 'bag',
              unitLabel: 'Bag',
              conversionToBase: 25,
              baseUnitCode: 'kg',
              baseUnitLabel: 'Kg',
              uses: 6,
              source: 'category',
            ),
          ],
        );
  });

  /// Pump a host with a button that opens the sale-variant Add New Item sheet
  /// pre-filled with [initialName]. Returns a closure that reads the captured
  /// result after the sheet is dismissed.
  Future<AddNewItemResult? Function()> pumpAndOpen(
    WidgetTester tester, {
    String initialName = 'New Soap',
    AddNewItemVariant variant = AddNewItemVariant.sale,
    String? initialBaseUnitCode,
    String? initialPackUnitCode,
    num? initialPackSize,
  }) async {
    AddNewItemResult? captured;
    var didCapture = false;
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  captured = await AddNewItemSheet.show(
                    context,
                    shop,
                    initialName: initialName,
                    variant: variant,
                    initialBaseUnitCode: initialBaseUnitCode,
                    initialPackUnitCode: initialPackUnitCode,
                    initialPackSize: initialPackSize,
                  );
                  didCapture = true;
                },
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
    return () => didCapture ? captured : null;
  }

  testWidgets(
    'initial layout: name prefilled, trigger shows the prompt, ADD TO SALE'
    ' disabled, price field hidden until pick',
    (tester) async {
      await pumpAndOpen(tester, initialName: 'Caano');

      // Name prefilled.
      expect(find.text('Caano'), findsOneWidget);
      // Trigger placeholder shows the variant prompt.
      expect(find.text(en.addNewItemHowSoldHeader), findsOneWidget);
      // Chips are NOT inline — they live in the sub-picker until tapped.
      expect(find.text(en.addNewItemBaseOnlyTile('Kg')), findsNothing);
      expect(
        find.textContaining(en.addNewItemPickedPriceLabel('')),
        findsNothing,
      );

      // ADD TO SALE button disabled.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.addNewItemAddToSaleButton),
      );
      expect(button.onPressed, isNull);

      // Tier 1 chips render inline on the main sheet (no sub-sheet trip).
      expect(find.text(en.addNewItemLooseType), findsOneWidget);
      expect(find.text('Bag'), findsOneWidget);
      expect(
        find.text(en.addNewItemCustomPackagingEntry),
        findsOneWidget,
      );
      // Tier 2 chips not yet visible — they live in the sub-sheet that
      // opens when the type has multiple sizes.
      expect(find.text(en.addNewItemBaseOnlyTile('Kg')), findsNothing);
      expect(find.text('25 Kg Bag'), findsNothing);

      // Tap "Loose" → sub-sheet opens with the base-unit chips.
      await tester.tap(find.text(en.addNewItemLooseType));
      await tester.pumpAndSettle();
      expect(find.text(en.addNewItemBaseOnlyTile('Kg')), findsOneWidget);
      expect(find.text(en.addNewItemBaseOnlyTile('Packet')), findsOneWidget);
    },
  );

  testWidgets(
    'picking a base-only chip closes the sub-picker, surfaces the price'
    ' field on the main sheet with a packaging-aware label',
    (tester) async {
      await pumpAndOpen(tester, initialName: 'Caano');

      // Inline Loose chip → sub-sheet base-units → By Kg.
      await tester.tap(find.text(en.addNewItemLooseType));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.addNewItemBaseOnlyTile('Kg')));
      await tester.pumpAndSettle();

      expect(
        find.text(en.addNewItemPickedPriceLabel('Kg')),
        findsOneWidget,
      );

      // No price typed → still disabled.
      final disabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.addNewItemAddToSaleButton),
      );
      expect(disabled.onPressed, isNull);

      // Type a price.
      await tester.enterText(find.byType(TextField).last, '2.5');
      await tester.pump();

      final enabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.addNewItemAddToSaleButton),
      );
      expect(enabled.onPressed, isNotNull);
    },
  );

  testWidgets(
    'sale base-only confirm: createShopItem called sold-in-base, popped result'
    ' carries the synthesized base label',
    (tester) async {
      ({
        String shopId,
        String name,
        String languageCode,
        String baseUnitCode,
        num? salePrice,
        String? soldUnitCode,
        num? soldConversion,
        String defaultSide,
      })?
      createCall;
      api.onCreateShopItem =
          (
            shopId,
            name,
            lang,
            baseUnit,
            price,
            _,
            soldUnitCode,
            soldConversion,
            defaultSide,
          ) async {
            createCall = (
              shopId: shopId,
              name: name,
              languageCode: lang,
              baseUnitCode: baseUnit,
              salePrice: price,
              soldUnitCode: soldUnitCode,
              soldConversion: soldConversion,
              defaultSide: defaultSide,
            );
            return (
              shopItemId: 'new-shop-item-id',
              defaultShopItemUnitId: 'new-siu-id',
            );
          };

      final readResult = await pumpAndOpen(tester, initialName: 'Caano');

      await tester.tap(find.text(en.addNewItemLooseType));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.addNewItemBaseOnlyTile('Kg')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '2.5');
      await tester.pump();

      await tester.tap(
        find.widgetWithText(FilledButton, en.addNewItemAddToSaleButton),
      );
      await tester.pumpAndSettle();

      expect(createCall, isNotNull);
      expect(createCall!.baseUnitCode, 'kg');
      expect(createCall!.soldUnitCode, isNull);
      expect(createCall!.soldConversion, isNull);
      expect(createCall!.defaultSide, 'sale');
      expect(createCall!.salePrice, 2.5);

      // The sheet mints the item + base-unit ids client-side (0095) and
      // returns THOSE — the same ids it sent to create_shop_item — not the
      // server's. Base-only, so the default unit is the base unit.
      final result = readResult();
      expect(result, isNotNull);
      expect(result!.shopItemId, isNotEmpty);
      expect(result.shopItemId, api.createShopItemCalls.last.shopItemId);
      expect(result.shopItemUnitId, api.createShopItemCalls.last.baseUnitId);
      expect(api.createShopItemCalls.last.soldUnitId, isNull);
      expect(api.createShopItemCalls.last.clientOpId, isNotNull);
      expect(result.packagingLabel, 'Kg');
      expect(result.baseUnitLabel, 'Kg');
      expect(result.salePrice, 2.5);
    },
  );

  testWidgets(
    'sale packaged confirm: createShopItem called with sold packaging,'
    ' packaging label synthesized "25 Kg Bag"',
    (tester) async {
      ({
        String? soldUnitCode,
        num? soldConversion,
        String defaultSide,
      })?
      createCall;
      api.onCreateShopItem =
          (_, _, _, _, _, _, soldUnitCode, soldConversion, defaultSide) async {
            createCall = (
              soldUnitCode: soldUnitCode,
              soldConversion: soldConversion,
              defaultSide: defaultSide,
            );
            return (
              shopItemId: 'new-shop-item-id',
              defaultShopItemUnitId: 'new-siu-id',
            );
          };

      final readResult = await pumpAndOpen(tester, initialName: 'Bariis');

      // Tap the inline "Bag" type chip. Since Bag has only one size in
      // the fixture, the main sheet auto-picks 25 Kg Bag — no sub-sheet
      // trip.
      await tester.tap(find.text('Bag'));
      await tester.pumpAndSettle();

      expect(
        find.text(en.addNewItemPickedPriceLabel('25 Kg Bag')),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).last, '120');
      await tester.pump();

      await tester.tap(
        find.widgetWithText(FilledButton, en.addNewItemAddToSaleButton),
      );
      await tester.pumpAndSettle();

      expect(createCall!.soldUnitCode, 'bag');
      expect(createCall!.soldConversion, 25);
      expect(createCall!.defaultSide, 'sale');

      final result = readResult()!;
      expect(result.packagingLabel, '25 Kg Bag');
      expect(result.baseUnitCode, 'kg');
      expect(result.baseUnitLabel, 'Kg');
      // Distinct sold packaging (0095): the client minted a separate sold
      // unit id, and it's the one dropped into the cart (the default).
      final call = api.createShopItemCalls.last;
      expect(call.soldUnitId, isNotNull);
      expect(call.baseUnitId, isNotNull);
      expect(result.shopItemUnitId, call.soldUnitId);
    },
  );

  testWidgets('Cancel pops with null', (tester) async {
    final readResult = await pumpAndOpen(tester, initialName: 'Caano');
    await tester.tap(
      find.widgetWithText(OutlinedButton, en.addNewItemCancelButton),
    );
    await tester.pumpAndSettle();
    expect(readResult(), isNull);
  });

  testWidgets(
    'offline: new item is queued with the client ids, not lost',
    (tester) async {
      // Direct create fails as if offline (transient — NOT a server reject).
      api.onCreateShopItem =
          (_, _, _, _, _, _, _, _, _) async => throw Exception('offline');

      final drained = <PendingPost>[];
      final queue = OfflineQueueController(
        dao: PendingPostDao(AppDatabase.instance()),
        executor: (p) async => drained.add(p),
        backoff: (_) => Duration.zero,
        clock: () => DateTime.utc(2026, 7, 2),
      );
      addTearDown(queue.dispose);

      AddNewItemResult? captured;
      await tester.pumpWidget(
        wrapWithApp(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    captured = await AddNewItemSheet.show(
                      context,
                      shop,
                      initialName: 'Caano',
                      variant: AddNewItemVariant.sale,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          shopApi: api,
          offlineQueueController: queue,
          configResolver:
              FakeConfigResolver(values: const {'use_local_db': true}),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.addNewItemLooseType));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.addNewItemBaseOnlyTile('Kg')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '2.5');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, en.addNewItemAddToSaleButton),
      );
      await tester.pumpAndSettle();

      // The sheet still returns an item — with the client-minted ids.
      expect(captured, isNotNull);
      expect(captured!.shopItemId, isNotEmpty);
      expect(captured!.shopItemUnitId, isNotEmpty);

      // The create was queued (not lost) with those ids + a client_op_id.
      final post = drained.singleWhere((p) => p.rpc == 'create_shop_item');
      expect(post.params['shop_item_id'], captured!.shopItemId);
      expect(post.params['base_unit_id'], captured!.shopItemUnitId);
      expect(post.params['name'], 'Caano');
      expect(post.clientOpId, isNotNull);
    },
  );

  // --- AI/caller packaging prefill (bono new-item "accept as-is") -----------

  testWidgets(
    'initialPack* pre-selects the packaging → SAVE lit with no packaging tap;'
    ' createShopItem carries the sold unit + conversion',
    (tester) async {
      final read = await pumpAndOpen(
        tester,
        initialName: 'BSMTI',
        variant: AddNewItemVariant.receive,
        initialBaseUnitCode: 'kg',
        initialPackUnitCode: 'bag',
        initialPackSize: 25,
      );

      // Packaging is already chosen (async prefill resolved during settle):
      // the receive SAVE is enabled without ever tapping a packaging chip.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.addNewItemAddToReceiveButton),
      );
      expect(button.onPressed, isNotNull);

      await tester.tap(
        find.widgetWithText(FilledButton, en.addNewItemAddToReceiveButton),
      );
      await tester.pumpAndSettle();

      final call = api.createShopItemCalls.single;
      expect(call.baseUnitCode, 'kg');
      expect(call.soldUnitCode, 'bag');
      expect(call.soldConversion, 25);
      expect(read(), isNotNull);
    },
  );

  testWidgets(
    'initialBaseUnitCode with no pack → base-only pick (soldUnitCode null)',
    (tester) async {
      await pumpAndOpen(
        tester,
        initialName: 'Loose Rice',
        variant: AddNewItemVariant.receive,
        initialBaseUnitCode: 'kg',
      );

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.addNewItemAddToReceiveButton),
      );
      expect(button.onPressed, isNotNull);

      await tester.tap(
        find.widgetWithText(FilledButton, en.addNewItemAddToReceiveButton),
      );
      await tester.pumpAndSettle();

      final call = api.createShopItemCalls.single;
      expect(call.baseUnitCode, 'kg');
      expect(call.soldUnitCode, isNull);
      expect(call.soldConversion, isNull);
    },
  );

  testWidgets(
    'unresolvable initialBaseUnitCode → no pre-select (SAVE stays disabled)',
    (tester) async {
      await pumpAndOpen(
        tester,
        initialName: 'Mystery',
        variant: AddNewItemVariant.receive,
        initialBaseUnitCode: 'zzz_not_a_unit',
        initialPackUnitCode: 'also_bogus',
        initialPackSize: 12,
      );

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.addNewItemAddToReceiveButton),
      );
      expect(button.onPressed, isNull);
    },
  );
}
