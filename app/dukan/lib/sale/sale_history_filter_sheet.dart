// Sale-history filter sheet. Three controls:
//
//   * Date range (Today / 7d / Month / All / Custom)
//   * Party (Anyone / pick via party picker sheet)
//   * Include voided (toggle)
//
// Pops the new [SaleHistoryFilters] or null if the user cancels.

import 'package:flutter/material.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/shared/date_range.dart';
import 'package:dukan/shared/date_range_sheet.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/party_picker_sheet.dart';

/// Filter state for the Sale history screen.
///
/// Voided sales are visible by default — voiding leaves a corrected
/// record on purpose (strike-through is the proof), and hiding by
/// default would confuse a cashier looking for "the sale I just
/// undid". `hideVoided` lets them clean up the view when they want.
class SaleHistoryFilters {
  const SaleHistoryFilters({
    required this.dateRange,
    this.partyId,
    this.partyName,
    this.hideVoided = false,
  });

  factory SaleHistoryFilters.initial() =>
      SaleHistoryFilters(dateRange: DateRange.today());

  final DateRange dateRange;
  final String? partyId;
  final String? partyName;
  final bool hideVoided;

  SaleHistoryFilters copyWith({
    DateRange? dateRange,
    String? partyId,
    String? partyName,
    bool clearParty = false,
    bool? hideVoided,
  }) {
    return SaleHistoryFilters(
      dateRange: dateRange ?? this.dateRange,
      partyId: clearParty ? null : (partyId ?? this.partyId),
      partyName: clearParty ? null : (partyName ?? this.partyName),
      hideVoided: hideVoided ?? this.hideVoided,
    );
  }

  /// Non-default filters that should render as removable chips.
  int get activeBeyondDate =>
      (partyId != null ? 1 : 0) + (hideVoided ? 1 : 0);
}

Future<SaleHistoryFilters?> showSaleHistoryFilterSheet(
  BuildContext context, {
  required ShopSummary shop,
  required SaleHistoryFilters current,
}) {
  return showModalBottomSheet<SaleHistoryFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _SaleHistoryFilterSheetBody(
      shop: shop,
      initial: current,
    ),
  );
}

class _SaleHistoryFilterSheetBody extends StatefulWidget {
  const _SaleHistoryFilterSheetBody({
    required this.shop,
    required this.initial,
  });

  final ShopSummary shop;
  final SaleHistoryFilters initial;

  @override
  State<_SaleHistoryFilterSheetBody> createState() =>
      _SaleHistoryFilterSheetBodyState();
}

class _SaleHistoryFilterSheetBodyState
    extends State<_SaleHistoryFilterSheetBody> {
  late SaleHistoryFilters _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  Future<void> _pickDate() async {
    final next = await showDateRangeSheet(context, current: _draft.dateRange);
    if (next != null && mounted) {
      setState(() => _draft = _draft.copyWith(dateRange: next));
    }
  }

  Future<void> _pickParty() async {
    final picked = await showPartyPicker(
      context,
      shop: widget.shop,
      typeCode: 'customer',
    );
    if (picked != null && mounted) {
      setState(() => _draft = _draft.copyWith(
            partyId: picked.id,
            partyName: picked.name,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l.filterSheetTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
            // Date row.
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(dateRangeLabel(context, _draft.dateRange)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDate,
            ),
            // Party row.
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(_draft.partyName ?? l.filterPartyAny),
              trailing: _draft.partyId != null
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() =>
                          _draft = _draft.copyWith(clearParty: true)),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _pickParty,
            ),
            // Voided toggle — flipped: voided rows are visible by
            // default, the toggle hides them when the user wants.
            SwitchListTile(
              secondary: const Icon(Icons.do_not_disturb_alt_outlined),
              title: Text(l.filterHideVoided),
              value: _draft.hideVoided,
              onChanged: (v) =>
                  setState(() => _draft = _draft.copyWith(hideVoided: v)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop(SaleHistoryFilters.initial()),
                    child: Text(l.filterResetButton),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_draft),
                    child: Text(l.filterApplyButton),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
