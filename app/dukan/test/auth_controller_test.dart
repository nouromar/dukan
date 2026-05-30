import 'package:dukan/auth/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizePhoneNumber', () {
    test('keeps valid E.164 numbers', () {
      expect(normalizePhoneNumber('+252612345678'), '+252612345678');
    });

    test('defaults local Somali numbers to +252', () {
      expect(normalizePhoneNumber('061 234 5678'), '+252612345678');
      expect(normalizePhoneNumber('61-234-5678'), '+252612345678');
    });

    test('accepts 00 international prefix', () {
      expect(normalizePhoneNumber('00252612345678'), '+252612345678');
    });

    test('rejects invalid phone numbers', () {
      expect(() => normalizePhoneNumber('123'), throwsFormatException);
    });
  });
}
