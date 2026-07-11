import 'dart:async';

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

  // Opens the "How is it sold?" dropdown and picks [label].
  Future<void> pickSoldUnit(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<UnitOption>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'initial layout: name prefilled, unit dropdown shown, ADD TO SALE disabled,'
    ' price hidden until a unit is picked',
    (tester) async {
      await pumpAndOpen(tester, initialName: 'Caano');

      expect(find.text('Caano'), findsOneWidget);
      // The "How is it sold?" dropdown (label + the control).
      expect(find.text(en.addNewItemHowSoldHeader), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<UnitOption>), findsOneWidget);
      // No price field yet.
      expect(
        find.textContaining(en.addNewItemPickedPriceLabel('')),
        findsNothing,
      );

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.addNewItemAddToSaleButton),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'sale: picking a unit surfaces the price field; SAVE enables with a price',
    (tester) async {
      await pumpAndOpen(tester, initialName: 'Caano');
      await pickSoldUnit(tester, 'Kg');

      expect(
        find.text(en.addNewItemPickedPriceLabel('Kg')),
        findsOneWidget,
      );

      // No price typed → still disabled.
      final disabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.addNewItemAddToSaleButton),
      );
      expect(disabled.onPressed, isNull);

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

      await pickSoldUnit(tester, 'Kg');
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
      await pickSoldUnit(tester, 'Kg');
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
    'initialPack* pre-selects the unit (base-only) → SAVE lit with no tap;'
    ' createShopItem uses the pack unit as the base',
    (tester) async {
      final read = await pumpAndOpen(
        tester,
        initialName: 'BSMTI',
        variant: AddNewItemVariant.receive,
        initialBaseUnitCode: 'kg',
        initialPackUnitCode: 'bag',
        initialPackSize: 25,
      );

      // The dropdown is pre-selected to the pack (selling) unit as base-only:
      // the receive SAVE is enabled without any tap.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, en.addNewItemAddToReceiveButton),
      );
      expect(button.onPressed, isNotNull);

      await tester.tap(
        find.widgetWithText(FilledButton, en.addNewItemAddToReceiveButton),
      );
      await tester.pumpAndSettle();

      final call = api.createShopItemCalls.single;
      expect(call.baseUnitCode, 'bag'); // pack unit preferred, base-only
      expect(call.soldUnitCode, isNull);
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

  // --- Product variant: "How is it sold?" is a plain all-units dropdown ----

  testWidgets(
    'product: pick a unit + price → base-only createShopItem, never posts stock',
    (tester) async {
      final read = await pumpAndOpen(
        tester,
        initialName: 'Bariis',
        variant: AddNewItemVariant.product,
      );
      await pickSoldUnit(tester, 'Kg');

      // Fields: name(0), price(1) — the opening-stock section is gone; stock
      // is set later via the detail screen's adjust sheet.
      await tester.enterText(find.byType(TextField).at(1), '45');
      await tester.pump();

      await tester.tap(
        find.widgetWithText(FilledButton, en.addNewItemSaveButton),
      );
      await tester.pumpAndSettle();

      final create = api.createShopItemCalls.single;
      expect(create.baseUnitCode, 'kg');
      expect(create.soldUnitCode, isNull); // base-only — no pack at create
      expect(create.salePrice, 45);
      expect(create.defaultSide, 'sale');
      // Base-only → base is default for both sides, no extra flag call.
      expect(api.setShopItemUnitDefaultFlagsCalls, isEmpty);
      // Creating a product never posts an inventory adjustment.
      expect(api.postInventoryAdjustmentCalls, isEmpty);
      expect(read(), isNotNull);
    },
  );

  testWidgets(
    'product: a hung create times out → queued, sheet still closes (no wedge)',
    (tester) async {
      // The first network call hangs (cold radio). The 8s timeout must recover
      // into the queue path instead of leaving SAVE stuck spinning.
      api.onCreateShopItem =
          (_, _, _, _, _, _, _, _, _) => Completer<CreateShopItemResult>().future;

      final drained = <PendingPost>[];
      final queue = OfflineQueueController(
        dao: PendingPostDao(AppDatabase.instance()),
        executor: (p) async => drained.add(p),
        backoff: (_) => Duration.zero,
        clock: () => DateTime.utc(2026, 7, 2),
      );
      addTearDown(queue.dispose);

      var closed = false;
      await tester.pumpWidget(
        wrapWithApp(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    await AddNewItemSheet.show(
                      context,
                      shop,
                      initialName: 'Rice',
                      variant: AddNewItemVariant.product,
                    );
                    closed = true;
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
      await tester.tap(find.byType(DropdownButtonFormField<UnitOption>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kg').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '10'); // price
      await tester.pump();

      await tester.tap(
        find.widgetWithText(FilledButton, en.addNewItemSaveButton),
      );
      await tester.pump(); // kick off the save
      await tester.pump(const Duration(seconds: 9)); // fire the 8s timeout
      await tester.pumpAndSettle();

      expect(closed, isTrue, reason: 'the sheet must close, not wedge');
      expect(
        drained.where((p) => p.rpc == 'create_shop_item'),
        isNotEmpty,
      );
    },
  );

  testWidgets('product "Save & add another" keeps the sheet open, cleared',
      (tester) async {
    await pumpAndOpen(
      tester,
      initialName: 'First',
      variant: AddNewItemVariant.product,
    );
    await pickSoldUnit(tester, 'Kg');
    await tester.enterText(find.byType(TextField).at(1), '45');
    await tester.pump();

    await tester.tap(
      find.widgetWithText(
        OutlinedButton,
        en.addNewItemSaveAndAddAnotherButton,
      ),
    );
    await tester.pumpAndSettle();

    // Saved once, sheet still open with the unit reset for the next item.
    expect(api.createShopItemCalls, hasLength(1));
    expect(find.text(en.addProductSheetTitle), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<UnitOption>), findsOneWidget);
  });

}
