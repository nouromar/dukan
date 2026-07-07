import 'package:flutter_test/flutter_test.dart';
import 'package:dukan/api/shop_api.dart';

void main() {
  group('BonoSuggestion.fromJson', () {
    test('parses a bound high-confidence supplier-alias line', () {
      final s = BonoSuggestion.fromJson({
        'line_no': 1,
        'raw_text': 'BSMTI 25KG',
        'suggested_shop_item_id': 'item-1',
        'suggested_shop_item_unit_id': 'unit-1',
        'item_id': 'catalog-1',
        'display_name': 'Bariis Basmati',
        'unit_code': 'bag25',
        'base_unit_code': 'kg',
        'conversion_to_base': 25,
        'quantity': 4,
        'unit_price': 20,
        'line_total': 80,
        'confidence': 'high',
        'reason': 'supplier_alias',
      });
      expect(s.lineNo, 1);
      expect(s.rawText, 'BSMTI 25KG');
      expect(s.isBound, isTrue);
      expect(s.suggestedShopItemUnitId, 'unit-1');
      expect(s.quantity, 4);
      expect(s.lineTotal, 80);
      expect(s.confidence, 'high');
      expect(s.reason, 'supplier_alias');
    });

    test('parses an unbound no-match line with sensible defaults', () {
      final s = BonoSuggestion.fromJson({
        'line_no': 3,
        'raw_text': 'ZZZ UNKNOWN',
        'suggested_shop_item_id': null,
        'suggested_shop_item_unit_id': null,
        'item_id': null,
        'display_name': null,
        'unit_code': null,
        'conversion_to_base': null,
        'quantity': null,
        'unit_price': null,
        'line_total': null,
        'confidence': null,
        'reason': null,
      });
      expect(s.isBound, isFalse);
      expect(s.quantity, 1); // default
      expect(s.confidence, 'low'); // default
      expect(s.reason, 'no_match'); // default
      expect(s.lineTotal, isNull);
    });
  });
}
