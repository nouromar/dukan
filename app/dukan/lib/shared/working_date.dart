import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:dukan/shared/history_date.dart';
import 'package:dukan/shared/l10n.dart';

/// Sticky backdating (#5). A daily-flow controller mixes this in to optionally
/// record a transaction for a PAST day. `null` = today — the happy path, zero
/// extra taps. Backdate mode is sticky within one screen session (so you can
/// enter several transactions for the same past day) and resets on each fresh
/// entry into the flow via [initWorkingDate], and on cold start (the
/// controllers are recreated).
mixin WorkingDateMixin on ChangeNotifier {
  DateTime? _workingDate;

  /// Non-null only when recording for a past day. `null` = today.
  DateTime? get workingDate => _workingDate;
  bool get isBackdated => _workingDate != null;

  /// The timestamp to stamp on the transaction: the backdate, or `now()` today.
  /// Used for both the optimistic local write and the posted `occurred_at`.
  DateTime get effectiveDate => _workingDate ?? DateTime.now();

  /// Notifying — for the in-screen chip / "back to today".
  void setWorkingDate(DateTime? date) {
    if (_workingDate == date) return;
    _workingDate = date;
    notifyListeners();
  }

  /// Non-notifying reset — safe to call from a screen's `initState` (a notify
  /// there would fire during build). Each fresh entry into the flow defaults
  /// back to today.
  void initWorkingDate() {
    _workingDate = null;
  }
}

/// How far back you may backdate. Generous enough to catch up a month of
/// missed entries, bounded so a stray tap can't land a sale in another year.
const Duration kBackdateWindow = Duration(days: 30);

/// Opens the past-date picker. Returns the chosen working date (with the
/// current time-of-day so it sorts naturally and survives timezone
/// conversion), or `null` if the user picked today / cancelled — caller passes
/// that straight to [WorkingDateMixin.setWorkingDate].
Future<DateTime?> pickWorkingDate(
  BuildContext context, {
  DateTime? current,
}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final picked = await showDatePicker(
    context: context,
    initialDate: current ?? now,
    firstDate: today.subtract(kBackdateWindow),
    lastDate: now,
  );
  if (picked == null) return current; // cancelled — leave the date unchanged.
  final pickedDay = DateTime(picked.year, picked.month, picked.day);
  if (pickedDay == today) return null; // today → not backdated.
  // Stamp the current time-of-day onto the chosen day.
  return DateTime(
    picked.year,
    picked.month,
    picked.day,
    now.hour,
    now.minute,
    now.second,
  );
}

/// A muted app-bar chip for the daily-entry flows. Reads "Today" normally;
/// turns loud and shows the date when backdating. Tap → past-date picker.
class WorkingDateChip extends StatelessWidget {
  const WorkingDateChip({
    required this.workingDate,
    required this.onChanged,
    super.key,
  });

  final DateTime? workingDate;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final scheme = Theme.of(context).colorScheme;
    final backdated = workingDate != null;
    final label =
        backdated ? formatInvoiceDate(context, workingDate!) : l.backdateChipToday;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: ActionChip(
        avatar: Icon(
          backdated ? Icons.event_busy : Icons.event,
          size: 18,
          color: backdated ? scheme.onTertiaryContainer : scheme.onSurfaceVariant,
        ),
        label: Text(label),
        tooltip: l.backdateChipTooltip,
        labelStyle: TextStyle(
          color: backdated ? scheme.onTertiaryContainer : scheme.onSurfaceVariant,
          fontWeight: backdated ? FontWeight.w700 : FontWeight.w400,
        ),
        backgroundColor:
            backdated ? scheme.tertiaryContainer : Colors.transparent,
        side: backdated
            ? BorderSide.none
            : BorderSide(color: scheme.outlineVariant),
        onPressed: () async {
          final next = await pickWorkingDate(context, current: workingDate);
          onChanged(next);
        },
      ),
    );
  }
}

/// A loud banner shown above the body while backdating, so the shopkeeper
/// can't forget the entry is for a past day. One tap returns to today.
class BackdateBanner extends StatelessWidget {
  const BackdateBanner({
    required this.date,
    required this.onClear,
    super.key,
  });

  final DateTime date;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.event_busy, size: 20, color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l.backdateBannerLabel(formatInvoiceDate(context, date)),
                style: TextStyle(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: onClear,
              child: Text(l.backdateBackToToday),
            ),
          ],
        ),
      ),
    );
  }
}
