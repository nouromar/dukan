// Compact date-time formatter for history rows (Sale, Receive, future
// debt log). The Sale + Receive screens previously rendered every row
// as bare HH:mm, which is only readable for today's rows — yesterday's
// "14:32" carries no day context.
//
// Rules (all in the device's local timezone):
//   * Today          → "14:32"
//   * Yesterday      → "Yesterday 14:32"  (localized word)
//   * Same year      → "Apr 6 14:32"
//   * Earlier year   → "6 Apr 2025"
//
// Locale handling: the `intl` package ships locale data for a fixed
// set (en, fr, es, ar, …) but NOT Somali. Passing 'so' to DateFormat
// throws `ArgumentError: Invalid locale "so"`. We try the requested
// locale first and fall back to English month/time symbols if intl
// doesn't recognise it. The "Yesterday" word stays localized via ARB.

import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart' as date_symbols;
import 'package:intl/intl.dart';

import 'package:dukan/shared/l10n.dart';

String formatHistoryStamp(BuildContext context, DateTime dt) {
  final l = tr(context);
  final locale = Localizations.localeOf(context).toLanguageTag();
  final local = dt.toLocal();
  final now = DateTime.now();
  final time = _safeFormat(local, locale, (lc) => DateFormat.Hm(lc));

  if (_isSameDay(local, now)) return time;

  final yesterday = DateTime(now.year, now.month, now.day - 1);
  if (_isSameDay(local, yesterday)) return '${l.historyYesterday} $time';

  if (local.year == now.year) {
    final md = _safeFormat(local, locale, (lc) => DateFormat.MMMd(lc));
    return '$md $time';
  }
  return _safeFormat(local, locale, (lc) => DateFormat.yMMMd(lc));
}

/// Try the requested locale; on `ArgumentError` (intl has no data for
/// it — Somali being the common case) fall back to English. `intl`'s
/// default-locale ensure runs once per process so the fallback is
/// cheap on repeated calls.
String _safeFormat(
  DateTime dt,
  String locale,
  DateFormat Function(String locale) factory,
) {
  try {
    return factory(locale).format(dt);
  } on ArgumentError {
    _ensureFallback();
    return factory('en').format(dt);
  }
}

bool _fallbackInitialized = false;

void _ensureFallback() {
  if (_fallbackInitialized) return;
  // initializeDateFormatting('en', null) is idempotent and synchronous
  // in practice (the en data is already linked at compile time).
  // Calling it ensures `DateFormat('en').format(...)` never fails even
  // when the ambient locale's data wasn't loaded.
  date_symbols.initializeDateFormatting('en', null);
  _fallbackInitialized = true;
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
