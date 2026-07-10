import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/shared/stock_format.dart';

void main() {
  group('formatCompoundStock', () {
    test('strips the number prefix then annotates the packaging size', () {
      // 498 kg, sack = 50 kg → "9 Sack(50kg) + 48kg" (NOT "9 50 Sack …").
      expect(
        formatCompoundStock(
          stock: 498,
          baseLabel: 'kg',
          packagingLabel: '50 Sack',
          conversion: 50,
        ),
        '9 Sack(50kg) + 48kg',
      );
    });

    test('strips a "{conv} {base} {unit}" label then annotates size', () {
      // 47 kg, bag = 25 kg, label "25 Kg Bag" → "1 Bag(25kg) + 22kg".
      expect(
        formatCompoundStock(
          stock: 47,
          baseLabel: 'kg',
          packagingLabel: '25 Kg Bag',
          conversion: 25,
        ),
        '1 Bag(25kg) + 22kg',
      );
    });

    test('no remainder → count + sized noun only', () {
      expect(
        formatCompoundStock(
          stock: 500,
          baseLabel: 'kg',
          packagingLabel: '50 Sack',
          conversion: 50,
        ),
        '10 Sack(50kg)',
      );
    });

    test('less than one packaging falls back to base units', () {
      expect(
        formatCompoundStock(
          stock: 22,
          baseLabel: 'kg',
          packagingLabel: '25 Kg Bag',
          conversion: 25,
        ),
        '22kg',
      );
    });

    test('a label with no conversion prefix still gets a size annotation', () {
      expect(
        formatCompoundStock(
          stock: 47,
          baseLabel: 'kg',
          packagingLabel: 'Bag',
          conversion: 25,
        ),
        '1 Bag(25kg) + 22kg',
      );
    });

    test('fractional remainder keeps the sized noun', () {
      expect(
        formatCompoundStock(
          stock: 498.5,
          baseLabel: 'kg',
          packagingLabel: '50 Sack',
          conversion: 50,
        ),
        '9 Sack(50kg) + 48.5kg',
      );
    });

    test('base packaging (conversion 1) shows plain base units', () {
      expect(
        formatCompoundStock(
          stock: 20,
          baseLabel: 'kg',
          packagingLabel: 'Kg',
          conversion: 1,
        ),
        '20kg',
      );
    });

    test('negative stock bypasses compound math', () {
      expect(
        formatCompoundStock(
          stock: -3,
          baseLabel: 'kg',
          packagingLabel: '50 Sack',
          conversion: 50,
        ),
        '-3kg',
      );
    });

    test('spelled-out base unit keeps a space ("143 piece"), abbrev does not',
        () {
      // "piece" is a word → space; matches the readable "143 piece".
      expect(
        formatCompoundStock(stock: 143, baseLabel: 'piece'),
        '143 piece',
      );
      // Abbreviated units stay glued.
      expect(formatCompoundStock(stock: 40, baseLabel: 'kg'), '40kg');
      expect(formatCompoundStock(stock: 2, baseLabel: 'L'), '2L');
    });

    test('compact mode drops the size annotation + remainder (grid tiles)', () {
      // 498 kg, sack = 50 kg → "9 Sack" (not "9 Sack(50kg) + 48kg").
      expect(
        formatCompoundStock(
          stock: 498,
          baseLabel: 'kg',
          packagingLabel: '50 Sack',
          conversion: 50,
          compact: true,
        ),
        '9 Sack',
      );
      // Less than one packaging still falls back to base.
      expect(
        formatCompoundStock(
          stock: 22,
          baseLabel: 'kg',
          packagingLabel: '25 Kg Bag',
          conversion: 25,
          compact: true,
        ),
        '22kg',
      );
    });

    test('packagingCountNoun strips the size prefix', () {
      expect(
        packagingCountNoun(
          packagingLabel: '12 Bottle Carton',
          conversion: 12,
          baseLabel: 'bottle',
        ),
        'Carton',
      );
    });

    test('word base unit spaces inside the packaging size too', () {
      // Box of 12 pieces, 30 in stock → "2 Box(12 piece) + 6 piece".
      expect(
        formatCompoundStock(
          stock: 30,
          baseLabel: 'piece',
          packagingLabel: '12 Box',
          conversion: 12,
        ),
        '2 Box(12 piece) + 6 piece',
      );
    });

    test('fractional stock rounds to a single decimal place', () {
      // Long binary-fraction tails collapse to one decimal on every page.
      expect(formatCompoundStock(stock: 12.53, baseLabel: 'kg'), '12.5kg');
      expect(formatCompoundStock(stock: 12.549, baseLabel: 'kg'), '12.5kg');
      expect(formatCompoundStock(stock: 12.55, baseLabel: 'kg'), '12.6kg');
      // Whole values stay whole (no ".0").
      expect(formatCompoundStock(stock: 12, baseLabel: 'kg'), '12kg');
      // The compound remainder is rounded too.
      expect(
        formatCompoundStock(
          stock: 27.53,
          baseLabel: 'kg',
          packagingLabel: '25 Bag',
          conversion: 25,
        ),
        '1 Bag(25kg) + 2.5kg',
      );
    });
  });
}
