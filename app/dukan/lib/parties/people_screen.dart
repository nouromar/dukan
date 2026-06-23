// Shared body for the Customers + Suppliers screens.
//
// Replaces the prior 3-screen split (Parties list + Receivables report
// + Payables report). One unified per-type surface with:
//   * Headline summary tile (total owed + count) at the top
//   * Pinned search bar + filter funnel
//   * Sorted list (balance DESC by default; debtors float to top)
//   * FAB → add party + opening balance (delegates to add_party_sheet)
//
// Behaviour differences between customer + supplier are captured by
// the [PeopleKind] enum so the screen logic stays single-source.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/parties/parties_cache.dart';
import 'package:dukan/parties/party_detail_screen.dart';
import 'package:dukan/shared/add_party_sheet.dart';
import 'package:dukan/shared/display_name.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/list_filter_bar.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/realtime.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

/// Which side of the party world this screen renders.
enum PeopleKind { customer, supplier }

extension on PeopleKind {
  String typeCode() => switch (this) {
        PeopleKind.customer => 'customer',
        PeopleKind.supplier => 'supplier',
      };
}

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({
    required this.shop,
    required this.kind,
    this.initialHasBalanceOnly = false,
    super.key,
  });

  final ShopSummary shop;
  final PeopleKind kind;

  /// When true the screen opens already filtered to rows with
  /// non-zero balance — used by the Home Today-card shortcuts so a
  /// tap on "Customers owe you $X" lands on exactly those rows.
  final bool initialHasBalanceOnly;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

enum _PeopleSort { byBalance, byName }

class _PeopleScreenState extends State<PeopleScreen> {
  // #370: hold last-known list so explicit reloads (filter
  // change, watcher fire, pull-to-refresh) don't transition
  // through the spinner branch. Spinner only on cold start.
  List<PartySearchResult>? _lastKnown;

  final _searchController = TextEditingController();
  Future<List<PartySearchResult>>? _future;
  String _query = '';
  Timer? _debounce;
  late bool _hasBalanceOnly;
  _PeopleSort _sort = _PeopleSort.byBalance;
  RealtimeWatcher? _watcher;

  @override
  void initState() {
    super.initState();
    _hasBalanceOnly = widget.initialHasBalanceOnly;
    _future = _fetch();
    // Refetch when any party in this shop changes — handles cross-cashier
    // payment posts shifting balances, owner edits on web, new parties
    // added from the supplier picker on another open screen.
    _watcher = RealtimeWatcher.tryCreate(
      channelName:
          'people_list:${widget.kind.name}:${widget.shop.id}',
      subscriptions: [
        RealtimeSubscription(
          table: 'party',
          filter: realtimeEq('shop_id', widget.shop.id),
        ),
      ],
      onChange: () {
        if (!mounted) return;
        setState(() {
          _future = _fetch();
        });
      },
    );
  }

