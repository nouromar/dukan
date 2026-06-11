// Compound stock formatter — renders `shop_item.current_stock` (always
// in base units) as a shopkeeper-friendly string that combines the
// default sale packaging count with any remainder in the base unit.
//
// Examples (base=kg, default packaging = 25 Kg Bag, conversion=25):
//   47   → "1 Bag + 22 Kg"
//   50   → "2 Bag"           (no remainder)
//   22   → "22 Kg"           (less than one bag)
//   0    → "0 Kg"            (caller decides color via isLowStock)
//   −3   → "−3 Kg"           (negative: skip compound, raw base)
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
  if (remainder == 0) {
    return '${_pretty(whole)} $pkg';
  }
  return '${_pretty(whole)} $pkg + ${_pretty(remainder)} $baseLabel';
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
