// Money formatting that respects the shop's configured currency. Reads
// the symbol from ShopSummary so SLSH shops show "SLSH 5000" and USD
// shops show "$ 5" without any hardcoded "$" leaking into the UI.
//
// The shop's currency is set by the template at apply_template time and
// can be changed via the Settings screen; symbols come from the
// currency reference table via ShopApi.currencySymbols() (cached on
// first read, baked into every ShopSummary instance).

import 'package:dukan/api/types.dart';

/// Format a monetary value with the shop's currency symbol. Drops the
/// decimal portion when the value is a whole number. Single-character
/// glyphs ($, £, €) print adjacent — "$1.50". Multi-character codes
/// (SLSH, KES) print with a space — "SLSH 5000".
String formatMoney(num value, ShopSummary shop) {
  final v = value.toDouble();
  final formatted = v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(2);
  final symbol = shop.currencySymbol;
  final sep = symbol.length == 1 ? '' : ' ';
  return '$symbol$sep$formatted';
}
