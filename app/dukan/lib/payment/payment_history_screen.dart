// Payment history — past in/out payments. Same pattern as Sale/Receive
// history (date subtitle, funnel, chips). Inbound and outbound are
// visually distinguished by an arrow icon on the row leading edge.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/payment/payment_detail_screen.dart';
import 'package:dukan/payment/payment_history_filter_sheet.dart';
import 'package:dukan/shared/date_range.dart';
import 'package:dukan/shared/history_date.dart';
import 'package:dukan/config/business_rules.dart';
import 'package:dukan/shared/future_list_scaffold.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/list_filter_bar.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({required this.shop, super.key});
  final ShopSummary shop;

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  late PaymentHistoryFilters _filters;
  Future<List<PaymentSummary>>? _future;
  String? _locale;

  @override
  void initState() {
    super.initState();
    _filters = PaymentHistoryFilters.initial();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = Localizations.localeOf(context).languageCode;
    if (_locale != current || _future == null) {
      _locale = current;
      _future = _fetch();
    }
  }

  Future<List<PaymentSummary>> _fetch() async {
    // #375: local mirror when offline_mode = full.
    if (useLocalDb(context)) {
      final repo = context.read<LocalRepository>();
      final rows = await repo.historyPayments(
        shopId: widget.shop.id,
        limit: historyPageLimit,
        dateFrom: _filters.dateRange.from,
        dateTo: _filters.dateRange.to,
        partyId: _filters.partyId,
        direction: _filters.direction.toCode(),
      );
      // Hide walk-in cash-sale legs by default (the server's list_payments
      // does the same for the online path). Show-mode keeps them.
      return rows
          .map(repo.toPaymentSummary)
          .where((p) => !widget.shop.hideSettlementLegs || !p.isSettlementLeg)
          .toList(growable: false);
    }
    return context.read<ShopApi>().listPayments(
      shopId: widget.shop.id,
      limit: historyPageLimit,
      dateFrom: _filters.dateRange.from,
      dateTo: _filters.dateRange.to,
      partyId: _filters.partyId,
      direction: _filters.direction.toCode(),
    );
  }

  void _reload() => setState(() => _future = _fetch());

  Future<void> _openFilterSheet() async {
    final next = await showPaymentHistoryFilterSheet(
      context,
      shop: widget.shop,
      current: _filters,
    );
    if (next == null || !mounted) return;
    setState(() {
      _filters = next;
      _future = _fetch();
    });
  }

  void _clearParty() {
    setState(() {
      _filters = _filters.copyWith(clearParty: true);
      _future = _fetch();
    });
  }

  void _clearDirection() {
    setState(() {
      _filters = _filters.copyWith(direction: PaymentDirectionFilter.any);
      _future = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final chips = <ActiveFilterChip>[
      if (_filters.partyId != null)
        ActiveFilterChip(
          label: l.filterChipParty(_filters.partyName ?? ''),
          onRemove: _clearParty,
        ),
      if (_filters.direction != PaymentDirectionFilter.any)
        ActiveFilterChip(
          label: _filters.direction.label(context),
          onRemove: _clearDirection,
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.paymentHistoryTitle),
            Text(
              dateRangeLabel(context, _filters.dateRange),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          FilterFunnelAction(
            onPressed: _openFilterSheet,
            activeCount:
                _filters.activeBeyondDate +
                (_filters.dateRange.isDefault ? 0 : 1),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            ActiveFiltersBar(chips: chips),
            Expanded(
              child: FutureListScaffold<PaymentSummary>(
                future: _future,
                onRefresh: () async => _reload(),
                emptyMessage: l.paymentHistoryEmptyMessage,
                errorMessage: l.paymentHistoryLoadFailedMessage,
                itemBuilder: (_, row, _) =>
                    _PaymentRow(shop: widget.shop, row: row),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.shop, required this.row});
  final ShopSummary shop;
  final PaymentSummary row;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final inbound = row.direction == 'I';
    final color = inbound
        ? theme.colorScheme.tertiary
        : theme.colorScheme.error;
    final icon = inbound ? Icons.arrow_downward : Icons.arrow_upward;
    final partyLabel = row.partyName ?? l.paymentHistoryNoParty;
    final note = row.notes?.trim();
    final hasNote = note != null && note.isNotEmpty;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              PaymentDetailScreen(shop: shop, paymentId: row.paymentId),
        ),
      ),
      leading: Icon(icon, color: color),
      title: Row(
        children: [
          Expanded(
            child: Text(
              formatHistoryStamp(context, row.occurredAt),
              style: theme.textTheme.titleMedium,
            ),
          ),
          Text(
            '${inbound ? '+' : '-'}${formatMoney(row.amount, shop)}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
      // Subtitle is a Column so the optional note can sit on its own
      // line below the party/refund row. Without this the cashier had
      // no way to see the note they typed on save (filed as #345 from
      // the iPhone test-pass — `notes` was already on PaymentSummary
      // but never rendered).
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(partyLabel)),
              if (row.isRefund)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6),
                  child: Text(
                    l.paymentHistoryRefundBadge,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
          if (hasNote)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                note,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
