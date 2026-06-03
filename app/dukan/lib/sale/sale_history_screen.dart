// Sale history — reverse-chronological list of past sales for the
// current shop. Reached via the history icon in the Sale screen's
// app bar. Tap a row → detail screen with the receipt + VOID action.
//
// v1 shows the last `_pageLimit` sales (no infinite scroll yet);
// pilot shops won't go deep enough on day one to need pagination
// chrome. The list_sales RPC already supports the `before` cursor
// so adding "load more" later is mechanical.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/sale/sale_detail_screen.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';

class SaleHistoryScreen extends StatefulWidget {
  const SaleHistoryScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<SaleHistoryScreen> createState() => _SaleHistoryScreenState();
}

class _SaleHistoryScreenState extends State<SaleHistoryScreen> {
  static const int _pageLimit = 50;
  late Future<List<SaleSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<SaleSummary>> _fetch() {
    return context.read<ShopApi>().listSales(
      shopId: widget.shop.id,
      limit: _pageLimit,
    );
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
    // If the detail screen voided the sale, refresh the list so the
    // ⓥ badge shows.
    if (didChange == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.saleHistoryTitle),
      body: SafeArea(
        child: FutureBuilder<List<SaleSummary>>(
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
                    l.saleHistoryLoadFailedMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              );
            }
            final sales = snapshot.data ?? const <SaleSummary>[];
            if (sales.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    l.saleHistoryEmptyMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sales.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _SaleRow(
                shop: widget.shop,
                sale: sales[i],
                onTap: () => _openDetail(sales[i]),
              ),
            );
          },
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
    final subtitle = sale.partyName != null
        ? l.saleHistoryDebtLabel(sale.partyName!)
        : l.saleHistoryCashLabel;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _formatTime(sale.occurredAt),
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

String _formatTime(DateTime dt) {
  final local = dt.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
