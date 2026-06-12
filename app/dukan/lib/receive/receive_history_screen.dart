// Bono (receive) history — reverse-chronological list of past bonos.
// Mirrors SaleHistoryScreen — same filter surface (date / supplier /
// hide voided), same scope-subtitle pattern in the app bar.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/receive/receive_detail_screen.dart';
import 'package:dukan/receive/receive_history_filter_sheet.dart';
import 'package:dukan/shared/date_range.dart';
import 'package:dukan/shared/history_date.dart';
import 'package:dukan/config/business_rules.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/list_filter_bar.dart';
import 'package:dukan/shared/money.dart';

class ReceiveHistoryScreen extends StatefulWidget {
  const ReceiveHistoryScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<ReceiveHistoryScreen> createState() => _ReceiveHistoryScreenState();
}

class _ReceiveHistoryScreenState extends State<ReceiveHistoryScreen> {
  late ReceiveHistoryFilters _filters;
  late Future<List<ReceiveSummary>> _future;

  @override
  void initState() {
    super.initState();
    _filters = ReceiveHistoryFilters.initial();
    _future = _fetch();
  }

  Future<List<ReceiveSummary>> _fetch() {
    return context.read<ShopApi>().listReceives(
          shopId: widget.shop.id,
          limit: historyPageLimit,
          dateFrom: _filters.dateRange.from,
          dateTo: _filters.dateRange.to,
          partyId: _filters.supplierId,
        );
  }

  void _reload() => setState(() => _future = _fetch());

  Future<void> _openDetail(ReceiveSummary receive) async {
    final didChange = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ReceiveDetailScreen(shop: widget.shop, txnId: receive.txnId),
      ),
    );
    if (didChange == true && mounted) _reload();
  }

  Future<void> _openFilterSheet() async {
    final next = await showReceiveHistoryFilterSheet(
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

  void _clearSupplier() {
    setState(() {
      _filters = _filters.copyWith(clearSupplier: true);
      _future = _fetch();
    });
  }

  void _clearVoidedHide() {
    setState(() {
      _filters = _filters.copyWith(hideVoided: false);
      _future = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final chips = <ActiveFilterChip>[
      if (_filters.supplierId != null)
        ActiveFilterChip(
          label: l.filterChipParty(_filters.supplierName ?? ''),
          onRemove: _clearSupplier,
        ),
      if (_filters.hideVoided)
        ActiveFilterChip(
          label: l.filterChipHideVoided,
          onRemove: _clearVoidedHide,
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.receiveHistoryTitle),
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
              child: FutureBuilder<List<ReceiveSummary>>(
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
                          l.receiveHistoryLoadFailedMessage,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    );
                  }
                  final all = snapshot.data ?? const <ReceiveSummary>[];
                  final rows = _filters.hideVoided
                      ? all.where((r) => !r.isVoided).toList(growable: false)
                      : all;
                  if (rows.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          l.receiveHistoryEmptyMessage,
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
                      itemBuilder: (context, i) => _ReceiveRow(
                        shop: widget.shop,
                        receive: rows[i],
                        onTap: () => _openDetail(rows[i]),
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

class _ReceiveRow extends StatelessWidget {
  const _ReceiveRow({
    required this.shop,
    required this.receive,
    required this.onTap,
  });

  final ShopSummary shop;
  final ReceiveSummary receive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final supplierName = receive.partyName ?? '—';
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Row(
        children: [
          Expanded(
            child: Text(
              formatHistoryStamp(context, receive.occurredAt),
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (receive.isVoided) ...[
            const SizedBox(width: 8),
            _VoidedBadge(text: l.receiveHistoryVoidedBadge),
            const SizedBox(width: 8),
          ],
          Text(
            formatMoney(receive.totalAmount, shop),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              decoration:
                  receive.isVoided ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
      subtitle: Text(l.receiveHistorySupplierLabel(supplierName)),
    );
  }
}

class _VoidedBadge extends StatelessWidget {
  const _VoidedBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
