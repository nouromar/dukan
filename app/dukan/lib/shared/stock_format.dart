// Compound stock formatter — renders `shop_item.current_stock` (always
// in base units) as a shopkeeper-friendly string that combines the
// default sale packaging count with any remainder in the base unit.
//
// Examples (base=kg, default packaging = "25 Kg Bag", conversion=25):
//   47   → "1 Bag(25kg) + 22kg"
//   50   → "2 Bag(25kg)"     (no remainder)
//   22   → "22kg"            (less than one bag)
//   0    → "0kg"             (caller decides color via isLowStock)
//   −3   → "−3kg"            (negative: skip compound, raw base)
//
// The packaging label frequently embeds its own conversion ("50 Sack",
// "25 Kg Bag"). On the count line that collides with the count itself —
// "9 50 Sack" reads as one number — so we strip the leading conversion
// (and base-label) prefix down to the bare noun, then re-attach the size
// in parens: "9 Sack(50kg) + 48kg".
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
  bool compact = false,
}) {
  // Attach an abbreviated unit to the number ("40kg", "50g", "2l") but keep a
  // space before a spelled-out unit ("143 piece", "2 bag", "1 litre").
  final sep = _unitAttaches(baseLabel) ? '' : ' ';

  // Negative balance bypasses compound math — "−1 Bag + 22 Kg" is
  // mathematically right but bewildering to shopkeepers. Show the
  // raw base value so the sign is unambiguous.
  if (stock < 0) {
    return '${_pretty(stock)}$sep$baseLabel';
  }

  final pkg = packagingLabel;
  final conv = conversion;
  // No packaging info, or packaging == base (conversion 1) → base only.
  if (pkg == null || conv == null || conv <= 1) {
    return '${_pretty(stock)}$sep$baseLabel';
  }

  final whole = (stock / conv).floor();
  final remainder = stock - whole * conv;

  if (whole == 0) {
    // Less than one packaging — show the partial in base.
    return '${_pretty(stock)}$sep$baseLabel';
  }
  // Use the bare packaging noun so the count doesn't collide with a
  // number-prefixed label ("9 50 Sack" → "9 Sack"), then annotate it with
  // its size so the count is unambiguous — "9 Sack(50kg)" makes clear how
  // big a sack is (a 50-kg sack vs a 25-kg sack). Compact (no spaces around
  // the size) to save room on the tile.
  final noun = _countNoun(pkg, conv, baseLabel);
  // Compact (grid tiles): just the whole packaging count — no size
  // annotation, no base remainder — so "45 Carton" instead of the full
  // "45 Carton(12 bottle) + 9 bottle". Keeps a small tile readable.
  if (compact) {
    return '${_pretty(whole)} $noun';
  }
  final sized = '$noun(${_pretty(conv)}$sep$baseLabel)';
  if (remainder == 0) {
    return '${_pretty(whole)} $sized';
  }
  return '${_pretty(whole)} $sized + ${_pretty(remainder)}$sep$baseLabel';
}

/// The bare packaging noun for a label ("12 Bottle Carton" → "Carton"),
/// stripping any "{conversion} " / "{baseLabel} " size prefix. Used to
/// keep the grid-tile unit line short. Falls back to the label when it
/// has no strippable prefix.
String packagingCountNoun({
  required String packagingLabel,
  required num conversion,
  required String baseLabel,
}) =>
    _countNoun(packagingLabel, conversion, baseLabel);

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

/// Measurement units that read best glued to the number ("40kg", "50g",
/// "2l"). Anything not here — spelled-out packagings like bag / piece /
/// litre / sack — keeps a space ("143 piece"). Matched case-insensitively.
const Set<String> _abbreviatedUnits = {
  'kg', 'g', 'mg', 't', // mass
  'l', 'ml', 'cl', 'dl', 'kl', // volume
  'm', 'cm', 'mm', 'km', // length
  'oz', 'lb', // imperial mass
};

bool _unitAttaches(String label) =>
    _abbreviatedUnits.contains(label.trim().toLowerCase());

/// Render a numeric stock value with at most ONE decimal place, dropping a
/// trailing zero so whole values read "25" (not "25.0") and fractional ones
/// round to a single decimal: 12.53 → "12.5", 0.55 → "0.6". Shopkeepers see
/// tidy numbers on the Sale, Receive, and Product pages instead of long
/// binary-fraction tails. Negatives keep their sign.
String _pretty(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(1)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
