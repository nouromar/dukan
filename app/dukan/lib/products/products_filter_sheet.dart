// Products filter sheet — two controls applied client-side over the
// loaded shop_item list:
//
//   * Category (picked from list_categories, "All" by default)
//   * Low stock only — show only items below threshold / negative
//
// "No price yet" was scoped out for v1 — the ShopItemSummary DTO
// doesn't carry packaging prices, so honouring it would need a
// per-row fetch (or a backend column). Add when we extend the RPC.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/shared/l10n.dart';

class ProductsFilters {
  const ProductsFilters({
    this.categoryId,
    this.categoryName,
    this.lowStockOnly = false,
    this.noPriceOnly = false,
  });

  factory ProductsFilters.initial() => const ProductsFilters();

  final String? categoryId;
  final String? categoryName;
  final bool lowStockOnly;
  final bool noPriceOnly;

  ProductsFilters copyWith({
    String? categoryId,
    String? categoryName,
    bool clearCategory = false,
    bool? lowStockOnly,
    bool? noPriceOnly,
  }) {
    return ProductsFilters(
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      categoryName:
          clearCategory ? null : (categoryName ?? this.categoryName),
      lowStockOnly: lowStockOnly ?? this.lowStockOnly,
      noPriceOnly: noPriceOnly ?? this.noPriceOnly,
    );
  }

  int get activeCount =>
      (categoryId != null ? 1 : 0) +
      (lowStockOnly ? 1 : 0) +
      (noPriceOnly ? 1 : 0);
}

Future<ProductsFilters?> showProductsFilterSheet(
  BuildContext context, {
  required ProductsFilters current,
  required String shopId,
}) {
  return showModalBottomSheet<ProductsFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) =>
        _ProductsFilterSheetBody(initial: current, shopId: shopId),
  );
}

class _ProductsFilterSheetBody extends StatefulWidget {
  const _ProductsFilterSheetBody({required this.initial, required this.shopId});
  final ProductsFilters initial;
  final String shopId;

  @override
  State<_ProductsFilterSheetBody> createState() =>
      _ProductsFilterSheetBodyState();
}

class _ProductsFilterSheetBodyState extends State<_ProductsFilterSheetBody> {
  late ProductsFilters _draft;
  Future<List<CategoryOption>>? _categoriesFuture;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _categoriesFuture ??= context.read<ShopApi>().listCategories(
          locale: Localizations.localeOf(context).languageCode,
          shopId: widget.shopId,
        );
  }

  Future<void> _pickCategory() async {
    final categories = await _categoriesFuture!;
    if (!mounted) return;
    final picked = await showModalBottomSheet<CategoryOption?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final l = tr(sheetContext);
        return SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(l.filterCategoryAny,
                    style:
                        const TextStyle(fontStyle: FontStyle.italic)),
                onTap: () => Navigator.of(sheetContext).pop(null),
              ),
              const Divider(height: 1),
              for (final c in categories)
                ListTile(
                  title: Text(c.name),
                  trailing: c.id == _draft.categoryId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(c),
                ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (picked == null) {
      setState(() => _draft = _draft.copyWith(clearCategory: true));
    } else {
      setState(() => _draft = _draft.copyWith(
            categoryId: picked.id,
            categoryName: picked.name,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l.filterSheetTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: Text(_draft.categoryName ?? l.filterCategoryAny),
              trailing: _draft.categoryId != null
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() =>
                          _draft = _draft.copyWith(clearCategory: true)),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _pickCategory,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.warning_amber_outlined),
              title: Text(l.filterLowStockOnly),
              value: _draft.lowStockOnly,
              onChanged: (v) =>
                  setState(() => _draft = _draft.copyWith(lowStockOnly: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.price_change_outlined),
              title: Text(l.filterNoPriceOnly),
              value: _draft.noPriceOnly,
              onChanged: (v) =>
                  setState(() => _draft = _draft.copyWith(noPriceOnly: v)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop(ProductsFilters.initial()),
                    child: Text(l.filterResetButton),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_draft),
                    child: Text(l.filterApplyButton),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
