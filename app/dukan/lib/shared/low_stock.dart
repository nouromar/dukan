// Shared low-stock predicate + indicator widget.
//
// Trigger: red when `currentStock < 1` OR (a per-item threshold is set
// AND `currentStock <= threshold`). The first rule is the floor — even
// without a per-item threshold, hitting zero counts as low. The second
// gives the shopkeeper a knob to flag earlier (e.g., "warn rice at
// 25 kg = one bag").
//
// All numbers are in the item's base unit. Stock can be negative
// internally (ledger preserves true balance per docs/plan); the
// indicator treats any value < 1 as low regardless of sign.

import 'package:flutter/material.dart';

bool isLowStock({required num? currentStock, required num? reorderThreshold}) {
  if (currentStock == null) return false;
  if (currentStock < 1) return true;
  if (reorderThreshold != null && currentStock <= reorderThreshold) return true;
  return false;
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
