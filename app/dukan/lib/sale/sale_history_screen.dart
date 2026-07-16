// Sale history — reverse-chronological list of past sales for the
// current shop. Filters live in a bottom sheet (funnel icon in the app
// bar); active non-date filters render as a compact dismissible chip
// row above the list. Date scope shows as a subtitle in the app bar so
// the user always knows what they're looking at without burning rows
// of screen real estate.
//
// v1 fetches `_pageLimit` rows after the filter clamp; pilot shops
// won't go deeper on day one. The RPC accepts a `before` cursor so
// "load more" is mechanical when we need it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/sale/sale_detail_screen.dart';
import 'package:dukan/sale/sale_history_cache.dart';
import 'package:dukan/sale/sale_history_filter_sheet.dart';
import 'package:dukan/shared/date_range.dart';
import 'package:dukan/shared/future_list_scaffold.dart';
import 'package:dukan/shared/history_date.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/config/business_rules.dart';
import 'package:dukan/shared/list_filter_bar.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/relative_time.dart';
import 'package:dukan/shared/voided_visibility.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

class SaleHistoryScreen extends StatefulWidget {
  const SaleHistoryScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<SaleHistoryScreen> createState() => _SaleHistoryScreenState();
}

class _SaleHistoryScreenState extends State<SaleHistoryScreen> {
  late SaleHistoryFilters _filters;
  late Future<List<SaleSummary>> _future;
  // Device pref (default show). The chip can still override for this visit.
  bool _showVoided = true;

  @override
  void initState() {
    super.initState();
    _filters = SaleHistoryFilters.initial();
    _future = _fetch();
    unawaited(_applyVoidedPref());
  }

  /// Apply the "Show voided" device pref as the initial default. Only acts when
  /// the pref is HIDE (default is show) — so the common case does no re-fetch.
  Future<void> _applyVoidedPref() async {
    final show = await VoidedVisibility.showVoided();
    if (!mounted || show) return;
    setState(() {
      _showVoided = false;
      _filters = _filters.copyWith(hideVoided: true);
      _future = _fetch();
    });
  }

  /// True when filters are at their (pref-derived) default — only this case is
  /// cached (per-filter keys would explode the cache). `hideVoided` matching the
  /// pref default still counts as default, so caching survives a hide-default.
  bool get _isDefaultFilters =>
      _filters.partyId == null &&
      _filters.hideVoided == !_showVoided &&
      _filters.dateRange.preset == DateRangePreset.all;

  Future<List<SaleSummary>> _fetch() async {
    // #375: when offline_mode=full, read straight from the local
    // mirror. SyncEngine keeps it warm; no network roundtrip needed.
    if (useLocalDb(context)) {
      final repo = context.read<LocalRepository>();
      final rows = await repo.historySales(
        shopId: widget.shop.id,
        limit: historyPageLimit,
        dateFrom: _filters.dateRange.from,
        dateTo: _filters.dateRange.to,
        partyId: _filters.partyId,
      );
      var summaries =
          rows.map(repo.toSaleSummary).toList(growable: false);
      if (_filters.hideVoided) {
        summaries =
            summaries.where((s) => !s.isVoided).toList(growable: false);
      }
      return summaries;
    }
    // SWR (#369): paint cached first, refresh in the background.
    if (_isDefaultFilters) {
      final cached = await SaleHistoryCache.get(widget.shop.id);
      if (cached != null) {
        // ignore: discarded_futures
        _refreshInBackground();
        return cached;
      }
    }
    return _fetchFresh();
  }

  Future<List<SaleSummary>> _fetchFresh() async {
    final api = context.read<ShopApi>();
    ConfigResolver? resolver;
    try {
      resolver = context.read<ConfigResolver>();
    } catch (_) {
      resolver = null;
    }
    final rows = await api.listSales(
      shopId: widget.shop.id,
      limit: historyPageLimit,
      dateFrom: _filters.dateRange.from,
      dateTo: _filters.dateRange.to,
      partyId: _filters.partyId,
    );
    if (_isDefaultFilters) {
      // ignore: discarded_futures
      SaleHistoryCache.put(widget.shop.id, rows, resolver: resolver);
    }
    return rows;
  }

  Future<void> _refreshInBackground() async {
    try {
      final fresh = await _fetchFresh();
      if (!mounted || !_isDefaultFilters) return;
      setState(() => _future = Future.value(fresh));
    } catch (_) {
      // Silent — cached value is on screen.
    }
  }

  void _reload() {
    setState(() => _future = _fetch());
  }

  Future<void> _openDetail(SaleSummary sale) async {
    final didChange = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SaleDetailScreen(shop: widget.shop, txnId: sale.txnId),
      ),
    );
    if (didChange == true && mounted) _reload();
  }

  Future<void> _openFilterSheet() async {
    final next = await showSaleHistoryFilterSheet(
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

  void _clearVoided() {
    setState(() {
      _filters = _filters.copyWith(hideVoided: false);
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
      if (_filters.hideVoided)
        ActiveFilterChip(
          label: l.filterChipHideVoided,
          onRemove: _clearVoided,
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.saleHistoryTitle),
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
              child: FutureListScaffold<SaleSummary>(
                future: _future,
                onRefresh: () async => _reload(),
                emptyMessage: l.saleHistoryEmptyMessage,
                errorMessage: l.saleHistoryLoadFailedMessage,
                filter: _filters.hideVoided
                    ? (sale) => !sale.isVoided
                    : null,
                itemBuilder: (_, sale, _) => _SaleRow(
                  shop: widget.shop,
                  sale: sale,
                  onTap: () => _openDetail(sale),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleRow extends StatelessWidget {
  const _SaleRow({
    required this.shop,
    required this.sale,
    required this.onTap,
  });

  final ShopSummary shop;
  final SaleSummary sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final base = sale.partyName != null
        ? l.saleHistoryDebtLabel(sale.partyName!)
        : l.saleHistoryCashLabel;
    // Tack on the void-time cue when this sale was voided. Uses the
    // existing voidedAt field (set on get_sale / list_sales) -- no
    // audit_log read needed for the void case (it's derivable from
    // the txn.reverses_transaction_id chain already).
    final subtitle = (sale.isVoided && sale.voidedAt != null)
        ? '$base · ${l.saleHistoryVoidedSubtitle(
            formatRelativeTime(context, sale.voidedAt!),
          )}'
        : base;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      title: Row(
        children: [
          Expanded(
            child: Text(
              formatHistoryStamp(context, sale.occurredAt),
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (sale.isVoided) ...[
            const SizedBox(width: 8),
            _VoidedBadge(text: l.saleHistoryVoidedBadge),
            const SizedBox(width: 8),
          ],
          Text(
            formatMoney(sale.totalAmount, shop),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              decoration: sale.isVoided ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
      subtitle: Text(subtitle),
      trailing: IconButton(
        tooltip: l.saleHistoryReceiptTooltip,
        icon: const Icon(Icons.receipt_long_outlined),
        onPressed: onTap,
      ),
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
