import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/receive/bono_review_screen.dart';
import 'package:dukan/receive/bono_suggestion_review_sheet.dart' show BonoApplyLine;
import 'package:dukan/shared/packaging_label.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

BonoSuggestion _bound({
  required int lineNo,
  required String confidence,
  String? categoryName,
}) =>
    BonoSuggestion.fromJson({
      'line_no': lineNo,
      'raw_text': 'RAW $lineNo',
      'suggested_shop_item_id': 'si-$lineNo',
      'suggested_shop_item_unit_id': 'siu-$lineNo',
      'item_id': 'i$lineNo',
      'display_name': 'Item $lineNo',
      'unit_code': 'bag',
      'base_unit_code': 'kg',
      'conversion_to_base': 25,
      'quantity': 3,
      'unit_price': 10,
      'line_total': 30,
      'confidence': confidence,
      'reason': confidence == 'high' ? 'supplier_alias' : 'shop_alias',
      'suggested_category_name': categoryName,
    });

// A matched item whose OCR pack is NEW to it (0114 new_packaging=true).
BonoSuggestion _newPack({required int lineNo}) => BonoSuggestion.fromJson({
      'line_no': lineNo,
      'raw_text': 'PACK $lineNo',
      'suggested_shop_item_id': 'si-$lineNo',
      'suggested_shop_item_unit_id': 'siu-$lineNo',
      'item_id': 'i$lineNo',
      'display_name': 'Item $lineNo',
      'unit_code': 'bag',
      'base_unit_code': 'kg',
      'conversion_to_base': 25,
      'quantity': 4,
      'unit_price': 10,
      'line_total': 40,
      'confidence': 'high',
      'reason': 'supplier_alias',
      'new_packaging': true,
      'suggested_base_unit_code': 'kg',
      'suggested_pack_unit_code': 'carton',
      'suggested_pack_size': 12,
    });

BonoSuggestion _newItem({required int lineNo, String? categoryName}) =>
    BonoSuggestion.fromJson({
      'line_no': lineNo,
      'raw_text': 'NEW $lineNo',
      'suggested_shop_item_id': null,
      'suggested_shop_item_unit_id': null,
      'quantity': 2,
      'line_total': 20,
      'confidence': 'low',
      'reason': 'no_match',
      'suggested_category_name': categoryName,
      'suggested_base_unit_code': 'piece',
      'suggested_pack_unit_code': 'packet',
      'suggested_pack_size': 24,
    });

