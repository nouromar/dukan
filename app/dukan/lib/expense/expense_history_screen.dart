// Expense history — reverse-chronological list of past expense txns.
// Same shape as Sale/Receive history: funnel on the app bar, scope
// subtitle showing the active date range, optional dismissible chip
// row for the category filter.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/expense/expense_history_filter_sheet.dart';
import 'package:dukan/shared/date_range.dart';
import 'package:dukan/shared/history_date.dart';
import 'package:dukan/config/business_rules.dart';
import 'package:dukan/shared/future_list_scaffold.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/list_filter_bar.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

class ExpenseHistoryScreen extends StatefulWidget {
  const ExpenseHistoryScreen({required this.shop, super.key});
  final ShopSummary shop;

  @override
  State<ExpenseHistoryScreen> createState() => _ExpenseHistoryScreenState();
}

class _ExpenseHistoryScreenState extends State<ExpenseHistoryScreen> {
  late ExpenseHistoryFilters _filters;
  Future<List<ExpenseSummary>>? _future;
  String? _locale;

  @override
  void initState() {
    super.initState();
    _filters = ExpenseHistoryFilters.initial();
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

  Future<List<ExpenseSummary>> _fetch() async {
    // #375: local mirror when offline_mode = full.
    if (useLocalDb(context)) {
      final repo = context.read<LocalRepository>();
      final rows = await repo.historyExpenses(
        shopId: widget.shop.id,
        limit: historyPageLimit,
        dateFrom: _filters.dateRange.from,
        dateTo: _filters.dateRange.to,
      );
      var summaries =
          rows.map(repo.toExpenseSummary).toList(growable: false);
      if (_filters.categoryId != null) {
        summaries = summaries
            .where((e) => e.categoryId == _filters.categoryId)
            .toList(growable: false);
      }
      return summaries;
    }
    return context.read<ShopApi>().listExpenses(
          shopId: widget.shop.id,
          limit: historyPageLimit,
          dateFrom: _filters.dateRange.from,
          dateTo: _filters.dateRange.to,
          categoryId: _filters.categoryId,
          locale: _locale,
        );
  }

  void _reload() => setState(() => _future = _fetch());

  Future<void> _openFilterSheet() async {
    final next = await showExpenseHistoryFilterSheet(
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

  void _clearCategory() {
    setState(() {
      _filters = _filters.copyWith(clearCategory: true);
      _future = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final chips = <ActiveFilterChip>[
      if (_filters.categoryId != null)
        ActiveFilterChip(
          label: l.filterChipCategory(_filters.categoryName ?? ''),
          onRemove: _clearCategory,
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.expenseHistoryTitle),
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
              child: FutureListScaffold<ExpenseSummary>(
                future: _future,
                onRefresh: () async => _reload(),
                emptyMessage: l.expenseHistoryEmptyMessage,
                errorMessage: l.expenseHistoryLoadFailedMessage,
                itemBuilder: (_, row, _) => _ExpenseRow(
                  shop: widget.shop,
                  row: row,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.shop, required this.row});
  final ShopSummary shop;
  final ExpenseSummary row;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final categoryLabel =
        row.categoryName?.trim().isNotEmpty == true
            ? row.categoryName!
            : l.other;
    final subtitleBits = <String>[
      categoryLabel,
      if (row.paymentMethodCode == 'cash') l.saleHistoryCashLabel,
      if (row.notes?.trim().isNotEmpty == true) row.notes!.trim(),
    ];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Row(
        children: [
          Expanded(
            child: Text(
              formatHistoryStamp(context, row.occurredAt),
              style: theme.textTheme.titleMedium,
            ),
          ),
          Text(
            formatMoney(row.amount, shop),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      subtitle: Text(subtitleBits.join(' · ')),
    );
  }
}
