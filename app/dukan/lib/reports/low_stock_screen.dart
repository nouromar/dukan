// Low-stock report — items with stock below their reorder threshold
// (or below 1 if no threshold set). Pinned search bar narrows by
// product name (client-side filter).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/products/shop_item_detail_screen.dart';
import 'package:dukan/shared/display_name.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/list_filter_bar.dart';
import 'package:dukan/shared/stock_format.dart';

class LowStockScreen extends StatefulWidget {
  const LowStockScreen({required this.shop, super.key});
  final ShopSummary shop;

  @override
  State<LowStockScreen> createState() => _LowStockScreenState();
}

class _LowStockScreenState extends State<LowStockScreen> {
  Future<List<LowStockRow>>? _future;
  String? _locale;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context).languageCode;
    if (_locale != locale || _future == null) {
      _locale = locale;
      _future = _load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<LowStockRow>> _load() {
    // Offline-first: compute from the local mirror (current_stock +
    // reorder_threshold are mirrored) so the report opens in airplane mode.
    if (useLocalDb(context)) {
      return context.read<LocalRepository>().lowStockLocal(widget.shop.id);
    }
    return context
        .read<ShopApi>()
        .listLowStock(shopId: widget.shop.id, locale: _locale ?? 'en');
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value.trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.lowStockReportTitle),
      body: SafeArea(
        child: Column(
          children: [
            ListSearchBar(
              controller: _searchController,
              hintText: l.lowStockSearchHint,
              onChanged: _onSearchChanged,
            ),
            Expanded(
              child: FutureBuilder<List<LowStockRow>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l.reportLoadFailedMessage,
                            textAlign: TextAlign.center),
                      ),
                    );
                  }
                  final all = snapshot.data ?? const <LowStockRow>[];
                  final rows = _query.isEmpty
                      ? all
                      : all
                          .where((r) =>
                              r.displayName.toLowerCase().contains(_query))
                          .toList(growable: false);
                  if (rows.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l.lowStockReportEmptyMessage,
                            textAlign: TextAlign.center),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(() => _future = _load());
                    },
                    child: ListView.separated(
                      padding:
                          const EdgeInsets.symmetric(vertical: 8),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        final stockText = formatCompoundStock(
                          stock: row.currentStock,
                          baseLabel: row.baseUnitLabel,
                        );
                        return ListTile(
                          title: Text(
                            displayName(row.displayName),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            stockText,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ShopItemDetailScreen(
                                  shop: widget.shop,
                                  shopItemId: row.shopItemId,
                                ),
                              ),
                            );
                          },
                        );
                      },
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
