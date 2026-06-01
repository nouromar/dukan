String money(num value) => value == value.roundToDouble()
    ? '\$${value.toStringAsFixed(0)}'
    : '\$${value.toStringAsFixed(2)}';

double parseAmount(String text) =>
    double.tryParse(text.replaceAll(',', '.')) ?? 0;
