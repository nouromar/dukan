// Numeric-input helpers that accept both ASCII 0-9 and the most common
// non-Latin digit families (Eastern Arabic ٠-٩, Persian ۰-۹). Many
// Android keyboards bound to Arabic or Persian IMEs send those code
// points even when the device locale is English; without translation,
// `FilteringTextInputFormatter.digitsOnly` strips every keystroke and
// the field looks frozen to the user.

import 'package:flutter/services.dart';

const _easternArabicZero = 0x0660; // ٠
const _persianZero = 0x06F0; // ۰

String _normalizeDigitsAndOptionalDecimal(String input, {bool allowDot = false}) {
  final buf = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x30 && rune <= 0x39) {
      buf.writeCharCode(rune); // ASCII 0-9
    } else if (rune >= _easternArabicZero && rune <= _easternArabicZero + 9) {
      buf.writeCharCode(0x30 + (rune - _easternArabicZero));
    } else if (rune >= _persianZero && rune <= _persianZero + 9) {
      buf.writeCharCode(0x30 + (rune - _persianZero));
    } else if (allowDot && rune == 0x2E) {
      buf.writeCharCode(rune);
    }
    // Everything else is dropped — same end result as digitsOnly.
  }
  return buf.toString();
}

/// Drop-in for `FilteringTextInputFormatter.digitsOnly` that ALSO
/// converts Eastern Arabic / Persian digit code points to ASCII. Use
/// this for OTP, phone, quantity (whole), and any int-only field.
class DigitsOnlyInputFormatter extends TextInputFormatter {
  const DigitsOnlyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = _normalizeDigitsAndOptionalDecimal(newValue.text);
    if (normalized == newValue.text) return newValue;
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }
}

/// Same as [DigitsOnlyInputFormatter] but also allows a single `.` for
/// decimal numeric input (prices, fractional quantities). Doesn't
/// enforce "one dot only" — the existing parse step (`num.tryParse`)
/// will reject malformed input downstream.
class DecimalDigitsInputFormatter extends TextInputFormatter {
  const DecimalDigitsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized =
        _normalizeDigitsAndOptionalDecimal(newValue.text, allowDot: true);
    if (normalized == newValue.text) return newValue;
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }
}

/// Phone-number formatter: ASCII digits + `+` only, with the same
/// Arabic/Persian digit translation as [DigitsOnlyInputFormatter].
/// `+` is allowed anywhere; downstream E.164 normalization decides
/// where it ends up.
class PhoneDigitsInputFormatter extends TextInputFormatter {
  const PhoneDigitsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final buf = StringBuffer();
    for (final rune in newValue.text.runes) {
      if (rune >= 0x30 && rune <= 0x39) {
        buf.writeCharCode(rune);
      } else if (rune >= _easternArabicZero && rune <= _easternArabicZero + 9) {
        buf.writeCharCode(0x30 + (rune - _easternArabicZero));
      } else if (rune >= _persianZero && rune <= _persianZero + 9) {
        buf.writeCharCode(0x30 + (rune - _persianZero));
      } else if (rune == 0x2B) {
        buf.writeCharCode(rune); // '+'
      }
    }
    final normalized = buf.toString();
    if (normalized == newValue.text) return newValue;
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }
}
