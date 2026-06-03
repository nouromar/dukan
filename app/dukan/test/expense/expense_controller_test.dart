import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/expense/expense_controller.dart';

void main() {
  group('ExpenseController', () {
    test('defaults to no category and zero amount', () {
      final c = ExpenseController();
      expect(c.category, isNull);
      expect(c.amount, 0);
    });

    test('setCategory sets and notifies; same category is a no-op', () {
      final c = ExpenseController();
      var notified = 0;
      c.addListener(() => notified++);

      const rent = ExpenseCategoryOption(
        id: 'cat-rent',
        code: 'rent',
        name: 'Rent',
      );
      c.setCategory(rent);
      expect(c.category, rent);
      expect(notified, 1);

      c.setCategory(rent);
      expect(notified, 1);
    });

    test('setAmount clamps negatives to zero', () {
      final c = ExpenseController();
      c.setAmount(-25);
      expect(c.amount, 0);
      c.setAmount(50);
      expect(c.amount, 50);
    });

    test('clearAll resets both', () {
      final c = ExpenseController();
      c.setCategory(
        const ExpenseCategoryOption(id: 'c1', code: 'rent', name: 'Rent'),
      );
      c.setAmount(80);
      c.clearAll();
      expect(c.category, isNull);
      expect(c.amount, 0);
    });
  });
}
