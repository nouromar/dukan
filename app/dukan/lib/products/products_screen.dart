import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _searchController = TextEditingController();
  late Future<List<ItemSearchResult>> _resultsFuture;
  String _activeQuery = '';
  Timer? _debounce;
  final Set<String> _adding = {};
  bool _loadFailed = false;

  String? _locale;

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
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<ItemSearchResult>> _fetch(String query) async {
    try {
      final results = await context.read<ShopApi>().searchItems(
        shopId: widget.shop.id,
        query: query,
        locale: Localizations.localeOf(context).languageCode,
      );
      if (mounted && _loadFailed) {
        setState(() => _loadFailed = false);
      }
      return results;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan products',
          context: ErrorDescription('searching items'),
        ),
      );
      if (mounted) setState(() => _loadFailed = true);
      rethrow;
    }
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

  Future<void> _activate(ItemSearchResult candidate) async {
    final catalogItemId = candidate.catalogItemId;
    if (catalogItemId == null) return;
    setState(() => _adding.add(catalogItemId));
    final l = tr(context);
    try {
      await context.read<ShopApi>().ensureShopItem(
        shopId: widget.shop.id,
        catalogItemId: catalogItemId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.productsAddedToShopToast(candidate.name))),
      );
      setState(() {
        _resultsFuture = _fetch(_activeQuery);
      });
    } on PostgrestException {
      if (mounted) {
        showError(context, l.productsAddToShopFailedMessage(candidate.name));
      }
    } finally {
      if (mounted) {
        setState(() => _adding.remove(catalogItemId));
      }
    }
  }

  void _onTapNewItem() {
    showError(context, tr(context).productsNewItemUnavailable);
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.productsTitle),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l.productsSearchHint,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<ItemSearchResult>>(
                future: _resultsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _ProductsErrorMessage(
                      message: l.productsLoadFailedMessage,
                      onRetry: () => setState(() {
                        _resultsFuture = _fetch(_activeQuery);
                      }),
                    );
                  }
                  final results = snapshot.data ?? const <ItemSearchResult>[];
                  if (results.isEmpty) {
                    return _ProductsEmptyMessage(
                      message: _activeQuery.isEmpty
                          ? l.productsEmptyMessage
                          : l.productsSearchEmptyMessage(_activeQuery),
                    );
                  }
                  return _ProductsList(
                    results: results,
                    adding: _adding,
                    onAdd: _activate,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: OutlinedButton(
                onPressed: _onTapNewItem,
                child: Text(l.productsNewItemButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductsList extends StatelessWidget {
  const _ProductsList({
    required this.results,
    required this.adding,
    required this.onAdd,
  });

  final List<ItemSearchResult> results;
  final Set<String> adding;
  final ValueChanged<ItemSearchResult> onAdd;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final activated = results.where((r) => r.isActivated).toList(growable: false);
    final catalog = results.where((r) => !r.isActivated).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      children: [
        if (activated.isNotEmpty) ...[
          _ProductsSectionHeader(label: l.productsInYourShop),
          for (final item in activated) _ActivatedItemTile(item: item),
          const SizedBox(height: 16),
        ],
        if (catalog.isNotEmpty) ...[
          _ProductsSectionHeader(label: l.productsFromCatalog),
          for (final item in catalog)
            _CatalogCandidateTile(
              item: item,
              adding: adding.contains(item.catalogItemId),
              onAdd: () => onAdd(item),
            ),
        ],
      ],
    );
  }
}

class _ProductsSectionHeader extends StatelessWidget {
  const _ProductsSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ActivatedItemTile extends StatelessWidget {
  const _ActivatedItemTile({required this.item});

  final ItemSearchResult item;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final stock = item.currentStock;
    final stockText = (stock == null || stock <= 0)
        ? l.productsNoStock
        : l.productsStockLabel(_trimNumber(stock), item.baseUnitLabel);
    return Card(
      child: ListTile(
        minVerticalPadding: 16,
        title: Text(
          item.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(stockText),
        trailing: item.salePrice == null
            ? null
            : Text(
                _formatPrice(item.salePrice!),
                style: Theme.of(context).textTheme.titleMedium,
              ),
      ),
    );
  }
}

class _CatalogCandidateTile extends StatelessWidget {
  const _CatalogCandidateTile({
    required this.item,
    required this.adding,
    required this.onAdd,
  });

  final ItemSearchResult item;
  final bool adding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Card(
      child: ListTile(
        minVerticalPadding: 16,
        title: Text(
          item.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: item.salePrice == null
            ? null
            : Text(_formatPrice(item.salePrice!)),
        trailing: adding
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : FilledButton.tonal(
                onPressed: onAdd,
                child: Text(l.productsAddToShopButton),
              ),
      ),
    );
  }
}

class _ProductsEmptyMessage extends StatelessWidget {
  const _ProductsEmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
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

String _trimNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String _formatPrice(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}
