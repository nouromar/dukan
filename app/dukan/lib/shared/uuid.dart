// Minimal RFC 4122 v4 UUID generator. Uses Dart's secure random so
// client-minted ids are collision-safe for our scale (well under the
// birthday-paradox threshold). Used for bono image upload paths where
// the storage key must embed the document id before insert.

import 'dart:math';

const _hex = '0123456789abcdef';
final _rng = Random.secure();

String uuidV4() {
  final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
  // RFC 4122 §4.4: set version + variant bits.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final buf = StringBuffer();
  for (var i = 0; i < 16; i++) {
    if (i == 4 || i == 6 || i == 8 || i == 10) buf.write('-');
    buf.write(_hex[(bytes[i] >> 4) & 0xf]);
    buf.write(_hex[bytes[i] & 0xf]);
  }
  return buf.toString();
}
