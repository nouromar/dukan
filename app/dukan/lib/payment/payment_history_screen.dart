// Payment history — past in/out payments. Same pattern as Sale/Receive
// history (date subtitle, funnel, chips). Inbound and outbound are
// visually distinguished by an arrow icon on the row leading edge.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/payment/payment_history_filter_sheet.dart';
import 'package:dukan/shared/date_range.dart';
import 'package:dukan/shared/history_date.dart';
import 'package:dukan/config/business_rules.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/list_filter_bar.dart';
import 'package:dukan/shared/money.dart';

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

  Future<List<PaymentSummary>> _fetch() {
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
            activeCount: _filters.activeBeyondDate +
                (_filters.dateRange.isDefault ? 0 : 1),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            ActiveFiltersBar(chips: chips),
            Expanded(
              child: FutureBuilder<List<PaymentSummary>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          l.paymentHistoryLoadFailedMessage,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    );
                  }
                  final rows = snapshot.data ?? const <PaymentSummary>[];
                  if (rows.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          l.paymentHistoryEmptyMessage,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _PaymentRow(
                        shop: widget.shop,
                        row: rows[i],
                      ),
                    ),
                  );
                },
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
    final icon = inbound
        ? Icons.arrow_downward
        : Icons.arrow_upward;
    final partyLabel = row.partyName ?? l.paymentHistoryNoParty;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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
      subtitle: Row(
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
    );
  }
}
