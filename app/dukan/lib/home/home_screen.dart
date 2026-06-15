import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/expense/expense_screen.dart';
import 'package:dukan/home/dukan_drawer.dart';
import 'package:dukan/payment/payment_screen.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/receive/receive_screen.dart';
import 'package:dukan/receive/supplier_picker_screen.dart';
import 'package:dukan/parties/customers_screen.dart';
import 'package:dukan/parties/suppliers_screen.dart';
import 'package:dukan/reports/low_stock_screen.dart';
import 'package:dukan/sale/sale_history_screen.dart';
import 'package:dukan/sale/sale_screen.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/favorites_cache.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/today_summary_cache.dart';
import 'package:dukan/observability/timing.dart';

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
    return Scaffold(
      drawer: shop != null ? DukanDrawer(shop: shop) : null,
      appBar: dukanAppBar(
        context,
        l.appTitle,
        actions: [
          if (widget.onSignOut != null)
            IconButton(
              tooltip: l.signOut,
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        // Single scrollable column — title, chip, summary, then action
        // grid stacked top-to-bottom with no forced bottom anchor.
        // Earlier layout used Expanded which created a visible empty
        // gap when the summary card was short. The new flow keeps
        // buttons within thumb reach on real devices because the
        // content above is always small.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.homeHint,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (shop != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: const Icon(Icons.storefront),
                    label: Text(l.activeShopLabel(shop.name)),
                  ),
                ),
                const SizedBox(height: 12),
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
                onPayment: () => _pushAndRefresh(
                  (_) {
                    Timing.startFlow('payment');
                    return PaymentScreen(shop: shop!);
                  },
                ),
                onExpense: () => _pushAndRefresh(
                  (_) {
                    Timing.startFlow('expense');
                    return ExpenseScreen(shop: shop!);
                  },
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
    required this.onPayment,
    required this.onExpense,
  });

  final ShopSummary? shop;
  final VoidCallback onSale;
  final VoidCallback onReceive;
  final VoidCallback onPayment;
  final VoidCallback onExpense;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    // 2x2 grid at a fixed cell height matching the previous design's
    // tap-target size. We don't enforce a parent height; the grid
    // sits at the natural end of the scroll column.
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
          icon: Icons.payments,
          label: l.payment,
          onTap: shop == null ? () {} : onPayment,
        ),
        HomeAction(
          icon: Icons.receipt_long,
          label: l.expense,
          onTap: shop == null ? () {} : onExpense,
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

  @override
  void initState() {
    super.initState();
    // First-frame on Home == end of cold start (auth bootstrap + shop
    // selection are done by the time _TodayCard mounts). No-op in
    // release builds — the entire Timing class is tree-shaken.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Timing.endFlow(context);
      _prefetchFavorites();
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
  Future<TodaySummary> _swrLoad() async {
    final cached = await TodaySummaryCache.get(widget.shop.id);
    // Fire-and-forget the fresh fetch. When it lands we replace
    // _future so the FutureBuilder rebuilds with the new values, and
    // persist for next mount.
    unawaited(_refreshFromNetwork());
    if (cached != null) return cached;
    // Cold cache — fall through to the network as the primary read.
    return _fetchFromNetwork();
  }

  Future<TodaySummary> _fetchFromNetwork() async {
    final summary = await context.read<ShopApi>().getTodaySummary(
          shopId: widget.shop.id,
          locale: _locale ?? 'en',
        );
    unawaited(TodaySummaryCache.put(widget.shop.id, summary));
    return summary;
  }

  Future<void> _refreshFromNetwork() async {
    try {
      final fresh = await context.read<ShopApi>().getTodaySummary(
            shopId: widget.shop.id,
            locale: _locale ?? 'en',
          );
      unawaited(TodaySummaryCache.put(widget.shop.id, fresh));
      if (!mounted) return;
      setState(() {
        _future = Future.value(fresh);
      });
    } catch (_) {
      // Background refresh failure leaves the cached value visible.
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
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: FutureBuilder<TodaySummary>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final s = snapshot.data;
          if (s == null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.reportLoadFailedMessage),
            );
          }
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
        },
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
