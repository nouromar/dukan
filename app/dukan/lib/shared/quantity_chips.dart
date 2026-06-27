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
  });

  /// Called with the chosen quantity (in the line's packaging units).
  final ValueChanged<num> onSelected;

  /// The shop's learned usual quantity for this packaging/context, if known.
  final num? learnedQty;

  /// Optional short label appended to each chip (e.g. "bag"). When null the
  /// chips show bare numbers (the packaging is already shown elsewhere).
  final String? unitLabel;

  final List<num> defaults;

  @override
  Widget build(BuildContext context) {
    final learned = learnedQty;
    final set = <num>{...defaults};
    if (learned != null && learned > 0) set.add(learned);
    final values = set.toList()..sort();

    String labelFor(num v) {
      final n = formatQty(v);
      return (unitLabel == null || unitLabel!.isEmpty) ? n : '$n $unitLabel';
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
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
