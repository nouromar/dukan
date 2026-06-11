// Catalog picker — browse the global catalog and batch-activate items
// into this shop. data-model-v2 §11.10.
//
// We rely on `searchItems(screen: 'sale')` because it already returns
// BOTH activated and unactivated rows (each carries `isActivated`). The
// list renders all rows; activated rows are visually greyed with the
// `catalogPickerActivatedBadge` and have their checkbox disabled so the
// cashier can't try to re-add them. Selecting one or more unactivated
// rows reveals a bottom action bar that runs `ensureShopItem` in
// parallel for the selection.
//
// Layout follows data-model-v2 §11.10 sketch:
//   - Flat list ordered by `search_items` relevance (no category grouping
//     in v1; grouping is a v2 polish item once we observe real usage).
//   - 250 ms debounce on the search field, mirroring sale_screen.dart so
//     the picker feels identical to the cashier.
//   - Bottom action bar surfaces only when ≥ 1 row is selected.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

class CatalogPickerScreen extends StatefulWidget {
  const CatalogPickerScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<CatalogPickerScreen> createState() => _CatalogPickerScreenState();
}

class _CatalogPickerScreenState extends State<CatalogPickerScreen> {
  final _searchController = TextEditingController();
  late Future<List<ItemSearchResult>> _resultsFuture;
  String _activeQuery = '';
  Timer? _debounce;
  String? _locale;
  bool _saving = false;

  /// Keyed by `itemId` (the global catalog row). Unactivated rows always
  /// carry a non-null `itemId`; that's what `ensureShopItem` needs.
  final Map<String, ItemSearchResult> _selected = {};

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

  Future<List<ItemSearchResult>> _fetch(String query) {
    return context.read<ShopApi>().searchItems(
      shopId: widget.shop.id,
      query: query,
      screen: 'sale',
      locale: Localizations.localeOf(context).languageCode,
    );
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

  void _toggleSelection(ItemSearchResult item) {
    final id = item.itemId;
    if (id == null) return;
    setState(() {
      if (_selected.containsKey(id)) {
        _selected.remove(id);
      } else {
        _selected[id] = item;
      }
    });
  }

  Future<void> _addSelected() async {
    if (_selected.isEmpty || _saving) return;
    setState(() => _saving = true);
    final l = tr(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final api = context.read<ShopApi>();
    final selected = _selected.values.toList(growable: false);
    try {
      await Future.wait(
        selected.map(
          (item) => api.ensureShopItem(
            shopId: widget.shop.id,
            itemId: item.itemId!,
          ),
        ),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l.catalogPickerAddedToast(selected.length))),
      );
      navigator.pop();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan catalog picker',
          context: ErrorDescription('ensure_shop_item batch'),
        ),
      );
      if (mounted) {
        showError(context, l.productsLoadFailedMessage);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.catalogPickerTitle),
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
                  hintText: l.catalogPickerSearchHint,
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
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l.productsLoadFailedMessage,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    );
                  }
                  final results =
                      snapshot.data ?? const <ItemSearchResult>[];
                  // Unactivated rows that lack a global itemId can't be
                  // activated by ensureShopItem; hide them defensively so
                  // the cashier never sees an un-tickable row that isn't
                  // already-added.
                  final visible = results
                      .where((r) => r.isActivated || r.itemId != null)
                      .toList(growable: false);
                  if (visible.isEmpty) {
                    return Center(
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
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      final isSelected = item.itemId != null &&
                          _selected.containsKey(item.itemId);
                      return _CatalogRow(
                        item: item,
                        selected: isSelected,
                        enabled: !_saving,
                        onToggle: () => _toggleSelection(item),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _saving ? null : _addSelected,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child:
                                CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Text(l.catalogPickerAddButton(_selected.length)),
                  ),
                ),
              ),
            ),
    );
  }
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.item,
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });

  final ItemSearchResult item;
  final bool selected;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final activated = item.isActivated;
    final disabled = !enabled || activated;
    final subtitleText = item.packagingLabel ?? item.baseUnitLabel;
    return Card(
      margin: EdgeInsets.zero,
      color: activated
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surface,
      child: InkWell(
        onTap: disabled ? null : onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: activated
                            ? theme.colorScheme.onSurface
                                .withValues(alpha: 0.5)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: activated ? 0.45 : 0.7),
                      ),
                    ),
                    if (activated) ...[
                      const SizedBox(height: 4),
                      Text(
                        l.catalogPickerActivatedBadge,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: Checkbox(
                  value: activated ? true : selected,
                  onChanged: disabled
                      ? null
                      : (_) => onToggle(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