void main() {
  late FakeShopApi api;
  late ShopSummary shop;
  late AppLocalizations en;

  setUp(() {
    api = FakeShopApi();
    shop = fakeShop();
    en = lookupAppLocalizations(const Locale('en'));
  });

  // Pump the screen directly — for pure-UI assertions that don't Save (Save
  // pops the route).
  Widget host(List<BonoSuggestion> suggestions) => wrapWithApp(
        BonoReviewScreen(suggestions: suggestions, shop: shop),
        shopApi: api,
      );

  // Push the screen via openBonoReview and capture what Save returns.
  Future<List<BonoApplyLine>? Function()> pushReview(
    WidgetTester tester,
    List<BonoSuggestion> suggestions,
  ) async {
    List<BonoApplyLine>? captured;
    var done = false;
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  captured = await openBonoReview(
                    context,
                    suggestions: suggestions,
                    shop: shop,
                  );
                  done = true;
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
    return () => done ? captured : null;
  }

  testWidgets(
    'matched shows no chip; new lines show amber chips; Save + lead counts',
    (tester) async {
      await tester.pumpWidget(host([
        _bound(lineNo: 1, confidence: 'high'),
        _newItem(lineNo: 2),
        _newPack(lineNo: 3),
      ]));
      await tester.pumpAndSettle();

      // Two glance cues, no per-card buttons / status pills.
      expect(find.text(en.bonoReviewNewProduct), findsOneWidget); // new item
      expect(find.text(en.bonoReviewNewPack), findsOneWidget); // new pack
      // Lead strip: 3 lines, 2 of them new.
      expect(find.text(en.bonoReviewLineCount(3)), findsOneWidget);
      expect(find.text(en.bonoReviewLinesNew(2)), findsOneWidget);
      // Save is always enabled; subtitle counts new PRODUCTS only (1).
      final save = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(en.bonoReviewSave(3)),
          matching: find.byType(FilledButton),
        ),
      );
      expect(save.onPressed, isNotNull);
      expect(find.text(en.bonoReviewSaveNew(1)), findsOneWidget);
    },
  );

  testWidgets(
    'Save materializes: new item → create_shop_item, new pack → create_shop_item_unit',
    (tester) async {
      final read = await pushReview(tester, [
        _bound(lineNo: 1, confidence: 'high'),
        _newItem(lineNo: 2),
        _newPack(lineNo: 3),
      ]);

      await tester.tap(find.text(en.bonoReviewSave(3)));
      await tester.pumpAndSettle();

      // The new product is created with the AI's base + pack, default-receive.
      final ci = api.createShopItemCalls.single;
      expect(ci.baseUnitCode, 'piece');
      expect(ci.soldUnitCode, 'packet');
      expect(ci.soldConversion, 24);
      expect(ci.defaultSide, 'receive');
      // The new pack is added to the matched item.
      final cu = api.createShopItemUnitCalls.single;
      expect(cu.unitCode, 'carton');
      expect(cu.conversionToBase, 12);
      // All three lines come back for the receive to merge.
      final out = read();
      expect(out, isNotNull);
      expect(out!.length, 3);
    },
  );

  testWidgets('matched-only Save creates nothing and returns the lines',
      (tester) async {
    final read = await pushReview(tester, [
      _bound(lineNo: 1, confidence: 'high'),
      _bound(lineNo: 2, confidence: 'med'),
    ]);

    await tester.tap(find.text(en.bonoReviewSave(2)));
    await tester.pumpAndSettle();

    expect(api.createShopItemCalls, isEmpty);
    expect(api.createShopItemUnitCalls, isEmpty);
    final out = read();
    expect(out!.map((l) => l.shopItemUnitId).toSet(), {'siu-1', 'siu-2'});
  });

  testWidgets('tap a card opens the edit sheet; changing qty updates the line',
      (tester) async {
    await tester.pumpWidget(host([_bound(lineNo: 1, confidence: 'high')]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Item 1'));
    await tester.pumpAndSettle();
    expect(find.text(en.bonoReviewEditTitle), findsOneWidget);

    // First TextField is quantity (Product/Packaging rows are InputDecorators).
    await tester.enterText(find.byType(TextField).first, '9');
    await tester.tap(find.text(en.bonoReviewEditSave));
    await tester.pumpAndSettle();

    // Sheet closed; the card reflects the new quantity.
    expect(find.text(en.bonoReviewEditTitle), findsNothing);
    expect(find.textContaining('× 9'), findsOneWidget);
  });

  testWidgets('Remove in the sheet drops the line and its Save count',
      (tester) async {
    await tester.pumpWidget(host([
      _bound(lineNo: 1, confidence: 'high'),
      _newItem(lineNo: 2),
    ]));
    await tester.pumpAndSettle();
    expect(find.text(en.bonoReviewSave(2)), findsOneWidget);

    await tester.tap(find.text('NEW 2')); // the new-item card (name = raw text)
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.bonoReviewRemove));
    await tester.pumpAndSettle();

    // One line left, and the "New product" cue is gone.
    expect(find.text(en.bonoReviewSave(1)), findsOneWidget);
    expect(find.text(en.bonoReviewNewProduct), findsNothing);
  });

  testWidgets('new-pack line: pick an existing pack in the sheet, nothing added',
      (tester) async {
    final read = await pushReview(tester, [_newPack(lineNo: 1)]);

    // Open the card; its packaging shows the AI's new pack.
    await tester.tap(find.text('Item 1'));
    await tester.pumpAndSettle();
    final aiPack = packagingLabel(12, 'Kg', 'Carton');
    await tester.tap(find.text(aiPack));
    await tester.pumpAndSettle(); // the item's packaging picker opens

    // Pick an existing pack (fake default: base Kg + 25 Kg Bag).
    await tester.tap(find.text('25 Kg Bag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.bonoReviewEditSave));
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.bonoReviewSave(1)));
    await tester.pumpAndSettle();

    // Bound to the existing pack — no new packaging created.
    expect(api.createShopItemUnitCalls, isEmpty);
    final out = read();
    expect(out!.single.shopItemUnitId, 'unit-bag-25');
  });
}
