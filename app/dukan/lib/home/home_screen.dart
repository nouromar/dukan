import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/expense/expense_screen.dart';
import 'package:dukan/home/dukan_drawer.dart';
import 'package:dukan/payment/payment_controller.dart';
import 'package:dukan/payment/payment_screen.dart';
import 'package:dukan/products/products_screen.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/receive/receive_screen.dart';
import 'package:dukan/receive/supplier_picker_screen.dart';
import 'package:dukan/parties/customers_screen.dart';
import 'package:dukan/parties/suppliers_screen.dart';
import 'package:dukan/reports/low_stock_screen.dart';
import 'package:dukan/sale/sale_history_screen.dart';
import 'package:dukan/sale/sale_screen.dart';
import 'package:dukan/settings/language_sheet.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/favorites_cache.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/today_summary_cache.dart';
import 'package:dukan/observability/timing.dart';
import 'package:dukan/sync/cache_miss_boundary.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.shop, this.onSignOut});

  final ShopSummary? shop;
  final VoidCallback? onSignOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Ticker that _TodayCard listens to. Bumped after each action
  // navigation (Sale / Receive / Payment / Expense) returns, so the
  // summary card refreshes without the user having to leave the
  // screen.
  final ValueNotifier<int> _refreshTrigger = ValueNotifier<int>(0);

  @override
  void dispose() {
    _refreshTrigger.dispose();
    super.dispose();
  }

  /// Pushes the given page and bumps the refresh ticker on return.
  /// Use for the top-level action buttons whose flows mutate today's
  /// numbers. The card's own navigation (drill-into-history) keeps
  /// its existing inline reload — no double fetch.
  Future<void> _pushAndRefresh(WidgetBuilder builder) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: builder));
    if (mounted) _refreshTrigger.value = _refreshTrigger.value + 1;
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final shop = widget.shop;
    final scaffold = _buildScaffold(context, shop, l);
    if (shop == null) return scaffold;
    // #375: gate access to the home flow on first-time setup +
    // surface the sync-issue banner when sync is stuck. In light
    // mode this is a transparent pass-through.
    return CacheMissBoundary(shop: shop, child: scaffold);
  }

  Widget _buildScaffold(BuildContext context, ShopSummary? shop, l) {
    return Scaffold(
      drawer: shop != null
          ? DukanDrawer(shop: shop, onSignOut: widget.onSignOut)
          : null,
      // AppBar title carries the shop name when one is selected — the
      // shopkeeper opens the app to act on THIS shop, and "Dukan"
      // (the brand) is on the splash + Play Store. Falls back to the
      // brand when no shop is set yet (pre-setup state).
      appBar: dukanAppBar(
        context,
        shop?.name ?? l.appTitle,
        actions: [
          // Language picker — bottom sheet with English / Somali.
          // Logout moved to the drawer (Setup section) per UX
          // simplification — daily flows shouldn't display a
          // logout button in eyesight.
          IconButton(
            tooltip: l.languageEnglish,  // generic "language" hint
            onPressed: () => showLanguageSheet(context),
            icon: const Icon(Icons.language),
          ),
        ],
      ),
      body: SafeArea(
        // Single scrollable column. Used to render the homeHint title
        // ("Choose today's job") + a shop-name chip; both were dropped
        // because the four big action buttons below speak for
        // themselves, and the shop name now lives in the AppBar.
        // Saves ~80px above the fold so the Today summary + actions
        // sit comfortably within thumb reach.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (shop != null) ...[
                _TodayCard(
                  shop: shop,
                  refreshTrigger: _refreshTrigger,
                ),
              ],
              const SizedBox(height: 20),
              _ActionGrid(
                shop: shop,
                onSale: () => _pushAndRefresh(
                  (_) {
                    Timing.startFlow('sale');
                    return SaleScreen(shop: shop!);
                  },
                ),
                onReceive: () => _pushAndRefresh(
                  (_) {
                    final receive = context.read<ReceiveController>();
                    Timing.startFlow('receive');
                    // Resume a partial bono if one is in flight;
                    // otherwise start from the supplier picker.
                    return receive.isNotEmpty
                        ? ReceiveScreen(shop: shop!)
                        : SupplierPickerScreen(shop: shop!);
                  },
                ),
                onPaymentIn: () => _pushAndRefresh(
                  (_) {
                    Timing.startFlow('payment');
                    return PaymentScreen(
                      shop: shop!,
                      initialType: PaymentType.customer,
                    );
                  },
                ),
                onPaymentOut: () => _pushAndRefresh(
                  (_) {
                    Timing.startFlow('payment');
                    return PaymentScreen(
                      shop: shop!,
                      initialType: PaymentType.supplier,
                    );
                  },
                ),
                onExpense: () => _pushAndRefresh(
                  (_) {
                    Timing.startFlow('expense');
                    return ExpenseScreen(shop: shop!);
                  },
                ),
                onProducts: () => _pushAndRefresh(
                  (_) => ProductsScreen(shop: shop!),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.shop,
    required this.onSale,
    required this.onReceive,
    required this.onPaymentIn,
    required this.onPaymentOut,
    required this.onExpense,
    required this.onProducts,
  });

  final ShopSummary? shop;
  final VoidCallback onSale;
  final VoidCallback onReceive;
  final VoidCallback onPaymentIn;
  final VoidCallback onPaymentOut;
  final VoidCallback onExpense;
  final VoidCallback onProducts;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    // 2-column grid at a fixed cell height matching the original design's
    // tap-target size. Six tiles in a clean 3×2: Sale, Receive / Money In,
    // Money Out / Expense, Products. Payment was split into Money In
    // (customer pays) and Money Out (pay supplier) so the direction is chosen
    // by which tile you tap, not a question inside the screen (#2 feedback).
    return GridView(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        mainAxisExtent: 128,
      ),
      children: [
        HomeAction(
          icon: Icons.point_of_sale,
          label: l.sale,
          onTap: shop == null ? () {} : onSale,
        ),
        HomeAction(
          icon: Icons.inventory_2,
          label: l.receive,
          onTap: shop == null ? () {} : onReceive,
        ),
        HomeAction(
          icon: Icons.call_received,
          label: l.paymentInLabel,
          onTap: shop == null ? () {} : onPaymentIn,
        ),
        HomeAction(
          icon: Icons.call_made,
          label: l.paymentOutLabel,
          onTap: shop == null ? () {} : onPaymentOut,
        ),
        HomeAction(
          icon: Icons.receipt_long,
          label: l.expense,
          onTap: shop == null ? () {} : onExpense,
        ),
        // Products — same icon as the drawer (Icons.label_outline) so
        // muscle memory transfers between the two entry points.
        HomeAction(
          icon: Icons.label_outline,
          label: l.drawerProducts,
          onTap: shop == null ? () {} : onProducts,
        ),
      ],
    );
  }
}

