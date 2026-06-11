// Compact date-range picker bottom sheet. Pops with the new [DateRange]
// or null on cancel. Five rows: Today / Last 7 days / This month /
// All time / Custom range. "Custom" opens the platform date-range
// picker; the sheet stays out of the way unless the user picks it.

import 'package:flutter/material.dart';

import 'package:dukan/shared/date_range.dart';
import 'package:dukan/shared/l10n.dart';

Future<DateRange?> showDateRangeSheet(
  BuildContext context, {
  required DateRange current,
}) {
  return showModalBottomSheet<DateRange>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _DateRangeSheetBody(current: current),
  );
}

class _DateRangeSheetBody extends StatelessWidget {
  const _DateRangeSheetBody({required this.current});
  final DateRange current;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PresetTile(
            label: l.dateRangeToday,
            selected: current.preset == DateRangePreset.today,
            onTap: () => Navigator.of(context).pop(DateRange.today()),
          ),
          _PresetTile(
            label: l.dateRangeWeek,
            selected: current.preset == DateRangePreset.week,
            onTap: () => Navigator.of(context).pop(DateRange.week()),
          ),
          _PresetTile(
            label: l.dateRangeMonth,
            selected: current.preset == DateRangePreset.month,
            onTap: () => Navigator.of(context).pop(DateRange.month()),
          ),
          _PresetTile(
            label: l.dateRangeAll,
            selected: current.preset == DateRangePreset.all,
            onTap: () => Navigator.of(context).pop(DateRange.all),
          ),
          _PresetTile(
            label: l.dateRangeCustom,
            selected: current.preset == DateRangePreset.custom,
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 2),
                lastDate: now,
                initialDateRange: current.preset == DateRangePreset.custom
                    ? DateTimeRange(
                        start: current.from!,
                        end: current.to!.subtract(const Duration(days: 1)),
                      )
                    : null,
              );
              if (picked != null && context.mounted) {
                Navigator.of(context)
                    .pop(DateRange.custom(picked.start, picked.end));
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(
        label,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? theme.colorScheme.primary : null,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}
