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
      expect(c.credit, 0);
      expect(c.supplier, isNull);
      expect(c.paidAmount, 0);
    });

    test('setSupplier notifies once per change', () {
      final c = ReceiveController();
      var notified = 0;
      c.addListener(() => notified++);

      final s = fakeCustomer(); // type doesn't matter; PartySearchResult.
      c.setSupplier(s);
      expect(c.supplier, s);
      expect(notified, 1);

      // Same supplier — no notify.
      c.setSupplier(s);
      expect(notified, 1);
    });

    test('addOrReplaceLine sets and replaces (no incrementing)', () {
      final c = ReceiveController();
      final item = fakeActivatedItem(itemId: 'i1', salePrice: 0);
      c.addOrReplaceLine(item, quantity: 3, unitCost: 4);
      expect(c.lineCount, 1);
      expect(c.lines['i1']!.quantity, 3);
      expect(c.lines['i1']!.unitCost, 4);

      // Adding again replaces — does NOT increment, unlike Sale.
      c.addOrReplaceLine(item, quantity: 5, unitCost: 4.5);
      expect(c.lines['i1']!.quantity, 5);
      expect(c.lines['i1']!.unitCost, 4.5);
    });

    test('catalog candidates key by catalog_item_id when itemId is null', () {
      final c = ReceiveController();
      c.addOrReplaceLine(
        fakeCatalogCandidate(catalogItemId: 'c1'),
        quantity: 1,
        unitCost: 2,
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
        unitCost: 1,
      );
      c.addOrReplaceLine(
        fakeActivatedItem(itemId: 'i2'),
        quantity: 1,
        unitCost: 1,
      );
      var notified = 0;
      c.addListener(() => notified++);

      c.removeLine('i1');
      expect(c.lines.keys, ['i2']);
      expect(notified, 1);
      // No-op
      c.removeLine('nope');
      expect(notified, 1);
    });

    test('bonoTotal and credit reflect lines + paid', () {
      final c = ReceiveController();
      c.addOrReplaceLine(
        fakeActivatedItem(itemId: 'i1'),
        quantity: 10,
        unitCost: 5,
      );
      c.addOrReplaceLine(
        fakeActivatedItem(itemId: 'i2'),
        quantity: 2,
        unitCost: 3,
      );
      expect(c.bonoTotal, 56);
      expect(c.credit, 56);

      c.setPaidAmount(20);
      expect(c.credit, 36);

      // Negative paid is clamped.
      c.setPaidAmount(-5);
      expect(c.paidAmount, 0);
      expect(c.credit, 56);
    });

    test('clearLines keeps supplier, clearAll wipes everything', () {
      final c = ReceiveController();
      c.setSupplier(fakeCustomer());
      c.addOrReplaceLine(
        fakeActivatedItem(itemId: 'i1'),
        quantity: 1,
        unitCost: 1,
      );
      c.setPaidAmount(0.5);

      c.clearLines();
      expect(c.isEmpty, isTrue);
      expect(c.paidAmount, 0);
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
        unitCost: 4,
      );
      c.setPaidAmount(10);

      final snap = c.snapshot();
      c.clearAll();
      expect(c.isEmpty, isTrue);
      expect(c.supplier, isNull);

      c.restore(snap);
      expect(c.lineCount, 1);
      expect(c.lines['i1']!.quantity, 5);
      expect(c.supplier?.name, 'Hassan');
      expect(c.paidAmount, 10);
    });
  });
}
