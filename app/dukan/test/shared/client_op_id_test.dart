import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/shared/client_op_id.dart';

void main() {
  test('generateUuidV4 is recognised as a server-assigned id', () {
    for (var i = 0; i < 50; i++) {
      expect(isServerAssignedId(generateUuidV4()), isTrue);
    }
  });

  test('client_op_id placeholders are NOT server-assigned ids', () {
    // These are the optimistic local ids for offline-posted transactions —
    // voiding one must be blocked until it syncs (else void RPC → 22P02).
    for (final prefix in const ['sale', 'receive', 'payment', 'expense']) {
      final opId = generateClientOpId(prefix);
      expect(opId, contains('$prefix-'));
      expect(isServerAssignedId(opId), isFalse);
    }
    // The exact value from the field report.
    expect(
      isServerAssignedId('expense-1783095528341-3366287978'),
      isFalse,
    );
  });

  test('malformed / near-UUID strings are rejected', () {
    expect(isServerAssignedId(''), isFalse);
    expect(isServerAssignedId('not-a-uuid'), isFalse);
    // Wrong segment lengths.
    expect(isServerAssignedId('0000-0000-0000-0000-000000000000'), isFalse);
    // Non-hex char.
    expect(
      isServerAssignedId('zzzzzzzz-0000-4000-8000-000000000000'),
      isFalse,
    );
  });
}
