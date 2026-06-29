import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/payment/payment_controller.dart';

void main() {
  group('PaymentController', () {
    test('defaults to customer type, no party, zero amount', () {
      final c = PaymentController();
      expect(c.type, PaymentType.customer);
      expect(c.party, isNull);
      expect(c.amount, 0);
      expect(c.outstandingBalance, 0);
    });

    test('setType clears party + amount (defensive on type change)', () {
      final c = PaymentController();
      c.setParty(
        const PartySearchResult(
          id: 'p1',
          name: 'Ahmed',
          phone: null,
          typeCode: 'customer',
          receivable: 40,
          payable: 0,
        ),
      );
      c.setAmount(10);
      expect(c.party, isNotNull);

      c.initType(PaymentType.supplier);
      // Opening a direction (initType) starts a clean entry — a customer-typed
      // party doesn't make sense under the supplier direction.
      expect(c.party, isNull);
      expect(c.amount, 0);
    });

    test('outstandingBalance follows the active type', () {
      final c = PaymentController();
      const both = PartySearchResult(
        id: 'p1',
        name: 'Asha',
        phone: null,
        typeCode: 'both',
        receivable: 25,
        payable: 100,
      );
      c.setParty(both);
      expect(c.outstandingBalance, 25); // customer mode → receivable

      // Setting type clears the party. Re-pick under the new mode to
      // exercise the supplier-balance path.
      c.initType(PaymentType.supplier);
      c.setParty(both);
      expect(c.outstandingBalance, 100); // supplier mode → payable
    });

    test('setAmount clamps negatives to zero', () {
      final c = PaymentController();
      c.setAmount(-50);
      expect(c.amount, 0);
      c.setAmount(25);
      expect(c.amount, 25);
    });

    test('clearAll resets party + amount, keeps type', () {
      final c = PaymentController();
      c.initType(PaymentType.supplier);
      c.setParty(
        const PartySearchResult(
          id: 'p1',
          name: 'Hassan',
          phone: null,
          typeCode: 'supplier',
          receivable: 0,
          payable: 120,
        ),
      );
      c.setAmount(40);
      c.clearAll();
      expect(c.party, isNull);
      expect(c.amount, 0);
      expect(c.type, PaymentType.supplier); // sticky across clearAll
    });

    test('type → partyTypeCode and direction extension', () {
      expect(PaymentType.customer.partyTypeCode, 'customer');
      expect(PaymentType.supplier.partyTypeCode, 'supplier');
      expect(PaymentType.customer.direction, 'I');
      expect(PaymentType.supplier.direction, 'O');
    });
  });
}
