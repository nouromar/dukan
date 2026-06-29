// Compound stock formatter — renders `shop_item.current_stock` (always
// in base units) as a shopkeeper-friendly string that combines the
// default sale packaging count with any remainder in the base unit.
//
// Examples (base=kg, default packaging = "25 Kg Bag", conversion=25):
//   47   → "1 Bag + 22 kg"
//   50   → "2 Bag"           (no remainder)
//   22   → "22 kg"           (less than one bag)
//   0    → "0 kg"            (caller decides color via isLowStock)
//   −3   → "−3 kg"           (negative: skip compound, raw base)
//
// The packaging label frequently embeds its own conversion ("50 Sack",
// "25 Kg Bag"). On the count line that collides with the count itself —
// "9 50 Sack" reads as one number — so we strip the leading conversion
// (and base-label) prefix down to the bare noun: "9 Sack + 48 kg".
//
// When the default packaging IS the base (conversion = 1) or no
// packaging info is available, the helper degrades to plain
// "{stock} {base-label}".
//
// Threshold + color are computed by the caller via isLowStock — this
// helper is pure formatting.

String formatCompoundStock({
  required num stock,
  required String baseLabel,
  String? packagingLabel,
  num? conversion,
}) {
  // Negative balance bypasses compound math — "−1 Bag + 22 Kg" is
  // mathematically right but bewildering to shopkeepers. Show the
  // raw base value so the sign is unambiguous.
  if (stock < 0) {
    return '${_pretty(stock)} $baseLabel';
  }

  final pkg = packagingLabel;
  final conv = conversion;
  // No packaging info, or packaging == base (conversion 1) → base only.
  if (pkg == null || conv == null || conv <= 1) {
    return '${_pretty(stock)} $baseLabel';
  }

  final whole = (stock / conv).floor();
  final remainder = stock - whole * conv;

  if (whole == 0) {
    // Less than one packaging — show the partial in base.
    return '${_pretty(stock)} $baseLabel';
  }
  // Use the bare packaging noun so the count doesn't collide with a
  // number-prefixed label ("9 50 Sack" → "9 Sack").
  final noun = _countNoun(pkg, conv, baseLabel);
  if (remainder == 0) {
    return '${_pretty(whole)} $noun';
  }
  return '${_pretty(whole)} $noun + ${_pretty(remainder)} $baseLabel';
}

/// Strip a leading "{conversion} " and optional "{baseLabel} " prefix from a
/// packaging label so the count line reads "9 Sack" — not "9 50 Sack" or
/// "9 25 Kg Bag". Labels without such a prefix (e.g. "Bag") pass through, and
/// a label that is nothing but the prefix falls back to the original.
String _countNoun(String packagingLabel, num conversion, String baseLabel) {
  var s = packagingLabel;
  final pretty = _pretty(conversion);
  if (s.startsWith('$pretty ')) s = s.substring(pretty.length + 1);
  // Case-insensitive so "25 Kg Bag" (base "kg") strips down to "Bag".
  if (s.toLowerCase().startsWith('${baseLabel.toLowerCase()} ')) {
    s = s.substring(baseLabel.length + 1);
  }
  return s.isEmpty ? packagingLabel : s;
}

/// Drop trailing zeros from a numeric stock value so 25.000 reads "25"
/// and 0.500 reads "0.5". Negatives keep their sign.
String _pretty(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
