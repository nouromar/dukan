// Shared filter + search building blocks for list pages.
//
// Three pieces, all designed for vertical compactness on a mid-range
// Android (≥ 56dp tap targets, ≤ 48dp idle height):
//
//   * ListSearchBar — 56dp pinned search input with a leading icon and
//     an optional trailing filter funnel. Funnel shows a tiny accent
//     dot when filters are active so the user knows something is on.
//   * ActiveFiltersBar — 36dp dismissible chip strip rendered ONLY
//     when filters are active (so the unfiltered default state stays
//     uncluttered).
//   * scopeSubtitle / dateRangeLabel — utilities for app-bar subtitle
//     and chip labels.
//
// The list pages own their filter state; this file holds presentation
// only, so it stays cheap to drop into any new screen.

import 'package:flutter/material.dart';

import 'package:dukan/shared/l10n.dart';

/// Pinned search row with optional filter funnel. Always 56dp tall.
class ListSearchBar extends StatelessWidget {
  const ListSearchBar({
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onFilterTap,
    this.filterCount = 0,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  /// When non-null, a funnel icon appears at the trailing edge.
  final VoidCallback? onFilterTap;

  /// Number of active filters. > 0 draws a dot on the funnel.
  final int filterCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: hintText,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          if (onFilterTap != null) ...[
            const SizedBox(width: 4),
            _FilterFunnelButton(
              onPressed: onFilterTap!,
              activeCount: filterCount,
              color: theme.colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }
}

/// Filter funnel for app-bar actions (use when there's no search bar).
class FilterFunnelAction extends StatelessWidget {
  const FilterFunnelAction({
    required this.onPressed,
    this.activeCount = 0,
    super.key,
  });

  final VoidCallback onPressed;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _FilterFunnelButton(
      onPressed: onPressed,
      activeCount: activeCount,
      color: theme.colorScheme.primary,
    );
  }
}

class _FilterFunnelButton extends StatelessWidget {
  const _FilterFunnelButton({
    required this.onPressed,
    required this.activeCount,
    required this.color,
  });

  final VoidCallback onPressed;
  final int activeCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: l.filterTooltip,
          onPressed: onPressed,
          icon: const Icon(Icons.tune),
        ),
        if (activeCount > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A dismissible chip representing an active filter.
class ActiveFilterChip {
  const ActiveFilterChip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;
}

/// 36dp chip strip — renders nothing when [chips] is empty so unfiltered
/// state takes zero vertical space.
class ActiveFiltersBar extends StatelessWidget {
  const ActiveFiltersBar({required this.chips, super.key});

  final List<ActiveFilterChip> chips;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final c = chips[i];
          return InputChip(
            label: Text(c.label),
            onDeleted: c.onRemove,
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}
