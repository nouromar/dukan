// Bilingual "{n} {unit} ago" formatter for inline audit cues.
//
// Renders the elapsed-since time in the most readable unit, capped
// per unit:
//   < 1 min  -> "just now"
//   < 60 min -> "{n} min ago"
//   < 24 hr  -> "{n} hr ago"
//   < 30 day -> "{n} day ago"
//   else     -> "on {short_date}"
//
// Both languages handled via the ARB ICU plural keys in app_en.arb /
// app_so.arb. Reads the current locale from AppLocalizations.of to
// stay in sync with Settings-driven language changes mid-session.

import 'package:flutter/material.dart';

import 'package:dukan/shared/history_date.dart';
import 'package:dukan/shared/l10n.dart';

String formatRelativeTime(BuildContext context, DateTime when, {DateTime? now}) {
  final l = tr(context);
  final reference = now ?? DateTime.now();
  final diff = reference.difference(when);
  if (diff.isNegative || diff.inSeconds < 60) {
    return l.relativeTimeJustNow;
  }
  if (diff.inMinutes < 60) {
    return l.relativeTimeMinutesAgo(diff.inMinutes);
  }
  if (diff.inHours < 24) {
    return l.relativeTimeHoursAgo(diff.inHours);
  }
  if (diff.inDays < 30) {
    return l.relativeTimeDaysAgo(diff.inDays);
  }
  // Past a month, fall back to the short date — the cue stops being
  // useful as a relative number.
  return l.relativeTimeOn(formatHistoryStamp(context, when));
}
