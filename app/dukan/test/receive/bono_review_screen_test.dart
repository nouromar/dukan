import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/receive/bono_review_screen.dart';
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

// A matched item whose OCR pack is NEW to it (0114 new_packaging=true): the
// item resolves (si/siu), but the AI proposes a carton of 12 the item lacks.
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

  Widget host(List<BonoSuggestion> suggestions) => wrapWithApp(
        BonoReviewScreen(suggestions: suggestions, shop: shop),
        shopApi: api,
      );

  testWidgets('high starts Ready, med/new start Needs review, Accept gated',
      (tester) async {
    await tester.pumpWidget(host([
      _bound(lineNo: 1, confidence: 'high'),
      _bound(lineNo: 2, confidence: 'med'),
      _newItem(lineNo: 3),
    ]));
    await tester.pumpAndSettle();

    expect(find.text(en.bonoReviewStatusReady), findsOneWidget);
    expect(find.text(en.bonoReviewStatusNeedsReview), findsOneWidget); // med
    expect(find.text(en.bonoReviewStatusNewItem), findsOneWidget); // new item
    // 2 of 3 need review → Accept disabled with the gate label.
    expect(find.text(en.bonoReviewAcceptGate(2, 3)), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(en.bonoReviewAcceptGate(2, 3)),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('Mark ready flips a med line green → Accept enabled',
      (tester) async {
    await tester.pumpWidget(host([_bound(lineNo: 1, confidence: 'med')]));
    await tester.pumpAndSettle();

    expect(find.text(en.bonoReviewAcceptGate(1, 1)), findsOneWidget);
    await tester.tap(find.text(en.bonoReviewMarkReady));
    await tester.pumpAndSettle();

    expect(find.text(en.bonoReviewStatusReady), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(en.bonoReviewAccept(1)),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('Flag for review sends a green line back to amber',
      (tester) async {
    await tester.pumpWidget(host([_bound(lineNo: 1, confidence: 'high')]));
    await tester.pumpAndSettle();

    // Green + acceptable to start.
    expect(find.text(en.bonoReviewAccept(1)), findsOneWidget);

    // Open the Ready ▾ menu → Flag for review.
    await tester.tap(find.text(en.bonoReviewStatusReady));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.bonoReviewFlag));
    await tester.pumpAndSettle();

    expect(find.text(en.bonoReviewStatusNeedsReview), findsOneWidget);
    expect(find.text(en.bonoReviewAcceptGate(1, 1)), findsOneWidget);
  });

  testWidgets('Remove drops a line from the review + the count',
      (tester) async {
    await tester.pumpWidget(host([
      _bound(lineNo: 1, confidence: 'high'),
      _newItem(lineNo: 2),
    ]));
    await tester.pumpAndSettle();

    // 1 amber (new item) → gate says 1 of 2. Remove it via the ▾ menu.
    expect(find.text(en.bonoReviewAcceptGate(1, 2)), findsOneWidget);
    await tester.tap(find.text(en.bonoReviewStatusNewItem));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.bonoReviewRemove));
    await tester.pumpAndSettle();

    // Only the green line remains → Accept 1.
    expect(find.text(en.bonoReviewAccept(1)), findsOneWidget);
  });

  testWidgets(
    'Create on a new line → one-tap create_shop_item materializes the AI pack',
    (tester) async {
      // _newItem seeds base 'piece', pack 'packet', size 24 — resolvable from
      // the default fake listUnits().
      await tester.pumpWidget(host([_newItem(lineNo: 1, categoryName: 'Snacks')]));
      await tester.pumpAndSettle();

      await tester.tap(find.text(en.bonoReviewCreateItem('NEW 1')));
      await tester.pumpAndSettle();

      // No full sheet — the item is created in one call with base = small unit
      // and the received pack as the default-receive packaging.
      expect(
          find.widgetWithText(FilledButton, en.addNewItemAddToReceiveButton),
          findsNothing);
      final call = api.createShopItemCalls.single;
      expect(call.baseUnitCode, 'piece');
      expect(call.soldUnitCode, 'packet');
      expect(call.soldConversion, 24);
      expect(call.defaultSide, 'receive');
      // Line is now Ready → Accept enabled.
      expect(find.text(en.bonoReviewStatusReady), findsOneWidget);
      expect(find.text(en.bonoReviewAccept(1)), findsOneWidget);
    },
  );

  testWidgets('Edit before creating still opens the full sheet',
      (tester) async {
    await tester.pumpWidget(host([_newItem(lineNo: 1)]));
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.bonoReviewStatusNewItem));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.bonoReviewEditNew));
    await tester.pumpAndSettle();

    // The full new-item sheet is up (its receive SAVE button is present).
    expect(find.widgetWithText(FilledButton, en.addNewItemAddToReceiveButton),
        findsOneWidget);
  });

  testWidgets('new-size line → Add packaging adds the AI pack + rebinds Ready',
      (tester) async {
    await tester.pumpWidget(host([_newPack(lineNo: 1)]));
    await tester.pumpAndSettle();

    // Even a high-confidence match with a genuinely new pack starts amber.
    expect(find.text(en.bonoReviewStatusNewSize), findsOneWidget);
    expect(find.text(en.bonoReviewAcceptGate(1, 1)), findsOneWidget);

    final label = en.bonoReviewAddPackaging(packagingLabel(12, 'Kg', 'Carton'));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();

    // The AI's pack is added to the matched item and the line rebinds to it.
    final call = api.createShopItemUnitCalls.single;
    expect(call.shopItemId, 'si-1');
    expect(call.unitCode, 'carton');
    expect(call.conversionToBase, 12);
    expect(find.text(en.bonoReviewStatusReady), findsOneWidget);
    expect(find.text(en.bonoReviewAccept(1)), findsOneWidget);
  });

  testWidgets('Keep current packaging confirms a new-size line without adding',
      (tester) async {
    await tester.pumpWidget(host([_newPack(lineNo: 1)]));
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.bonoReviewStatusNewSize));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.bonoReviewKeepPackaging));
    await tester.pumpAndSettle();

    expect(find.text(en.bonoReviewStatusReady), findsOneWidget);
    expect(api.createShopItemUnitCalls, isEmpty);
  });

  testWidgets('category chip marks AI proposals on new lines only',
      (tester) async {
    await tester.pumpWidget(host([
      _bound(lineNo: 1, confidence: 'high', categoryName: 'Staples'),
      _newItem(lineNo: 2, categoryName: 'Snacks'),
    ]));
    await tester.pumpAndSettle();

    // Matched line: plain category. New line: category + "New" marker.
    expect(find.text('Staples'), findsOneWidget);
    expect(find.text('Snacks · ${en.bonoReviewNewItem}'), findsOneWidget);
  });
}
