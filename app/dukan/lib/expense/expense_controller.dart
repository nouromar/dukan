// Expense-screen state: selected category + entered amount. Lifted
// into a ChangeNotifier so the screen survives back/forward navigation
// the same way Cart, Receive, Payment do.

import 'package:flutter/foundation.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/shared/working_date.dart';

class ExpenseController extends ChangeNotifier with WorkingDateMixin {
  ExpenseCategoryOption? _category;
  num _amount = 0;

  ExpenseCategoryOption? get category => _category;
  num get amount => _amount;

  void setCategory(ExpenseCategoryOption category) {
    if (_category?.id == category.id) return;
    _category = category;
    notifyListeners();
  }

  void setAmount(num value) {
    final clamped = value < 0 ? 0 : value;
    if (_amount == clamped) return;
    _amount = clamped;
    notifyListeners();
  }

  void clearAll() {
    final wasEmpty = _category == null && _amount == 0;
    _category = null;
    _amount = 0;
    if (!wasEmpty) notifyListeners();
  }

  /// Snapshot for the optimistic-SAVE dance.
  ExpenseSnapshot snapshot() =>
      ExpenseSnapshot(category: _category, amount: _amount);

  void restore(ExpenseSnapshot snapshot) {
    _category = snapshot.category;
    _amount = snapshot.amount;
    notifyListeners();
  }
}

class ExpenseSnapshot {
  const ExpenseSnapshot({required this.category, required this.amount});

  final ExpenseCategoryOption? category;
  final num amount;
}
