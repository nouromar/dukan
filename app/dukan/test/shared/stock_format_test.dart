import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/shared/stock_format.dart';

void main() {
  group('formatCompoundStock', () {
    test('strips a number-prefixed packaging label down to the bare noun', () {
      // 498 kg, sack = 50 kg → "9 Sack + 48 kg" (NOT "9 50 Sack + 48 kg").
      expect(
        formatCompoundStock(
          stock: 498,
          baseLabel: 'kg',
          packagingLabel: '50 Sack',
          conversion: 50,
        ),
        '9 Sack + 48 kg',
      );
    });

    test('strips a "{conv} {base} {unit}" label down to the unit noun', () {
      // 47 kg, bag = 25 kg, label "25 Kg Bag" → "1 Bag + 22 kg".
      expect(
        formatCompoundStock(
          stock: 47,
          baseLabel: 'kg',
          packagingLabel: '25 Kg Bag',
          conversion: 25,
        ),
        '1 Bag + 22 kg',
      );
    });

    test('no remainder → count + bare noun only', () {
      expect(
        formatCompoundStock(
          stock: 500,
          baseLabel: 'kg',
          packagingLabel: '50 Sack',
          conversion: 50,
        ),
        '10 Sack',
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
        '22 kg',
      );
    });

    test('a label with no conversion prefix passes through unchanged', () {
      expect(
        formatCompoundStock(
          stock: 47,
          baseLabel: 'kg',
          packagingLabel: 'Bag',
          conversion: 25,
        ),
        '1 Bag + 22 kg',
      );
    });

    test('fractional remainder keeps the bare noun', () {
      expect(
        formatCompoundStock(
          stock: 498.5,
          baseLabel: 'kg',
          packagingLabel: '50 Sack',
          conversion: 50,
        ),
        '9 Sack + 48.5 kg',
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
        '20 kg',
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
        '-3 kg',
      );
    });
  });
}
