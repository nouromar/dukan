import 'package:flutter/material.dart';

import 'package:dukan/shared/quantity_format.dart';

/// A row of quick-tap quantity chips so the shopkeeper sets the quantity with a
/// tap instead of the numpad (UX rule: tap = the normal path). The shop's
/// learned usual quantity (if any) is folded in and highlighted with a history
/// mark; the rest are sensible static defaults. A chip is a *default the
/// shopkeeper taps* — never auto-applied.
class QuantityChips extends StatelessWidget {
  const QuantityChips({
    super.key,
    required this.onSelected,
    this.learnedQty,
    this.unitLabel,
    this.defaults = const [1, 2, 5],
    this.maxChips,
    this.alignment = WrapAlignment.center,
  });

  /// Called with the chosen quantity (in the line's packaging units).
  final ValueChanged<num> onSelected;

  /// The shop's learned usual quantity for this packaging/context, if known.
  final num? learnedQty;

  /// Optional short label appended to each chip (e.g. "bag"). When null the
  /// chips show bare numbers (the packaging is already shown elsewhere).
  final String? unitLabel;

  final List<num> defaults;

  /// Cap on the number of chips shown. null = no cap. When capping, the learned
  /// quantity is always kept (it's the most useful), then defaults fill the
  /// rest. Used by the Receive form, where the chips sit beside the qty box.
  final int? maxChips;

  /// How the chip row aligns within its width. Receive sits them beside the
  /// box (start); Sale centers them below the stepper.
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final learned =
        (learnedQty != null && learnedQty! > 0) ? learnedQty : null;
    // Keep the learned chip first so it survives the cap, then fill with
    // defaults up to maxChips, then sort for display.
    final values = <num>[];
    if (learned != null) values.add(learned);
    for (final d in defaults) {
      if (maxChips != null && values.length >= maxChips!) break;
      if (!values.contains(d)) values.add(d);
    }
    values.sort();

    String labelFor(num v) {
      final n = formatQty(v);
      return (unitLabel == null || unitLabel!.isEmpty) ? n : '$n $unitLabel';
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: alignment,
      children: [
        for (final v in values)
          ActionChip(
            // Compact so the chip row fits dense forms (e.g. the inline
            // Receive line editor) without overflowing.
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            avatar: (learned != null && v == learned)
                ? const Icon(Icons.history, size: 16)
                : null,
            label: Text(labelFor(v)),
            onPressed: () => onSelected(v),
          ),
      ],
    );
  }
}
