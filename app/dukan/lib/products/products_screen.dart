// Products screen — v2 (data-model-v2.md §11.11). Lists the shop_items
// this shop carries (one row per shop_item, not per packaging). Activation
// of new catalog items moved out of this screen into the catalog picker;
// shop-local item creation lives in the shop_item editor. This file is
// pure list + navigation — no posting, no activation, no price edits.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/products/catalog_picker_screen.dart';
import 'package:dukan/products/products_cache.dart';
import 'package:dukan/products/products_filter_sheet.dart';
import 'package:dukan/products/shop_item_detail_screen.dart';
import 'package:dukan/sale/add_new_item_sheet.dart';
import 'package:dukan/shared/display_name.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/list_filter_bar.dart';
import 'package:dukan/shared/low_stock.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/realtime.dart';
import 'package:dukan/shared/stock_format.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

enum _ProductsSort { name, stockLowFirst }

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _searchController = TextEditingController();
  late Future<List<ShopItemSummary>> _resultsFuture;
  // #370: hold last-known results so explicit reloads
  // (filter change, realtime watcher, return-from-detail) don't
  // flash the spinner over an already-rendered list. Spinner only
  // fires on the truly-cold path.
  List<ShopItemSummary>? _lastKnown;
  String _activeQuery = '';
  Timer? _debounce;
  ProductsFilters _filters = ProductsFilters.initial();
  _ProductsSort _sort = _ProductsSort.name;

  String? _locale;
  RealtimeWatcher? _watcher;

  @override
  void initState() {
    super.initState();
    // Filter on shop_id so a multi-shop owner using the same session
    // only refetches when the *current* shop's products move. Price
    // edits on a packaging row also bubble up via shop_item_unit so
    // the "$1.00/Kg" subtitle stays current.
    _watcher = RealtimeWatcher.tryCreate(
      channelName: 'products_list:${widget.shop.id}',
      subscriptions: [
        RealtimeSubscription(
          table: 'shop_item',
          filter: realtimeEq('shop_id', widget.shop.id),
        ),
        RealtimeSubscription(
          table: 'shop_item_unit',
          filter: realtimeEq('shop_id', widget.shop.id),
        ),
      ],
      onChange: _onRealtime,
    );
  }

  void _onRealtime() {
    if (!mounted) return;
    setState(() {
      _resultsFuture = _fetch(_activeQuery);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = Localizations.localeOf(context).languageCode;
    if (_locale != current) {
      _locale = current;
      _resultsFuture = _fetch(_activeQuery);
    }
  }

  @override
  void dispose() {
    _watcher?.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// True when neither search query nor any filter is active —
  /// the only case we cache (per-query keys would balloon).
  bool _isDefaultView(String query) =>
      query.isEmpty &&
      _filters.categoryId == null &&
      !_filters.lowStockOnly &&
      !_filters.noPriceOnly;

  Future<List<ShopItemSummary>> _fetch(String query) async {
    // SWR (#369): if this is the default unfiltered view, return
    // the cached list immediately and schedule a background fetch
    // to refresh on next render. Filtered / searched views skip
    // the cache.
    if (_isDefaultView(query)) {
      final cached = await ProductsCache.get(widget.shop.id);
      if (cached != null) {
        // Schedule background refresh — fire-and-forget; the
        // refresh swaps in fresh data via setState when it
        // returns. UI shows the cached snapshot in the meantime.
        // ignore: discarded_futures
        _refreshInBackground(query);
        return cached;
      }
    }
    return _fetchFresh(query);
  }

  Future<List<ShopItemSummary>> _fetchFresh(String query) async {
    // Capture context-dependent values BEFORE the await — using
    // context after an async gap trips the analyzer.
    final api = context.read<ShopApi>();
    final locale = Localizations.localeOf(context).languageCode;
    ConfigResolver? resolver;
    try {
      resolver = context.read<ConfigResolver>();
    } catch (_) {
      resolver = null;
    }
    // #374: when offline_mode = full, read from the local mirror.
    if (useLocalDb(context)) {
      final repo = context.read<LocalRepository>();
      final items = await repo.allActiveItems(widget.shop.id);
      // One batched read of pending queued stock deltas so each row shows
      // projected stock without an N-item lookup.
      final deltas = await repo.projectionDeltas();
      final summaries = <ShopItemSummary>[];
      for (final item in items) {
        // Apply name + category filters in-memory.
        if (query.isNotEmpty &&
            !item.displayName.toLowerCase().contains(query.toLowerCase())) {
          continue;
        }
        if (_filters.categoryId != null &&
            item.categoryId != _filters.categoryId) {
          continue;
        }
        summaries.add(await repo.toShopItemSummary(
          item,
          projectionDelta: deltas[item.shopItemId] ?? 0,
        ));
      }
      return summaries;
    }
    try {
      final items = await api.listShopItems(
        shopId: widget.shop.id,
        query: query.isEmpty ? null : query,
        categoryId: _filters.categoryId,
        locale: locale,
      );
      // Only cache the default view (matching the read path).
      if (_isDefaultView(query)) {
        // ignore: discarded_futures
        ProductsCache.put(widget.shop.id, items, resolver: resolver);
      }
      return items;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan products',
          context: ErrorDescription('listing shop items'),
        ),
      );
      rethrow;
    }
  }

  Future<void> _refreshInBackground(String query) async {
    try {
      final fresh = await _fetchFresh(query);
      if (!mounted) return;
      // Only swap if the query/filter context hasn't moved on.
      if (_activeQuery == query && _isDefaultView(query)) {
        setState(() => _resultsFuture = Future.value(fresh));
      }
    } catch (_) {
      // Background refresh failures are silent; the user sees
      // the cached value and a pull-to-refresh recovery path.
    }
  }

  Future<void> _openFilterSheet() async {
    final next = await showProductsFilterSheet(
      context,
      current: _filters,
      shopId: widget.shop.id,
    );
    if (next == null || !mounted) return;
    setState(() {
      _filters = next;
      _resultsFuture = _fetch(_activeQuery);
    });
  }

  void _clearCategory() {
    setState(() {
      _filters = _filters.copyWith(clearCategory: true);
      _resultsFuture = _fetch(_activeQuery);
    });
  }

  void _clearNoPrice() {
    setState(() {
      _filters = _filters.copyWith(noPriceOnly: false);
    });
  }

  void _clearLowStock() {
    setState(() {
      _filters = _filters.copyWith(lowStockOnly: false);
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _activeQuery = value.trim();
        _resultsFuture = _fetch(_activeQuery);
      });
    });
  }

  void _reload() {
    setState(() {
      _resultsFuture = _fetch(_activeQuery);
    });
  }

  Future<void> _openDetail(ShopItemSummary row) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ShopItemDetailScreen(
          shop: widget.shop,
          shopItemId: row.shopItemId,
          displayName: row.displayName,
        ),
      ),
    );
    if (!mounted) return;
    // Detail screen edits (price, packagings, aliases) can mutate the
    // current_stock projection / unit_count — refresh on return so the
    // list reflects whatever the sibling editor just did.
    _reload();
  }

  Future<void> _openEditor() async {
    // Simplified single-packaging create (name → how sold → price → optional
    // opening stock). Advanced editing — extra sizes, aliases, supplier,
    // barcode — lives on ShopItemDetailScreen after the product exists.
    await AddNewItemSheet.show(
      context,
      widget.shop,
      initialName: '',
      variant: AddNewItemVariant.product,
    );
    if (!mounted) return;
    _reload();
  }

  Future<void> _openCatalogPicker() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CatalogPickerScreen(shop: widget.shop),
      ),
    );
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(
        context,
        l.productsTitle,
        actions: [
          IconButton(
            tooltip: l.catalogPickerTitle,
            onPressed: _openCatalogPicker,
            icon: const Icon(Icons.menu_book_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        icon: const Icon(Icons.add),
        label: Text(l.productsNewItemButton),
      ),
      body: SafeArea(
        child: Column(
          children: [
            ListSearchBar(
              controller: _searchController,
              hintText: l.productsSearchHint,
              onChanged: _onSearchChanged,
              onFilterTap: _openFilterSheet,
              filterCount: _filters.activeCount,
            ),
            ActiveFiltersBar(chips: [
              if (_filters.categoryId != null)
                ActiveFilterChip(
                  label: l.filterChipCategory(_filters.categoryName ?? ''),
                  onRemove: _clearCategory,
                ),
              if (_filters.lowStockOnly)
                ActiveFilterChip(
                  label: l.filterChipLowStock,
                  onRemove: _clearLowStock,
                ),
              if (_filters.noPriceOnly)
                ActiveFilterChip(
                  label: l.filterChipNoPrice,
                  onRemove: _clearNoPrice,
                ),
            ]),
            Expanded(
              child: FutureBuilder<List<ShopItemSummary>>(
                future: _resultsFuture,
                builder: (context, snapshot) {
                  // Capture newly-resolved data; subsequent rebuilds
                  // during a pending reload paint from `_lastKnown`.
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasData) {
                    _lastKnown = snapshot.data;
                  }
                  final loaded = _lastKnown ?? snapshot.data;
                  // Truly cold — no previous data + nothing landed
                  // yet. Show the spinner.
                  if (loaded == null) {
                    if (snapshot.hasError) {
                      // #372: append raw error so the next smoke
                      // test surfaces the actual server failure
                      // (e.g. "function does not exist" vs
                      // "permission denied" vs network timeout).
                      // Temporary debug aid — revert to friendly-
                      // only copy once root cause is identified.
                      return _ProductsErrorMessage(
                        message: '${l.productsLoadFailedMessage}\n'
                            '${snapshot.error}',
                        onRetry: _reload,
                      );
                    }
                    return const Center(child: CircularProgressIndicator());
                  }
                  // Client-side filtering for low-stock + no-price-only:
                  // server doesn't take these flags yet, and counts at
                  // small shop scale (≤ a few hundred) are cheap.
                  final results = loaded.where((r) {
                    if (_filters.lowStockOnly &&
                        !isLowStock(currentStock: r.currentStock)) {
                      return false;
                    }
                    if (_filters.noPriceOnly && r.anyPriceSet) return false;
                    return true;
                  }).toList(growable: false);
                  // Apply user-picked sort.
                  if (_sort == _ProductsSort.stockLowFirst) {
                    results.sort((a, b) {
                      // Low/zero stock floats first (lower current_stock
                      // first), then name alphabetical as tiebreaker.
                      final c = a.currentStock.compareTo(b.currentStock);
                      return c != 0 ? c : a.displayName.compareTo(b.displayName);
                    });
                  } else {
                    results.sort(
                        (a, b) => a.displayName.compareTo(b.displayName));
                  }
                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _HeadlineTile(rows: loaded),
                      ),
                      SliverToBoxAdapter(
                        child: _SortBar(
                          sort: _sort,
                          onChanged: (v) => setState(() => _sort = v),
                        ),
                      ),
                      if (results.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _activeQuery.isEmpty
                                    ? l.productsEmptyMessage
                                    : l.productsSearchEmptyMessage(_activeQuery),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          sliver: SliverList.separated(
                            itemCount: results.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final row = results[index];
                              return _ShopItemTile(
                                // #370: stable key so Flutter
                                // reconciles unchanged tiles in
                                // place instead of remounting all
                                // when the count changes.
                                key: ValueKey(row.shopItemId),
                                row: row,
                                shop: widget.shop,
                                onTap: () => _openDetail(row),
                              );
                            },
                          ),
                        ),
                    ],
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
  const _HeadlineTile({required this.rows});
  final List<ShopItemSummary> rows;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final total = rows.length;
    final lowCount = rows
        .where((r) => isLowStock(currentStock: r.currentStock))
        .length;
    final noPriceCount = rows.where((r) => !r.anyPriceSet).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.productsHeadline(total, lowCount, noPriceCount),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({required this.sort, required this.onChanged});
  final _ProductsSort sort;
  final ValueChanged<_ProductsSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      child: Row(
        children: [
          Text(
            l.productsSortLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<_ProductsSort>(
            value: sort,
            isDense: true,
            underline: const SizedBox.shrink(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            items: [
              DropdownMenuItem(
                value: _ProductsSort.name,
                child: Text(l.productsSortByName),
              ),
              DropdownMenuItem(
                value: _ProductsSort.stockLowFirst,
                child: Text(l.productsSortByStockLow),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShopItemTile extends StatelessWidget {
  const _ShopItemTile({
    super.key,
    required this.row,
    required this.shop,
    required this.onTap,
  });

  final ShopItemSummary row;
  final ShopSummary shop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final level = stockLevel(
      currentStock: row.currentStock,
      reorderThreshold: row.reorderThreshold,
    );
    final stockText = formatCompoundStock(
      stock: row.currentStock,
      baseLabel: row.baseUnitLabel,
      // Render in the default *receive* packaging when the shop has one
      // (the size they restock in), else base unit.
      packagingLabel: row.defaultReceivePackagingLabel,
      conversion: row.defaultReceiveConversion,
    );
    final subtitleBits = <Widget>[
      if (row.categoryName != null && row.categoryName!.trim().isNotEmpty)
        Text(row.categoryName!),
      // Primary price (or "no price yet") — drives the most common
      // "what does this cost again?" question from the row itself.
      if (row.defaultSalePrice != null)
        Text(
          '${formatMoney(row.defaultSalePrice!, shop)}/${row.baseUnitLabel}',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        )
      else
        Text(
          l.shopItemDetailNoPriceLabel,
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        minVerticalPadding: 14,
        onTap: onTap,
        title: Text(
          displayName(row.displayName),
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Wrap(
          spacing: 6,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < subtitleBits.length; i++) ...[
              subtitleBits[i],
              if (i < subtitleBits.length - 1)
                Text(
                  '·',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              stockText,
              style: theme.textTheme.titleMedium?.copyWith(
                color: stockLevelColor(context, level),
                fontWeight: level == StockLevel.healthy
                    ? FontWeight.w500
                    : FontWeight.w800,
              ),
            ),
            if (level != StockLevel.healthy)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: Icon(
                  Icons.warning_amber_outlined,
                  size: 18,
                  color: stockLevelColor(context, level),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductsErrorMessage extends StatelessWidget {
  const _ProductsErrorMessage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(l.tryAgain)),
          ],
        ),
      ),
    );
  }
}

