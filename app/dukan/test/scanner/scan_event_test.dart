import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/scanner/scan_event.dart';

void main() {
  group('ScanEvent', () {
    test('equality is structural', () {
      const a = ScanEvent(
        code: '1234567890123',
        source: ScanSource.camera,
        symbology: 'ean13',
      );
      const b = ScanEvent(
        code: '1234567890123',
        source: ScanSource.camera,
        symbology: 'ean13',
      );
      const c = ScanEvent(
        code: '1234567890123',
        source: ScanSource.hid,
        symbology: 'ean13',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString includes code + source + symbology', () {
      const e = ScanEvent(
        code: '5901234123457',
        source: ScanSource.camera,
        symbology: 'ean13',
      );
      expect(e.toString(), contains('5901234123457'));
      expect(e.toString(), contains('camera'));
      expect(e.toString(), contains('ean13'));
    });

    test('symbology defaults to null', () {
      const e = ScanEvent(code: '123', source: ScanSource.hid);
      expect(e.symbology, isNull);
    });
  });
}