class HomeAction extends StatelessWidget {
  const HomeAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 34),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Today summary card on Home — sales total + counters for receivables,
/// payables, and low-stock. Each counter row is tappable into the
/// corresponding report. Refreshes on revisit and when the parent
/// HomeScreen's refresh ticker is bumped (after an action returns).
class _TodayCard extends StatefulWidget {
  const _TodayCard({required this.shop, this.refreshTrigger});
  final ShopSummary shop;
  final ValueNotifier<int>? refreshTrigger;

  @override
  State<_TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<_TodayCard> with RouteAware {
  Future<TodaySummary>? _future;
  String? _locale;
  // #370: hold the last successfully-resolved summary so that
  // explicit reloads (return-from-subscreen, refresh-trigger bump)
  // don't transition the FutureBuilder through its spinner branch.
  // Spinner now only fires on the truly-cold path where nothing was
  // ever rendered.
  TodaySummary? _lastKnown;

  @override
  void initState() {
    super.initState();
    // First-frame on Home == end of cold start (auth bootstrap + shop
    // selection are done by the time _TodayCard mounts). No-op in
    // release builds — the entire Timing class is tree-shaken.
    //
    // Favorites prefetch is deliberately NOT fired here — it lives
    // inside _swrLoad so it runs AFTER the today summary lands. The
    // summary RPC is the user's wait; firing two extra search_items
    // calls alongside it just steals the first network slot.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Timing.endFlow(context);
    });
    widget.refreshTrigger?.addListener(_onRefreshTrigger);
  }

  @override
  void didUpdateWidget(covariant _TodayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) {
      oldWidget.refreshTrigger?.removeListener(_onRefreshTrigger);
      widget.refreshTrigger?.addListener(_onRefreshTrigger);
    }
  }

  @override
  void dispose() {
    widget.refreshTrigger?.removeListener(_onRefreshTrigger);
    super.dispose();
  }

  void _onRefreshTrigger() {
    if (!mounted) return;
    _reload();
  }

  void _prefetchFavorites() {
    final api = context.read<ShopApi>();
    final locale = Localizations.localeOf(context).languageCode;
    for (final screen in const ['sale', 'receive']) {
      if (!FavoritesCache.isStale(widget.shop.id, screen)) continue;
      unawaited(
        api
            .searchItems(
              shopId: widget.shop.id,
              query: '',
              screen: screen,
              locale: locale,
            )
            .then((results) {
          FavoritesCache.put(widget.shop.id, screen, results);
        }).catchError((Object _, StackTrace _) {
          // Swallow: prefetch is best-effort.
        }),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = Localizations.localeOf(context).languageCode;
    if (_locale != current || _future == null) {
      _locale = current;
      _future = _swrLoad();
    }
  }

  /// Stale-while-revalidate: resolves the persisted cache for instant
  /// render, then fires the network fetch and persists the fresh
  /// summary. The FutureBuilder receives whichever lands first — in
  /// practice the cached value lands within a frame and the network
  /// value updates the persisted cache for the next mount.
  ///
  /// Favorites prefetch (sale + receive search seeds) is fired only
  /// AFTER the summary lands so it doesn't compete with the summary
  /// RPC for the first network slot. On a warm cache the cached
  /// value returns instantly and the prefetch can ride along with
  /// the background refresh.
  Future<TodaySummary> _swrLoad() async {
    final cached = await TodaySummaryCache.get(widget.shop.id);
    if (cached != null) {
      // Warm cache — render immediately. Background refresh +
      // favorites prefetch fire concurrently; neither blocks the user.
      unawaited(_refreshFromNetwork());
      _prefetchFavorites();
      return cached;
    }
    // Cold cache — the summary RPC IS the user's wait. Fire favorites
    // prefetch only after it lands. (Previously this path also fired
    // a redundant _refreshFromNetwork in parallel with _fetchFromNetwork
    // for the same data; the duplicate is gone with this rewrite.)
    final summary = await _fetchFromNetwork();
    _prefetchFavorites();
    return summary;
  }

  Future<TodaySummary> _fetchFromNetwork() async {
    final summary = await context.read<ShopApi>().getTodaySummary(
          shopId: widget.shop.id,
          locale: _locale ?? 'en',
        );
    // ConfigResolver from the provider tree feeds the per-shop /
    // per-org TTL override (Phase 3 / `cache_ttl_today_summary_s`).
    // Falls back to a 1h default when no override is set.
    final resolver = _readResolverOrNull();
    unawaited(TodaySummaryCache.put(widget.shop.id, summary, resolver: resolver));
    return summary;
  }

  Future<void> _refreshFromNetwork() async {
    try {
      final fresh = await context.read<ShopApi>().getTodaySummary(
            shopId: widget.shop.id,
            locale: _locale ?? 'en',
          );
      final resolver = _readResolverOrNull();
      unawaited(TodaySummaryCache.put(widget.shop.id, fresh, resolver: resolver));
      if (!mounted) return;
      setState(() {
        _future = Future.value(fresh);
      });
    } catch (_) {
      // Background refresh failure leaves the cached value visible.
    }
  }

  /// Returns the ConfigResolver from the provider tree, or null if it
  /// isn't wired (widget tests that skip AuthBootstrap). The cache
  /// gracefully falls back to its hard-coded TTL when null.
  ConfigResolver? _readResolverOrNull() {
    try {
      return context.read<ConfigResolver>();
    } catch (_) {
      return null;
    }
  }

  void _reload() {
    setState(() {
      _future = _fetchFromNetwork();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Card(
      margin: EdgeInsets.zero,
      child: FutureBuilder<TodaySummary>(
        future: _future,
        builder: (context, snapshot) {
          // Capture newly-resolved data so future rebuilds during
          // pending reloads can paint from `_lastKnown`.
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasData) {
            _lastKnown = snapshot.data;
          }
          // Prefer the most recent known value. Skips the spinner
          // on explicit reloads — the existing values stay painted
          // until the new ones land.
          final s = _lastKnown ?? snapshot.data;
          if (s != null) {
            return _renderSummary(context, s);
          }
          // Truly cold — nothing ever rendered. Show spinner
          // while the first fetch is in flight.
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          // Resolved with no data — empty / error state.
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l.reportLoadFailedMessage),
          );
        },
      ),
    );
  }

  Widget _renderSummary(BuildContext context, TodaySummary s) {
    final l = tr(context);
    final theme = Theme.of(context);
    return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.homeTodayHeader,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                InkWell(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SaleHistoryScreen(shop: widget.shop),
                      ),
                    );
                    if (mounted) _reload();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l.homeSalesTodayLabel,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        Text(
                          formatMoney(s.salesToday, widget.shop),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 12),
                _CounterRow(
                  label: l.homeReceivablesLabel,
                  amount: formatMoney(s.receivablesTotal, widget.shop),
                  highlight: s.receivablesTotal > 0,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CustomersScreen(
                          shop: widget.shop,
                          // Land already scoped to who-owes-you so
                          // the user sees exactly what they tapped.
                          initialHasBalanceOnly: true,
                        ),
                      ),
                    );
                    if (mounted) _reload();
                  },
                ),
                _CounterRow(
                  label: l.homePayablesLabel,
                  amount: formatMoney(s.payablesTotal, widget.shop),
                  highlight: s.payablesTotal > 0,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SuppliersScreen(
                          shop: widget.shop,
                          initialHasBalanceOnly: true,
                        ),
                      ),
                    );
                    if (mounted) _reload();
                  },
                ),
                _CounterRow(
                  label: l.homeLowStockLabel,
                  amount: l.homeLowStockCount(s.lowStockCount),
                  highlight: s.lowStockCount > 0,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LowStockScreen(shop: widget.shop),
                      ),
                    );
                    if (mounted) _reload();
                  },
                ),
              ],
            ),
          );
  }
}

class _CounterRow extends StatelessWidget {
  const _CounterRow({
    required this.label,
    required this.amount,
    required this.highlight,
    required this.onTap,
  });

  final String label;
  final String amount;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
            Text(
              amount,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: highlight ? theme.colorScheme.error : null,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
