import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/sale/cart_controller.dart';

import '../shared/fakes.dart';

void main() {
  group('CartController', () {
    test('starts empty', () {
      final cart = CartController();
      expect(cart.isEmpty, isTrue);
      expect(cart.itemCount, 0);
      expect(cart.total, 0);
      expect(cart.debt, isFalse);
      expect(cart.customer, isNull);
      expect(cart.held, isEmpty);
    });

    test('addItem inserts a line with qty 1 at the item default price', () {
      final cart = CartController();
      cart.addItem(fakeActivatedItem(itemId: 'i1', salePrice: 1.5));
      expect(cart.itemCount, 1);
      expect(cart.total, 1.5);
      expect(cart.lines, hasLength(1));
      expect(cart.lines['i1']!.quantity, 1);
    });

    test('addItem on the same item increments quantity', () {
      final cart = CartController();
      cart.addItem(fakeActivatedItem(itemId: 'i1', salePrice: 1.5));
      cart.addItem(fakeActivatedItem(itemId: 'i1', salePrice: 1.5));
      cart.addItem(fakeActivatedItem(itemId: 'i1', salePrice: 1.5));
      expect(cart.lines['i1']!.quantity, 3);
      expect(cart.total, 4.5);
    });

    test('catalog candidates with no item_id key by catalog_item_id', () {
      final cart = CartController();
      cart.addItem(fakeCatalogCandidate(catalogItemId: 'c1', salePrice: 2.0));
      expect(cart.itemCount, 1);
      expect(cart.lines.keys.first, 'c1');
      expect(cart.lines['c1']!.itemId, isNull);
      expect(cart.lines['c1']!.catalogItemId, 'c1');
    });

    test('removeLine drops the line and notifies', () {
      final cart = CartController();
      cart.addItem(fakeActivatedItem(itemId: 'i1'));
      cart.addItem(fakeActivatedItem(itemId: 'i2'));
      var notified = 0;
      cart.addListener(() => notified++);

      cart.removeLine('i1');
      expect(cart.lines.keys, ['i2']);
      expect(notified, 1);

      // No-op remove doesn't notify
      cart.removeLine('nonexistent');
      expect(notified, 1);
    });

    test('clearAll wipes lines + debt + customer', () {
      final cart = CartController();
      cart.addItem(fakeActivatedItem(itemId: 'i1'));
      cart.setDebt(true);
      cart.setCustomer(fakeCustomer());

      cart.clearAll();

      expect(cart.isEmpty, isTrue);
      expect(cart.debt, isFalse);
      expect(cart.customer, isNull);
    });

    test('snapshot/restore round-trips lines + debt + customer', () {
      final cart = CartController();
      cart.addItem(fakeActivatedItem(itemId: 'i1', salePrice: 1.5));
      cart.addItem(fakeActivatedItem(itemId: 'i1', salePrice: 1.5));
      cart.addItem(fakeActivatedItem(itemId: 'i2', salePrice: 1.0));
      cart.setDebt(true);
      cart.setCustomer(fakeCustomer(name: 'Ahmed'));

      final snapshot = cart.snapshot();
      cart.clearAll();
      expect(cart.isEmpty, isTrue);

      cart.restore(snapshot);

      expect(cart.itemCount, 3);
      expect(cart.lines['i1']!.quantity, 2);
      expect(cart.debt, isTrue);
      expect(cart.customer?.name, 'Ahmed');
    });

    test('snapshot is a deep copy — later edits do not affect the captured value', () {
      final cart = CartController();
      cart.addItem(fakeActivatedItem(itemId: 'i1'));
      final snapshot = cart.snapshot();

      cart.lines['i1']?.quantity = 99; // also unmodifiable; should throw
      // Either way the snapshot.lines should be unaffected.
      expect(snapshot.lines['i1']!.quantity, 1);
    });

    test('multi-cart v2 methods throw UnimplementedError', () {
      final cart = CartController();
      expect(() => cart.hold('Cart 1'), throwsUnimplementedError);
      expect(() => cart.resume('id'), throwsUnimplementedError);
      expect(() => cart.discard('id'), throwsUnimplementedError);
    });
  });
}
