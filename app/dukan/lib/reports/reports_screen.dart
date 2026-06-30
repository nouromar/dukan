import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/reports/low_stock_screen.dart';
import 'package:dukan/sale/sale_history_screen.dart';
import 'package:dukan/shared/date_range.dart';
import 'package:dukan/shared/date_range_sheet.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';

/// Simple at-a-glance reports (#7): Sales, Profit, Stock over a chosen period.
/// Glanceable cards (big numbers, tap-to-drill) — not dense tables; the formal
/// P&L / cash-flow lives in the shop-admin portal.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // This month is the sensible default for a shopkeeper glancing at totals.
  DateRange _range = DateRange.month();
  late Future<_ReportBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ReportBundle> _load() async {
    final api = context.read<ShopApi>();
    final results = await Future.wait([
      api.getProfitReport(
        shopId: widget.shop.id,
        from: _range.from,
        to: _range.to,
      ),
      api.getStockReport(shopId: widget.shop.id),
    ]);
    return _ReportBundle(
      profit: results[0] as ProfitReport,
      stock: results[1] as StockReport,
    );
  }

  Future<void> _pickRange() async {
    final next = await showDateRangeSheet(context, current: _range);
    if (next == null || !mounted) return;
    setState(() {
      _range = next;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.reportsTitle),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: ActionChip(
                  avatar: const Icon(Icons.calendar_today, size: 18),
                  label: Text(dateRangeLabel(context, _range)),
                  onPressed: _pickRange,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<_ReportBundle>(
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
                          l.reportsLoadFailedMessage,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final b = snapshot.data!;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _salesCard(l, b.profit),
                      const SizedBox(height: 12),
                      _profitCard(l, b.profit),
                      const SizedBox(height: 12),
                      _stockCard(l, b.stock),
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

  Widget _salesCard(L10n l, ProfitReport p) {
    final shop = widget.shop;
    final num avg = p.saleCount > 0 ? p.revenue / p.saleCount : 0;
    return _ReportCard(
      icon: Icons.point_of_sale,
      title: l.reportsSalesTitle,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SaleHistoryScreen(shop: shop)),
      ),
      rows: [
        _Metric(l.reportsRevenueLabel, formatMoney(p.revenue, shop),
            emphasize: true),
        _Metric(l.reportsSalesCountLabel, '${p.saleCount}'),
        _Metric(l.reportsAvgSaleLabel, formatMoney(avg, shop)),
      ],
    );
  }

  Widget _profitCard(L10n l, ProfitReport p) {
    final shop = widget.shop;
    return _ReportCard(
      icon: Icons.trending_up,
      title: l.reportsProfitTitle,
      rows: [
        _Metric(l.reportsCostLabel, formatMoney(p.cogs, shop)),
        // Each profit line carries its own margin % as a faint suffix — gross
        // margin (markup health) on gross, net margin (bottom line) on net.
        _Metric(l.reportsGrossProfitLabel, formatMoney(p.grossProfit, shop),
            emphasize: true,
            suffix: '${p.grossMarginPct.toStringAsFixed(0)}%'),
        _Metric(l.reportsExpensesLabel, formatMoney(p.expenseTotal, shop)),
        _Metric(l.reportsNetProfitLabel, formatMoney(p.netProfit, shop),
            emphasize: true,
            suffix: '${p.marginPct.toStringAsFixed(0)}%'),
      ],
    );
  }

  Widget _stockCard(L10n l, StockReport s) {
    final shop = widget.shop;
    return _ReportCard(
      icon: Icons.inventory_2,
      title: l.reportsStockTitle,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LowStockScreen(shop: shop)),
      ),
      rows: [
        _Metric(l.reportsItemsLabel, '${s.itemCount}'),
        _Metric(l.reportsStockValueLabel, formatMoney(s.stockValue, shop),
            emphasize: true),
        _Metric(l.reportsLowStockLabel, '${s.lowStockCount}'),
      ],
    );
  }
}

class _ReportBundle {
  _ReportBundle({required this.profit, required this.stock});
  final ProfitReport profit;
  final StockReport stock;
}

class _Metric {
  _Metric(this.label, this.value, {this.emphasize = false, this.suffix});
  final String label;
  final String value;
  final bool emphasize;

  /// Optional faint trailing text (e.g. a margin %) shown after the value.
  final String? suffix;
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.icon,
    required this.title,
    required this.rows,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final List<_Metric> rows;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(title, style: theme.textTheme.titleMedium),
                  const Spacer(),
                  if (onTap != null)
                    Icon(Icons.chevron_right,
                        color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 8),
              for (final m in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        m.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        textBaseline: TextBaseline.alphabetic,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        children: [
                          Text(
                            m.value,
                            style: m.emphasize
                                ? theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)
                                : theme.textTheme.bodyLarge,
                          ),
                          if (m.suffix != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              m.suffix!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
