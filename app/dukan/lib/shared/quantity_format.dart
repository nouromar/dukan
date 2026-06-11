// Display formatter for numeric quantities. Drops trailing zeros so
// stored `numeric(14,3)` values print as the shopkeeper would write
// them: "1", "0.5", "1.5", "25", "0.125".
//
// Used by the cart row, receipt lines, history, and the Receive line
// list — anywhere a raw `num quantity` needs to land in the UI.

String formatQty(num value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
