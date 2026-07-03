import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/shared/low_stock.dart';

void main() {
  group('stockLevel', () {
    test('with a threshold: <1 red, [1..threshold] yellow, >threshold green',
        () {
      expect(stockLevel(currentStock: 0.5, reorderThreshold: 5), StockLevel.out);
      expect(stockLevel(currentStock: 0, reorderThreshold: 5), StockLevel.out);
      expect(stockLevel(currentStock: 1, reorderThreshold: 5), StockLevel.low);
      expect(stockLevel(currentStock: 5, reorderThreshold: 5), StockLevel.low);
      expect(stockLevel(currentStock: 6, reorderThreshold: 5),
          StockLevel.healthy);
    });

    test('no threshold → 1 is used: <1 red, ==1 yellow, >1 green', () {
      expect(stockLevel(currentStock: 0.9), StockLevel.out);
      expect(stockLevel(currentStock: 1), StockLevel.low);
      expect(stockLevel(currentStock: 2), StockLevel.healthy);
    });

    test('null / negative stock is out (red)', () {
      expect(stockLevel(currentStock: null), StockLevel.out);
      expect(stockLevel(currentStock: -3, reorderThreshold: 5), StockLevel.out);
    });
  });
}
