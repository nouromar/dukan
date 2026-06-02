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
      final item = fakeActivatedItem(itemId: 'i1');
      c.addOrReplaceLine(item, quantity: 3, lineTotal: 12);
      expect(c.lineCount, 1);
      expect(c.lines['i1']!.quantity, 3);
      expect(c.lines['i1']!.lineTotal, 12);
      expect(c.lines['i1']!.unitCost, 4); // computed from total/qty

      // Adding again REPLACES — does not increment.
      c.addOrReplaceLine(item, quantity: 5, lineTotal: 22.5);
      expect(c.lines['i1']!.quantity, 5);
      expect(c.lines['i1']!.lineTotal, 22.5);
      expect(c.lines['i1']!.unitCost, 4.5);
    });

    test('line carries the receive unit, not the base unit', () {
      final c = ReceiveController();
      c.addOrReplaceLine(
        fakeActivatedItem(
          itemId: 'i1',
          baseUnitCode: 'kg',
          baseUnitLabel: 'Kg',
          receiveUnitCode: 'bag',
          receiveUnitLabel: 'Bag',
        ),
        quantity: 5,
        lineTotal: 120,
      );
      expect(c.lines['i1']!.receiveUnitCode, 'bag');
      expect(c.lines['i1']!.receiveUnitLabel, 'Bag');
    });

    test('catalog candidates key by catalog_item_id when itemId is null', () {
      final c = ReceiveController();
      c.addOrReplaceLine(
        fakeCatalogCandidate(catalogItemId: 'c1'),
        quantity: 1,
        lineTotal: 2,
      );
      expect(c.lines.keys.first, 'c1');
      expect(c.lines['c1']!.itemId, isNull);
      expect(c.lines['c1']!.catalogItemId, 'c1');
    });

    test('removeLine drops the line and notifies', () {
      final c = ReceiveController();
      c.addOrReplaceLine(
        fakeActivatedItem(itemId: 'i1'),
        quantity: 1,
        lineTotal: 1,
      );
      c.addOrReplaceLine(
        fakeActivatedItem(itemId: 'i2'),
        quantity: 1,
        lineTotal: 1,
      );
      var notified = 0;
      c.addListener(() => notified++);

      c.removeLine('i1');
      expect(c.lines.keys, ['i2']);
      expect(notified, 1);
      c.removeLine('nope');
      expect(notified, 1);
    });

    test('bonoTotal is the sum of line_totals', () {
      final c = ReceiveController();
      c.addOrReplaceLine(
        fakeActivatedItem(itemId: 'i1'),
        quantity: 5,
        lineTotal: 120,
      );
      c.addOrReplaceLine(
        fakeActivatedItem(itemId: 'i2'),
        quantity: 2,
        lineTotal: 6,
      );
      expect(c.bonoTotal, 126);
    });

    test('clearLines keeps supplier, clearAll wipes everything', () {
      final c = ReceiveController();
      c.setSupplier(fakeCustomer());
      c.addOrReplaceLine(
        fakeActivatedItem(itemId: 'i1'),
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
        fakeActivatedItem(itemId: 'i1'),
        quantity: 5,
        lineTotal: 100,
      );

      final snap = c.snapshot();
      c.clearAll();
      expect(c.isEmpty, isTrue);
      expect(c.supplier, isNull);

      c.restore(snap);
      expect(c.lineCount, 1);
      expect(c.lines['i1']!.quantity, 5);
      expect(c.lines['i1']!.lineTotal, 100);
      expect(c.supplier?.name, 'Hassan');
    });
  });
}
