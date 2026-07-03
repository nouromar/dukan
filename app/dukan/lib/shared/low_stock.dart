// Shared low-stock predicate + indicator widget.
//
// v1 rule: red when `currentStock < 1` — i.e. you're out of stock (or
// oversold into the negative). The per-item reorder threshold knob is
// not supported in v1 (the column stays on shop_item for forward
// compat but no UI sets or reads it). Reintroduce a threshold-aware
// branch here if/when reorder/replenishment lands.
//
// All numbers are in the item's base unit. Stock can be negative
// internally (ledger preserves true balance per docs/plan); the
// indicator treats any value < 1 as low regardless of sign.

import 'package:flutter/material.dart';

bool isLowStock({required num? currentStock}) {
  if (currentStock == null) return false;
  return currentStock < 1;
}

/// Three-tier stock health for colour-coding the stock count.
///   * red    — out: stock < 1
///   * yellow — low: 1 ≤ stock ≤ reorder threshold (inclusive)
///   * green  — healthy: stock > threshold
/// When no reorder threshold is set, 1 is used as the threshold, so a
/// threshold-less item is red below 1, yellow at exactly 1, green above.
enum StockLevel { out, low, healthy }

StockLevel stockLevel({required num? currentStock, num? reorderThreshold}) {
  final stock = currentStock ?? 0;
  final threshold = reorderThreshold ?? 1;
  if (stock < 1) return StockLevel.out;
  if (stock > threshold) return StockLevel.healthy;
  return StockLevel.low;
}

/// Readable stock-count colour for [level]. Fixed accessible shades so
/// green / amber / red read the same in the list and the item tiles.
Color stockLevelColor(BuildContext context, StockLevel level) {
  switch (level) {
    case StockLevel.out:
      return Theme.of(context).colorScheme.error;
    case StockLevel.low:
      return Colors.orange.shade800;
    case StockLevel.healthy:
      return Colors.green.shade700;
  }
}

/// Compact filled red circle for placing in the top-right corner of an
/// item tile / list row. ~10dp — visible at a glance, not loud.
class LowStockDot extends StatelessWidget {
  const LowStockDot({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        shape: BoxShape.circle,
      ),
    );
  }
}
