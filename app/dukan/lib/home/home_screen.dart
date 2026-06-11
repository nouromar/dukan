import 'dart:async';
import 'dart:math' as math;

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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.shop, this.onSignOut});

  final ShopSummary? shop;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      drawer: shop != null ? DukanDrawer(shop: shop!) : null,
      appBar: dukanAppBar(
        context,
        l.appTitle,
        actions: [
          if (onSignOut != null)
            IconButton(
              tooltip: l.signOut,
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Action grid stays anchored at the bottom (primary tap
              // surface). Tighter than before so the Today summary card
              // above can render without clipping its last row.
              final buttonAreaHeight = math.min(
                280.0,
                constraints.maxHeight * 0.45,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
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
                                label: Text(l.activeShopLabel(shop!.name)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _TodayCard(shop: shop!),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: buttonAreaHeight,
                    child: GridView(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        // Compute cell height from the budget so 2 rows
                        // always fit regardless of viewport width.
                        mainAxisExtent: (buttonAreaHeight - 14) / 2,
                      ),
                      children: [
                        HomeAction(
                          icon: Icons.point_of_sale,
                          label: l.sale,
                          onTap: shop == null
                              ? () {}
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SaleScreen(shop: shop!),
                                  ),
                                ),
                        ),
                        HomeAction(
                          icon: Icons.inventory_2,
                          label: l.receive,
                          onTap: shop == null
                              ? () {}
                              : () {
                                  final receive =
                                      context.read<ReceiveController>();
                                  // Resume a partial bono if one is in
                                  // flight; otherwise start from the
                                  // supplier picker. Supplier alone is
                                  // not enough to count as "in flight"
                                  // — we resume only when actual lines
                                  // exist, so an aborted picker visit
                                  // doesn't pin us to a stale supplier.
                                  final destination = receive.isNotEmpty
                                      ? ReceiveScreen(shop: shop!)
                                      : SupplierPickerScreen(shop: shop!);
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => destination,
                                    ),
                                  );
                                },
                        ),
                        HomeAction(
                          icon: Icons.payments,
                          label: l.payment,
                          onTap: shop == null
                              ? () {}
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PaymentScreen(shop: shop!),
                                  ),
                                ),
                        ),
                        HomeAction(
                          icon: Icons.receipt_long,
                          label: l.expense,
                          onTap: shop == null
                              ? () {}
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ExpenseScreen(shop: shop!),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
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
/// corresponding report. Refreshes on revisit.
class _TodayCard extends StatefulWidget {
  const _TodayCard({required this.shop});
  final ShopSummary shop;

  @override
  State<_TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<_TodayCard> with RouteAware {
  Future<TodaySummary>? _future;
  String? _locale;

  @override
  void initState() {
    super.initState();
    // While the cashier is looking at Home, warm the favorites cache
    // in the background so Sale/Receive entry feels instant. Fire and
    // forget — the cache is best-effort; any failure leaves the
    // entry empty and the screen falls back to its own fetch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prefetchFavorites();
    });
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
      _future = context.read<ShopApi>().getTodaySummary(
            shopId: widget.shop.id,
            locale: current,
          );
    }
  }

  void _reload() {
    setState(() {
      _future = context.read<ShopApi>().getTodaySummary(
            shopId: widget.shop.id,
            locale: _locale ?? 'en',
          );
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
