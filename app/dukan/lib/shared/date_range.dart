// Date-range presets used by history list filters. Sales/Receives
// default to "Today" since that's the most-common scope; users can
// widen to week / month / custom via the filter sheet.
//
// The preset is resolved against the device's *local* day boundaries
// when applied — server-side filtering uses the resulting [from, to)
// timestamps. Custom ranges carry their own explicit values.

import 'package:flutter/material.dart';

import 'package:dukan/shared/l10n.dart';

enum DateRangePreset { today, week, month, all, custom }

class DateRange {
  const DateRange({required this.preset, this.from, this.to});

  final DateRangePreset preset;

  /// Inclusive lower bound. Null when [preset] is [DateRangePreset.all].
  final DateTime? from;

  /// Exclusive upper bound. Null when [preset] is [DateRangePreset.all].
  final DateTime? to;

  static const DateRange all = DateRange(preset: DateRangePreset.all);

  /// Today-only, resolved to local-day boundaries at call time.
  factory DateRange.today({DateTime? now}) {
    final n = now ?? DateTime.now();
    final start = DateTime(n.year, n.month, n.day);
    return DateRange(
      preset: DateRangePreset.today,
      from: start,
      to: start.add(const Duration(days: 1)),
    );
  }

  factory DateRange.week({DateTime? now}) {
    final n = now ?? DateTime.now();
    final start = DateTime(n.year, n.month, n.day)
        .subtract(const Duration(days: 6));
    final end = DateTime(n.year, n.month, n.day)
        .add(const Duration(days: 1));
    return DateRange(
      preset: DateRangePreset.week,
      from: start,
      to: end,
    );
  }

  factory DateRange.month({DateTime? now}) {
    final n = now ?? DateTime.now();
    final start = DateTime(n.year, n.month, 1);
    final end = DateTime(n.year, n.month + 1, 1);
    return DateRange(
      preset: DateRangePreset.month,
      from: start,
      to: end,
    );
  }

  factory DateRange.custom(DateTime from, DateTime to) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day)
        .add(const Duration(days: 1));
    return DateRange(
      preset: DateRangePreset.custom,
      from: start,
      to: end,
    );
  }

  bool get isDefault => preset == DateRangePreset.today;
  bool get isAll => preset == DateRangePreset.all;
}

String dateRangeLabel(BuildContext context, DateRange range) {
  final l = tr(context);
  switch (range.preset) {
    case DateRangePreset.today:
      return l.dateRangeToday;
    case DateRangePreset.week:
      return l.dateRangeWeek;
    case DateRangePreset.month:
      return l.dateRangeMonth;
    case DateRangePreset.all:
      return l.dateRangeAll;
    case DateRangePreset.custom:
      final f = range.from!;
      final t = range.to!.subtract(const Duration(days: 1));
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(f.day)}/${two(f.month)} – ${two(t.day)}/${two(t.month)}';
  }
}
