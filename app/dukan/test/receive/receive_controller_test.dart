import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/receive/receive_controller.dart';

import '../shared/fakes.dart';

void main() {
  group('ReceiveController', () {
    test('starts empty', () {
      final c = ReceiveController();
      expect(c.isEmpty, isTrue);
      expect(c.lineCount, 0);
      expect(c.bonoTotal, 0);
      expect(c.supplier, isNull);
    });

    test('setSupplier notifies once per change', () {
      final c = ReceiveController();
      var notified = 0;
      c.addListener(() => notified++);

      final s = fakeCustomer();
      c.setSupplier(s);
      expect(c.supplier, s);
      expect(notified, 1);

      c.setSupplier(s); // same — no notify
      expect(notified, 1);
    });

    test('addOrReplaceLine sets and replaces (no incrementing)', () {
      final c = ReceiveController();
      c.addOrReplaceLine(
        shopItemUnitId: 'siu-1',
        shopItemId: 'si-1',
        itemId: 'i1',
        displayName: 'Bariis',
        packagingLabel: 'Kg',
        baseUnitLabel: 'Kg',
        quantity: 3,
        lineTotal: 12,
      );
      expect(c.lineCount, 1);
      expect(c.lines['siu-1']!.quantity, 3);
      expect(c.lines['siu-1']!.lineTotal, 12);
      expect(c.lines['siu-1']!.unitCost, 4); // computed from total/qty

      // Adding again REPLACES — does not increment.
      c.addOrReplaceLine(
        shopItemUnitId: 'siu-1',
        shopItemId: 'si-1',
        itemId: 'i1',
        displayName: 'Bariis',
        packagingLabel: 'Kg',
        baseUnitLabel: 'Kg',
        quantity: 5,
        lineTotal: 22.5,
      );
      expect(c.lines['siu-1']!.quantity, 5);
      expect(c.lines['siu-1']!.lineTotal, 22.5);
      expect(c.lines['siu-1']!.unitCost, 4.5);
    });

    test('line carries the packaging label, not the base unit', () {
      final c = ReceiveController();
      c.addOrReplaceLine(
        shopItemUnitId: 'siu-bag',
        shopItemId: 'si-1',
        itemId: 'i1',
        displayName: 'Bariis',
        packagingLabel: '25 Kg Bag',
        baseUnitLabel: 'Kg',
        quantity: 5,
        lineTotal: 120,
      );
      expect(c.lines['siu-bag']!.packagingLabel, '25 Kg Bag');
      expect(c.lines['siu-bag']!.baseUnitLabel, 'Kg');
    });

    test('lines key by shopItemUnitId; shop-only items have null itemId', () {
      final c = ReceiveController();
      c.addOrReplaceLine(
        shopItemUnitId: 'siu-shop-only',
        shopItemId: 'si-shop-only',
        itemId: null,
        displayName: 'Caano qalalan',
        packagingLabel: 'Packet',
        baseUnitLabel: 'Packet',
        quantity: 1,
        lineTotal: 2,
      );
      expect(c.lines.keys.first, 'siu-shop-only');
      expect(c.lines['siu-shop-only']!.itemId, isNull);
      expect(c.lines['siu-shop-only']!.shopItemId, 'si-shop-only');
    });

    test('removeLine drops the line and notifies', () {
      final c = ReceiveController();
      c.addOrReplaceLine(
        shopItemUnitId: 'siu-1',
        shopItemId: 'si-1',
        itemId: 'i1',
        displayName: 'Bariis',
        packagingLabel: 'Kg',
        baseUnitLabel: 'Kg',
        quantity: 1,
        lineTotal: 1,
      );
      c.addOrReplaceLine(
        shopItemUnitId: 'siu-2',
        shopItemId: 'si-2',
        itemId: 'i2',
        displayName: 'Sonkor',
        packagingLabel: 'Kg',
        baseUnitLabel: 'Kg',
        quantity: 1,
        lineTotal: 1,
      );
      var notified = 0;
      c.addListener(() => notified++);

      c.removeLine('siu-1');
      expect(c.lines.keys, ['siu-2']);
      expect(notified, 1);
      c.removeLine('nope');
      expect(notified, 1);
    });

    test('bonoTotal is the sum of line_totals', () {
      final c = ReceiveController();
      c.addOrReplaceLine(
        shopItemUnitId: 'siu-1',
        shopItemId: 'si-1',
        itemId: 'i1',
        displayName: 'Bariis',
        packagingLabel: 'Bag',
        baseUnitLabel: 'Kg',
        quantity: 5,
        lineTotal: 120,
      );
      c.addOrReplaceLine(
        shopItemUnitId: 'siu-2',
        shopItemId: 'si-2',
        itemId: 'i2',
        displayName: 'Sonkor',
        packagingLabel: 'Kg',
        baseUnitLabel: 'Kg',
        quantity: 2,
        lineTotal: 6,
      );
      expect(c.bonoTotal, 126);
    });

    test('clearLines keeps supplier, clearAll wipes everything', () {
      final c = ReceiveController();
      c.setSupplier(fakeCustomer());
      c.addOrReplaceLine(
        shopItemUnitId: 'siu-1',
        shopItemId: 'si-1',
        itemId: 'i1',
        displayName: 'Bariis',
        packagingLabel: 'Kg',
        baseUnitLabel: 'Kg',
        quantity: 1,
        lineTotal: 1,
      );

      c.clearLines();
      expect(c.isEmpty, isTrue);
      expect(c.supplier, isNotNull);

      c.clearAll();
      expect(c.supplier, isNull);
    });

    test('snapshot/restore round-trips', () {
      final c = ReceiveController();
      c.setSupplier(fakeCustomer(name: 'Hassan'));
      c.addOrReplaceLine(
        shopItemUnitId: 'siu-1',
        shopItemId: 'si-1',
        itemId: 'i1',
        displayName: 'Bariis',
        packagingLabel: 'Bag',
        baseUnitLabel: 'Kg',
        quantity: 5,
        lineTotal: 100,
      );

      final snap = c.snapshot();
      c.clearAll();
      expect(c.isEmpty, isTrue);
      expect(c.supplier, isNull);

      c.restore(snap);
      expect(c.lineCount, 1);
      expect(c.lines['siu-1']!.quantity, 5);
      expect(c.lines['siu-1']!.lineTotal, 100);
      expect(c.supplier?.name, 'Hassan');
    });
  });
}
