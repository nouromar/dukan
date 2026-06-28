// Money formatting that respects the shop's configured currency. Reads
// the symbol from ShopSummary so SLSH shops show "SLSH 5000" and USD
// shops show "$ 5" without any hardcoded "$" leaking into the UI.
//
// The shop's currency is set by the template at apply_template time and
// can be changed via the Settings screen; symbols come from the
// currency reference table via ShopApi.currencySymbols() (cached on
// first read, baked into every ShopSummary instance).

import 'package:dukan/api/types.dart';

/// Format a monetary value with the shop's currency symbol and decimal
/// places. Renders to the currency's decimals — 2 for USD ("$1.50"), 0 for
/// the shillings ("SLSH 5000", "Sh.So 5000") — so 0-decimal currencies don't
/// show a misleading ".00". Single-character glyphs ($, £, €) print adjacent;
/// multi-character codes (SLSH, KES) print with a space.
String formatMoney(num value, ShopSummary shop) {
  final formatted = value.toDouble().toStringAsFixed(shop.currencyDecimals);
  final symbol = shop.currencySymbol;
  final sep = symbol.length == 1 ? '' : ' ';
  return '$symbol$sep$formatted';
}
