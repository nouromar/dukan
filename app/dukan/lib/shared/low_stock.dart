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
