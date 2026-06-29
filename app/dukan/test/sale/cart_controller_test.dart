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
      cart.addItem(
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-1',
          defaultUnitSalePrice: 1.5,
        ),
      );
      expect(cart.itemCount, 1);
      expect(cart.total, 1.5);
      expect(cart.lines, hasLength(1));
      expect(cart.lines['siu-1']!.quantity, 1);
    });

    test('addItem carries the item base unit code (for "+ Add packaging")', () {
      final cart = CartController();
      cart.addItem(
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-1',
        ),
      );
      // baseUnitCode lets the cart-line editor offer "+ Add packaging".
      expect(cart.lines['siu-1']!.baseUnitCode, 'kg');
    });

    test('addItem on the same packaging increments quantity', () {
      final cart = CartController();
      final item = fakeActivatedItem(
        shopItemId: 'si-1',
        itemId: 'i1',
        defaultShopItemUnitId: 'siu-1',
        defaultUnitSalePrice: 1.5,
      );
      cart.addItem(item);
      cart.addItem(item);
      cart.addItem(item);
      expect(cart.lines['siu-1']!.quantity, 3);
      expect(cart.total, 4.5);
    });

    // TODO(v2): rewrite for new activation semantics — T#145
    // Unactivated catalog candidates (no shopItemId / defaultShopItemUnitId)
    // can no longer be added to the cart directly; the Sale screen activates
    // first via ensureShopItem.

    test('removeLine drops the line and notifies', () {
      final cart = CartController();
      cart.addItem(
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-1',
        ),
      );
      cart.addItem(
        fakeActivatedItem(
          shopItemId: 'si-2',
          itemId: 'i2',
          defaultShopItemUnitId: 'siu-2',
        ),
      );
      var notified = 0;
      cart.addListener(() => notified++);

      cart.removeLine('siu-1');
      expect(cart.lines.keys, ['siu-2']);
      expect(notified, 1);

      // No-op remove doesn't notify
      cart.removeLine('nonexistent');
      expect(notified, 1);
    });

    test('clearAll wipes lines + debt + customer', () {
      final cart = CartController();
      cart.addItem(fakeActivatedItem(defaultShopItemUnitId: 'siu-1'));
      cart.setDebt(true);
      cart.setCustomer(fakeCustomer());

      cart.clearAll();

      expect(cart.isEmpty, isTrue);
      expect(cart.debt, isFalse);
      expect(cart.customer, isNull);
    });

    test('snapshot/restore round-trips lines + debt + customer', () {
      final cart = CartController();
      final item1 = fakeActivatedItem(
        shopItemId: 'si-1',
        itemId: 'i1',
        defaultShopItemUnitId: 'siu-1',
        defaultUnitSalePrice: 1.5,
      );
      final item2 = fakeActivatedItem(
        shopItemId: 'si-2',
        itemId: 'i2',
        defaultShopItemUnitId: 'siu-2',
        defaultUnitSalePrice: 1.0,
      );
      cart.addItem(item1);
      cart.addItem(item1);
      cart.addItem(item2);
      cart.setDebt(true);
      cart.setCustomer(fakeCustomer(name: 'Ahmed'));

      final snapshot = cart.snapshot();
      cart.clearAll();
      expect(cart.isEmpty, isTrue);

      cart.restore(snapshot);

      // v1.x: itemCount is line count (rows), not qty sum — fractional
      // weights ("0.5 kg") would make a qty sum meaningless.
      expect(cart.itemCount, 2);
      expect(cart.lines['siu-1']!.quantity, 2);
      expect(cart.debt, isTrue);
      expect(cart.customer?.name, 'Ahmed');
    });

    test('snapshot is a deep copy — later edits do not affect the captured value', () {
      final cart = CartController();
      cart.addItem(
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-1',
        ),
      );
      final snapshot = cart.snapshot();

      cart.lines['siu-1']?.quantity = 99; // also unmodifiable; should throw
      // Either way the snapshot.lines should be unaffected.
      expect(snapshot.lines['siu-1']!.quantity, 1);
    });

    test('multi-cart v2 methods throw UnimplementedError', () {
      final cart = CartController();
      expect(() => cart.hold('Cart 1'), throwsUnimplementedError);
      expect(() => cart.resume('id'), throwsUnimplementedError);
      expect(() => cart.discard('id'), throwsUnimplementedError);
    });

    // priceWasEntered drives whether SAVE persists the line's unit price
    // back to shop_item_unit.sale_price via set_shop_item_unit_sale_price.
    // Fast-path addItem must NOT set it; both editor entry points MUST
    // set it; the flag also has to survive snapshot/restore so the SAVE
    // retry path doesn't lose the signal after a transient failure.

    test('addItem leaves priceWasEntered false (fast-path)', () {
      final cart = CartController();
      cart.addItem(
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-1',
          defaultUnitSalePrice: 1.5,
        ),
      );
      expect(cart.lines['siu-1']!.priceWasEntered, isFalse);
    });

    test('addOrReplaceFromEditor marks priceWasEntered true', () {
      final cart = CartController();
      cart.addOrReplaceFromEditor(
        shopItemUnitId: 'siu-1',
        shopItemId: 'si-1',
        itemId: 'i1',
        displayName: 'Bariis',
        packagingLabel: 'Kg',
        baseUnitLabel: 'Kg',
        quantity: 2,
        unitPrice: 3,
      );
      final line = cart.lines['siu-1']!;
      expect(line.priceWasEntered, isTrue);
      expect(line.quantity, 2);
      expect(line.unitPrice, 3);
    });

    test('updateLineFromEditor marks priceWasEntered true on an existing line',
        () {
      final cart = CartController();
      cart.addItem(
        fakeActivatedItem(
          shopItemId: 'si-1',
          itemId: 'i1',
          defaultShopItemUnitId: 'siu-1',
          defaultUnitSalePrice: 1.5,
        ),
      );
      expect(cart.lines['siu-1']!.priceWasEntered, isFalse);

      cart.updateLineFromEditor('siu-1', quantity: 5, unitPrice: 2);

      expect(cart.lines['siu-1']!.priceWasEntered, isTrue);
      expect(cart.lines['siu-1']!.quantity, 5);
      expect(cart.lines['siu-1']!.unitPrice, 2);
    });

    test('snapshot/restore preserves priceWasEntered', () {
      final cart = CartController();
      cart.addOrReplaceFromEditor(
        shopItemUnitId: 'siu-1',
        shopItemId: 'si-1',
        itemId: 'i1',
        displayName: 'Bariis',
        packagingLabel: 'Kg',
        baseUnitLabel: 'Kg',
        quantity: 1,
        unitPrice: 0.25,
      );
      final snapshot = cart.snapshot();
      cart.clearAll();
      cart.restore(snapshot);
      expect(cart.lines['siu-1']!.priceWasEntered, isTrue);
    });
  });
}
