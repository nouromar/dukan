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
      expect(
        () => normalizePhoneNumber('123'),
        throwsA(isA<AuthInputException>()),
      );
    });
  });

  group('normalizeEmail', () {
    test('lowercases + trims valid addresses', () {
      expect(normalizeEmail('  Owner@Example.COM '), 'owner@example.com');
    });

    test('accepts internationalized-looking simple form', () {
      expect(normalizeEmail('a.b+tag@sub.example.co'), 'a.b+tag@sub.example.co');
    });

    test('rejects missing @', () {
      expect(
        () => normalizeEmail('not-an-email'),
        throwsA(isA<AuthInputException>()),
      );
    });

    test('rejects missing domain', () {
      expect(
        () => normalizeEmail('user@'),
        throwsA(isA<AuthInputException>()),
      );
    });

    test('rejects whitespace inside the address', () {
      expect(
        () => normalizeEmail('user @example.com'),
        throwsA(isA<AuthInputException>()),
      );
    });

    test('rejects missing TLD dot', () {
      expect(
        () => normalizeEmail('user@example'),
        throwsA(isA<AuthInputException>()),
      );
    });
  });
}
