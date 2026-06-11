// Payment-history filter sheet. Three controls:
//   * Date range
//   * Party (any / pick via party picker — both customer + supplier
//     candidates since payment direction decides the side)
//   * Direction (Any / Inbound / Outbound)

import 'package:flutter/material.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/shared/date_range.dart';
import 'package:dukan/shared/date_range_sheet.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/party_picker_sheet.dart';

enum PaymentDirectionFilter { any, inbound, outbound }

extension PaymentDirectionFilterX on PaymentDirectionFilter {
  /// Server-side code: 'I'/'O'/null.
  String? toCode() => switch (this) {
        PaymentDirectionFilter.any => null,
        PaymentDirectionFilter.inbound => 'I',
        PaymentDirectionFilter.outbound => 'O',
      };

  String label(BuildContext context) {
    final l = tr(context);
    return switch (this) {
      PaymentDirectionFilter.any => l.paymentDirectionAny,
      PaymentDirectionFilter.inbound => l.paymentDirectionInbound,
      PaymentDirectionFilter.outbound => l.paymentDirectionOutbound,
    };
  }
}

class PaymentHistoryFilters {
  const PaymentHistoryFilters({
    required this.dateRange,
    this.partyId,
    this.partyName,
    this.direction = PaymentDirectionFilter.any,
  });

  factory PaymentHistoryFilters.initial() =>
      PaymentHistoryFilters(dateRange: DateRange.today());

  final DateRange dateRange;
  final String? partyId;
  final String? partyName;
  final PaymentDirectionFilter direction;

  PaymentHistoryFilters copyWith({
    DateRange? dateRange,
    String? partyId,
    String? partyName,
    bool clearParty = false,
    PaymentDirectionFilter? direction,
  }) {
    return PaymentHistoryFilters(
      dateRange: dateRange ?? this.dateRange,
      partyId: clearParty ? null : (partyId ?? this.partyId),
      partyName: clearParty ? null : (partyName ?? this.partyName),
      direction: direction ?? this.direction,
    );
  }

  int get activeBeyondDate =>
      (partyId != null ? 1 : 0) +
      (direction != PaymentDirectionFilter.any ? 1 : 0);
}

Future<PaymentHistoryFilters?> showPaymentHistoryFilterSheet(
  BuildContext context, {
  required ShopSummary shop,
  required PaymentHistoryFilters current,
}) {
  return showModalBottomSheet<PaymentHistoryFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _Body(shop: shop, initial: current),
  );
}

class _Body extends StatefulWidget {
  const _Body({required this.shop, required this.initial});
  final ShopSummary shop;
  final PaymentHistoryFilters initial;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late PaymentHistoryFilters _draft;

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
    // Direction decides which type to surface; "any" defaults to
    // customer (the most common inbound payee) — outbound users can
    // toggle the direction first.
    final type = _draft.direction == PaymentDirectionFilter.outbound
        ? 'supplier'
        : 'customer';
    final picked = await showPartyPicker(
      context,
      shop: widget.shop,
      typeCode: type,
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
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(dateRangeLabel(context, _draft.dateRange)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDate,
            ),
            ListTile(
              leading: const Icon(Icons.swap_vert),
              title: Text(_draft.direction.label(context)),
              subtitle: Text(l.paymentDirectionLabel),
              trailing: PopupMenuButton<PaymentDirectionFilter>(
                onSelected: (v) => setState(
                    () => _draft = _draft.copyWith(direction: v)),
                itemBuilder: (ctx) => [
                  for (final d in PaymentDirectionFilter.values)
                    PopupMenuItem(value: d, child: Text(d.label(ctx))),
                ],
                icon: const Icon(Icons.expand_more),
              ),
            ),
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
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop(PaymentHistoryFilters.initial()),
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