  @override
  void dispose() {
    _watcher?.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  bool get _isCustomer => widget.kind == PeopleKind.customer;

  /// SWR cache (#369) only kicks in for the default view: empty
  /// query AND no hasBalanceOnly filter. Sorting is client-side
  /// (re-applied below) so it doesn't disqualify caching.
  bool get _isDefaultView => _query.isEmpty && !_hasBalanceOnly;

  Future<List<PartySearchResult>> _fetch() async {
    // SWR fast path: paint cached, then refresh in background.
    if (_isDefaultView) {
      final cached = await PartiesCache.get(
        widget.shop.id,
        widget.kind.typeCode(),
      );
      if (cached != null) {
        // ignore: discarded_futures
        _refreshInBackground();
        return _applySort(cached);
      }
    }
    return _fetchFresh();
  }

  Future<List<PartySearchResult>> _fetchFresh() async {
    final api = context.read<ShopApi>();
    ConfigResolver? resolver;
    try {
      resolver = context.read<ConfigResolver>();
    } catch (_) {
      resolver = null;
    }
    // #374: when offline_mode = full, read from the local mirror.
    // hasBalanceOnly is applied client-side after the read; same
    // semantics as the network path (RPC also returns active only).
    if (useLocalDb(context)) {
      final repo = context.read<LocalRepository>();
      final parties = await repo.searchParties(
        _query,
        shopId: widget.shop.id,
        typeCode: widget.kind.typeCode(),
      );
      final filtered = parties.where((p) {
        if (!_hasBalanceOnly) return true;
        return p.receivable != 0 || p.payable != 0;
      }).map(repo.toPartySearchResult).toList();
      return _applySort(filtered);
    }
    final rows = await api.listParties(
      shopId: widget.shop.id,
      query: _query,
      type: widget.kind.typeCode(),
      hasBalanceOnly: _hasBalanceOnly,
    );
    if (_isDefaultView) {
      // ignore: discarded_futures
      PartiesCache.put(
        widget.shop.id,
        widget.kind.typeCode(),
        rows,
        resolver: resolver,
      );
    }
    return _applySort(rows);
  }

  Future<void> _refreshInBackground() async {
    try {
      final fresh = await _fetchFresh();
      if (!mounted || !_isDefaultView) return;
      setState(() => _future = Future.value(fresh));
    } catch (_) {
      // Silent — cached value is on screen; pull-to-refresh
      // recovers if needed.
    }
  }

  List<PartySearchResult> _applySort(List<PartySearchResult> rows) {
    // Server sorts by (receivable+payable) DESC then name; honour the
    // user-picked sort client-side so the toggle is instant.
    if (_sort == _PeopleSort.byName) {
      final sorted = [...rows]..sort((a, b) => a.name.compareTo(b.name));
      return sorted;
    }
    if (_isCustomer) {
      final sorted = [...rows]
        ..sort((a, b) {
          final c = b.receivable.compareTo(a.receivable);
          return c != 0 ? c : a.name.compareTo(b.name);
        });
      return sorted;
    }
    final sorted = [...rows]
      ..sort((a, b) {
        final c = b.payable.compareTo(a.payable);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    return sorted;
  }

  void _reload() => setState(() => _future = _fetch());

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim();
        _future = _fetch();
      });
    });
  }

  Future<void> _openFilterSheet() async {
    final next = await showModalBottomSheet<(_PeopleSort, bool)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _FilterSheetBody(
        kind: widget.kind,
        sort: _sort,
        hasBalanceOnly: _hasBalanceOnly,
      ),
    );
    if (next == null || !mounted) return;
    setState(() {
      _sort = next.$1;
      _hasBalanceOnly = next.$2;
      _future = _fetch();
    });
  }

  void _clearHasBalance() {
    setState(() {
      _hasBalanceOnly = false;
      _future = _fetch();
    });
  }

  Future<void> _onAdd() async {
    final created = await showAddPartySheet(
      context,
      shopId: widget.shop.id,
      typeCode: widget.kind.typeCode(),
      allowOpeningBalance: true,
    );
    if (created == null || !mounted) return;
    _reload();
  }

  Future<void> _openDetail(PartySearchResult row) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PartyDetailScreen(shop: widget.shop, partyId: row.id),
      ),
    );
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final title = _isCustomer ? l.customersTitle : l.suppliersTitle;
    final hint =
        _isCustomer ? l.customersSearchHint : l.suppliersSearchHint;
    final activeChips = <ActiveFilterChip>[
      if (_hasBalanceOnly)
        ActiveFilterChip(
          label: _isCustomer
              ? l.customersHasBalanceChip
              : l.suppliersHasBalanceChip,
          onRemove: _clearHasBalance,
        ),
    ];
    final activeFilterCount =
        (_hasBalanceOnly ? 1 : 0) + (_sort != _PeopleSort.byBalance ? 1 : 0);
    return Scaffold(
      appBar: dukanAppBar(context, title),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onAdd,
        icon: const Icon(Icons.add),
        label: Text(_isCustomer ? l.customersAddButton : l.suppliersAddButton),
      ),
      body: SafeArea(
        child: Column(
          children: [
            ListSearchBar(
              controller: _searchController,
              hintText: hint,
              onChanged: _onSearchChanged,
              onFilterTap: _openFilterSheet,
              filterCount: activeFilterCount,
            ),
            ActiveFiltersBar(chips: activeChips),
            Expanded(
              child: FutureBuilder<List<PartySearchResult>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasData) {
                    _lastKnown = snapshot.data;
                  }
                  final loaded = _lastKnown ?? snapshot.data;
                  if (loaded == null) {
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            l.partiesLoadFailedMessage,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows = loaded;
                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: _HeadlineTile(
                            kind: widget.kind,
                            shop: widget.shop,
                            rows: rows,
                          ),
                        ),
                        if (rows.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _query.isEmpty
                                      ? l.partiesEmptyMessage
                                      : l.partiesEmptyForQuery(_query),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          )
                        else
                          SliverList.separated(
                            itemCount: rows.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) => _PartyRow(
                              // #370: stable key so unchanged
                              // rows survive list rebuilds.
                              key: ValueKey(rows[i].id),
                              row: rows[i],
                              shop: widget.shop,
                              isCustomer: _isCustomer,
                              onTap: () => _openDetail(rows[i]),
                            ),
                          ),
                      ],
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

class _HeadlineTile extends StatelessWidget {
  const _HeadlineTile({
    required this.kind,
    required this.shop,
    required this.rows,
  });

  final PeopleKind kind;
  final ShopSummary shop;
  final List<PartySearchResult> rows;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final isCustomer = kind == PeopleKind.customer;
    final balances = rows
        .map((r) => isCustomer ? r.receivable : r.payable)
        .where((v) => v > 0)
        .toList(growable: false);
    final total = balances.fold<double>(0, (a, b) => a + b);
    final count = balances.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isCustomer
                          ? l.customersHeadlineLabel
                          : l.suppliersHeadlineLabel,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  Text(
                    formatMoney(total, shop),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: total > 0 ? theme.colorScheme.error : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                isCustomer
                    ? l.customersHeadlineCount(count)
                    : l.suppliersHeadlineCount(count),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartyRow extends StatelessWidget {
  const _PartyRow({
    super.key,
    required this.row,
    required this.shop,
    required this.isCustomer,
    required this.onTap,
  });

  final PartySearchResult row;
  final ShopSummary shop;
  final bool isCustomer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balance = isCustomer ? row.receivable : row.payable;
    Widget? trailing;
    if (balance > 0) {
      trailing = Text(
        isCustomer
            ? formatMoney(balance, shop)
            : '-${formatMoney(balance, shop)}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.error,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    final subtitleBits = <String>[
      if (row.phone != null && row.phone!.isNotEmpty) row.phone!,
    ];
    return ListTile(
      onTap: onTap,
      title: Text(
        displayName(row.name),
        style: theme.textTheme.titleMedium,
      ),
      subtitle:
          subtitleBits.isEmpty ? null : Text(subtitleBits.join(' · ')),
      trailing: trailing,
    );
  }
}

class _FilterSheetBody extends StatefulWidget {
  const _FilterSheetBody({
    required this.kind,
    required this.sort,
    required this.hasBalanceOnly,
  });

  final PeopleKind kind;
  final _PeopleSort sort;
  final bool hasBalanceOnly;

  @override
  State<_FilterSheetBody> createState() => _FilterSheetBodyState();
}

class _FilterSheetBodyState extends State<_FilterSheetBody> {
  late _PeopleSort _sort;
  late bool _hasBalance;

  @override
  void initState() {
    super.initState();
    _sort = widget.sort;
    _hasBalance = widget.hasBalanceOnly;
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final isCustomer = widget.kind == PeopleKind.customer;
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
            SwitchListTile(
              secondary: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(
                isCustomer
                    ? l.customersHasBalanceChip
                    : l.suppliersHasBalanceChip,
              ),
              value: _hasBalance,
              onChanged: (v) => setState(() => _hasBalance = v),
            ),
            ListTile(
              leading: const Icon(Icons.sort),
              title: Text(_sortLabel(context)),
              subtitle: Text(l.peopleSortLabel),
              trailing: PopupMenuButton<_PeopleSort>(
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: _PeopleSort.byBalance,
                    child: Text(
                      isCustomer
                          ? tr(ctx).peopleSortByReceivable
                          : tr(ctx).peopleSortByPayable,
                    ),
                  ),
                  PopupMenuItem(
                    value: _PeopleSort.byName,
                    child: Text(tr(ctx).peopleSortByName),
                  ),
                ],
                icon: const Icon(Icons.expand_more),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop((_PeopleSort.byBalance, false)),
                    child: Text(l.filterResetButton),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop((_sort, _hasBalance)),
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

  String _sortLabel(BuildContext context) {
    final l = tr(context);
    return switch (_sort) {
      _PeopleSort.byBalance => widget.kind == PeopleKind.customer
          ? l.peopleSortByReceivable
          : l.peopleSortByPayable,
      _PeopleSort.byName => l.peopleSortByName,
    };
  }
}
