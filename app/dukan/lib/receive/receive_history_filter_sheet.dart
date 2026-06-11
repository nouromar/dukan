// Receive-history filter sheet. Same shape as the Sale variant —
// date / party (supplier) / hide voided.

import 'package:flutter/material.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/shared/date_range.dart';
import 'package:dukan/shared/date_range_sheet.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/party_picker_sheet.dart';

class ReceiveHistoryFilters {
  const ReceiveHistoryFilters({
    required this.dateRange,
    this.supplierId,
    this.supplierName,
    this.hideVoided = false,
  });

  factory ReceiveHistoryFilters.initial() =>
      ReceiveHistoryFilters(dateRange: DateRange.today());

  final DateRange dateRange;
  final String? supplierId;
  final String? supplierName;
  final bool hideVoided;

  ReceiveHistoryFilters copyWith({
    DateRange? dateRange,
    String? supplierId,
    String? supplierName,
    bool clearSupplier = false,
    bool? hideVoided,
  }) {
    return ReceiveHistoryFilters(
      dateRange: dateRange ?? this.dateRange,
      supplierId:
          clearSupplier ? null : (supplierId ?? this.supplierId),
      supplierName:
          clearSupplier ? null : (supplierName ?? this.supplierName),
      hideVoided: hideVoided ?? this.hideVoided,
    );
  }

  int get activeBeyondDate =>
      (supplierId != null ? 1 : 0) + (hideVoided ? 1 : 0);
}

Future<ReceiveHistoryFilters?> showReceiveHistoryFilterSheet(
  BuildContext context, {
  required ShopSummary shop,
  required ReceiveHistoryFilters current,
}) {
  return showModalBottomSheet<ReceiveHistoryFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _ReceiveHistoryFilterSheetBody(
      shop: shop,
      initial: current,
    ),
  );
}

class _ReceiveHistoryFilterSheetBody extends StatefulWidget {
  const _ReceiveHistoryFilterSheetBody({
    required this.shop,
    required this.initial,
  });

  final ShopSummary shop;
  final ReceiveHistoryFilters initial;

  @override
  State<_ReceiveHistoryFilterSheetBody> createState() =>
      _ReceiveHistoryFilterSheetBodyState();
}

class _ReceiveHistoryFilterSheetBodyState
    extends State<_ReceiveHistoryFilterSheetBody> {
  late ReceiveHistoryFilters _draft;

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

  Future<void> _pickSupplier() async {
    final picked = await showPartyPicker(
      context,
      shop: widget.shop,
      typeCode: 'supplier',
    );
    if (picked != null && mounted) {
      setState(() => _draft = _draft.copyWith(
            supplierId: picked.id,
            supplierName: picked.name,
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
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(dateRangeLabel(context, _draft.dateRange)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDate,
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: Text(_draft.supplierName ?? l.filterPartyAny),
              trailing: _draft.supplierId != null
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() =>
                          _draft = _draft.copyWith(clearSupplier: true)),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _pickSupplier,
            ),
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
                        .pop(ReceiveHistoryFilters.initial()),
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
