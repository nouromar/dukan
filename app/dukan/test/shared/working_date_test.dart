import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/shared/working_date.dart';

class _Ctrl extends ChangeNotifier with WorkingDateMixin {}

void main() {
  group('WorkingDateMixin', () {
    test('defaults to today: null, not backdated, effectiveDate ~= now', () {
      final c = _Ctrl();
      expect(c.workingDate, isNull);
      expect(c.isBackdated, isFalse);
      expect(
        c.effectiveDate.difference(DateTime.now()).inSeconds.abs() < 5,
        isTrue,
      );
    });

    test('setWorkingDate flips to backdated and notifies once', () {
      final c = _Ctrl();
      var notifications = 0;
      c.addListener(() => notifications++);
      final past = DateTime(2026, 1, 1, 9);
      c.setWorkingDate(past);
      expect(c.isBackdated, isTrue);
      expect(c.workingDate, past);
      expect(c.effectiveDate, past);
      expect(notifications, 1);
      // Same value again is a no-op (no extra notify).
      c.setWorkingDate(past);
      expect(notifications, 1);
    });

    test('initWorkingDate resets to today WITHOUT notifying', () {
      final c = _Ctrl();
      var notifications = 0;
      c.setWorkingDate(DateTime(2026, 1, 1));
      c.addListener(() => notifications++);
      c.initWorkingDate();
      expect(c.workingDate, isNull);
      expect(c.isBackdated, isFalse);
      expect(notifications, 0);
    });
  });

  group('post builders carry occurred_at (UTC ISO) only when backdated', () {
    final past = DateTime(2026, 1, 2, 8, 30);
    final expected = past.toUtc().toIso8601String();

    test('sale', () {
      expect(
        buildPostSaleParams(
          lines: const [],
          paidAmount: 0,
          occurredAt: past,
        )['occurred_at'],
        expected,
      );
      expect(
        buildPostSaleParams(lines: const [], paidAmount: 0)
            .containsKey('occurred_at'),
        isFalse,
      );
    });

    test('receive', () {
      expect(
        buildPostReceiveParams(
          partyId: 's',
          lines: const [],
          paidAmount: 0,
          occurredAt: past,
        )['occurred_at'],
        expected,
      );
    });

    test('payment', () {
      expect(
        buildPostPaymentParams(
          partyId: 's',
          direction: 'I',
          amount: 1,
          paymentMethodCode: 'cash',
          occurredAt: past,
        )['occurred_at'],
        expected,
      );
    });

    test('expense', () {
      expect(
        buildPostExpenseParams(
          expenseCategoryId: 'c',
          amount: 1,
          paymentMethodCode: 'cash',
          occurredAt: past,
        )['occurred_at'],
        expected,
      );
      expect(
        buildPostExpenseParams(
          expenseCategoryId: 'c',
          amount: 1,
          paymentMethodCode: 'cash',
        ).containsKey('occurred_at'),
        isFalse,
      );
    });
  });
}
