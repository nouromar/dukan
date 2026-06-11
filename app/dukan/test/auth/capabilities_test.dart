import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/auth/capabilities.dart';

void main() {
  test('empty() has no codes and all gates default to false', () {
    final c = Capabilities.empty();
    expect(c.codes, isEmpty);
    expect(c.canPostSale, isFalse);
    expect(c.canVoidSale, isFalse);
    expect(c.canEditProducts, isFalse);
    expect(c.has('anything.at.all'), isFalse);
  });

  test('fromRaw parses a List<dynamic> of String', () {
    final c =
        Capabilities.fromRaw(<dynamic>['sales.post', 'sales.history.view']);
    expect(c.codes, {'sales.post', 'sales.history.view'});
    expect(c.canPostSale, isTrue);
    expect(c.canViewSalesHistory, isTrue);
    expect(c.canVoidSale, isFalse);
  });

  test('fromRaw on non-iterable falls back to empty', () {
    expect(Capabilities.fromRaw(null).codes, isEmpty);
    expect(Capabilities.fromRaw('not a list').codes, isEmpty);
    expect(Capabilities.fromRaw(42).codes, isEmpty);
  });

  test('cashier baseline gates allow daily flows but not owner-only', () {
    final c = Capabilities.forTesting([
      'sales.post',
      'sales.history.view',
      'receive.post',
      'payment.post',
      'expense.post',
      'inventory.product.view',
      'people.party.create',
      'dashboard.view',
    ]);
    expect(c.canPostSale, isTrue);
    expect(c.canViewSalesHistory, isTrue);
    expect(c.canPostReceive, isTrue);
    expect(c.canPostPayment, isTrue);
    expect(c.canPostExpense, isTrue);
    expect(c.canViewProducts, isTrue);
    expect(c.canCreateParty, isTrue);
    expect(c.canViewDashboard, isTrue);
    // Owner-only must remain false
    expect(c.canVoidSale, isFalse);
    expect(c.canVoidReceive, isFalse);
    expect(c.canEditProducts, isFalse);
    expect(c.canAdjustStock, isFalse);
    expect(c.canEditShopSettings, isFalse);
    expect(c.canPostOpeningBalance, isFalse);
  });

  test('owner profile gates allow everything in the v1 set', () {
    final c = Capabilities.forTesting([
      'sales.post', 'sales.history.view', 'sales.void', 'sales.export',
      'receive.post', 'receive.history.view', 'receive.void',
      'payment.post', 'payment.history.view',
      'expense.post', 'expense.history.view',
      'inventory.product.view', 'inventory.product.edit',
      'inventory.product.create', 'inventory.product.activate',
      'inventory.barcode.bind', 'inventory.adjustment.post',
      'people.party.view', 'people.party.create', 'people.party.edit',
      'people.party.opening_balance',
      'setup.shop.edit', 'dashboard.view',
    ]);
    expect(c.canPostSale, isTrue);
    expect(c.canVoidSale, isTrue);
    expect(c.canEditProducts, isTrue);
    expect(c.canAdjustStock, isTrue);
    expect(c.canBindBarcode, isTrue);
    expect(c.canEditShopSettings, isTrue);
    expect(c.canPostOpeningBalance, isTrue);
  });

  test('equality is structural', () {
    final a = Capabilities.forTesting(['sales.post', 'dashboard.view']);
    final b = Capabilities.forTesting(['dashboard.view', 'sales.post']);
    final c = Capabilities.forTesting(['sales.post']);
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });
}
