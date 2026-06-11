// Top movers report — Phase C of the products redesign.
//
// Two segments in one screen:
//   * Top sellers (by base-unit volume, period selectable)
//   * Dead stock (items with stock and zero sales in the period)
//
// Period is 7 / 30 / 90 days, selectable in the app bar.
//
// Tap a row → ShopItemDetailScreen.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/products/shop_item_detail_screen.dart';
import 'package:dukan/shared/display_name.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/quantity_format.dart';

class TopMoversScreen extends StatefulWidget {
  const TopMoversScreen({required this.shop, super.key});
  final ShopSummary shop;

  @override
  State<TopMoversScreen> createState() => _TopMoversScreenState();
}

class _TopMoversScreenState extends State<TopMoversScreen> {
  static const _periods = [7, 30, 90];
  int _periodDays = 7;
  String? _locale;
  Future<ProductVelocity>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = Localizations.localeOf(context).languageCode;
    if (_locale != current || _future == null) {
      _locale = current;
      _future = _load();
    }
  }

  Future<ProductVelocity> _load() {
    return context.read<ShopApi>().listProductVelocity(
          shopId: widget.shop.id,
          periodDays: _periodDays,
          limit: 20,
          locale: _locale,
        );
  }

  void _reload() => setState(() => _future = _load());

  void _setPeriod(int days) {
    if (days == _periodDays) return;
    setState(() {
      _periodDays = days;
      _future = _load();
    });
  }

  Future<void> _openDetail(String shopItemId, String name) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShopItemDetailScreen(
          shop: widget.shop,
          shopItemId: shopItemId,
          displayName: name,
        ),
      ),
    );
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.topMoversTitle),
            Text(
              l.topMoversPeriodSubtitle(_periodDays),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<int>(
            tooltip: l.topMoversPeriodTooltip,
            initialValue: _periodDays,
            onSelected: _setPeriod,
            itemBuilder: (ctx) => [
              for (final d in _periods)
                PopupMenuItem(
                  value: d,
                  child: Text(l.topMoversPeriodOption(d)),
                ),
            ],
            icon: const Icon(Icons.calendar_today_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<ProductVelocity>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    l.reportLoadFailedMessage,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final data = snapshot.data!;
            if (data.top.isEmpty && data.dead.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l.topMoversEmptyMessage,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                children: [
                  if (data.top.isNotEmpty) ...[
                    _SectionHeader(label: l.topMoversTopSegment),
                    for (final r in data.top)
                      _TopRow(
                        row: r,
                        shop: widget.shop,
                        onTap: () => _openDetail(r.shopItemId, r.displayName),
                      ),
                  ],
                  if (data.dead.isNotEmpty) ...[
                    _SectionHeader(label: l.topMoversDeadSegment),
                    for (final r in data.dead)
                      _DeadRow(
                        row: r,
                        onTap: () => _openDetail(r.shopItemId, r.displayName),
                      ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.row,
    required this.shop,
    required this.onTap,
  });
  final TopMoverRow row;
  final ShopSummary shop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      title: Text(
        displayName(row.displayName),
        style: theme.textTheme.titleMedium,
      ),
      subtitle: Text(
        '${formatQty(row.unitsSoldBase)} ${row.baseUnitLabel}'
        ' · ${row.salesCount} ×',
      ),
      trailing: Text(
        formatMoney(row.revenue, shop),
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DeadRow extends StatelessWidget {
  const _DeadRow({required this.row, required this.onTap});
  final DeadStockRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      title: Text(
        displayName(row.displayName),
        style: theme.textTheme.titleMedium,
      ),
      trailing: Text(
        '${formatQty(row.currentStock)} ${row.baseUnitLabel}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
