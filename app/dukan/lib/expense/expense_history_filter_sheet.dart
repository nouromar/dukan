// Expense-history filter sheet. Two controls:
//   * Date range (Today / 7d / Month / All / Custom)
//   * Category (any / pick from the shop's expense_category list)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/shared/date_range.dart';
import 'package:dukan/shared/date_range_sheet.dart';
import 'package:dukan/shared/l10n.dart';

class ExpenseHistoryFilters {
  const ExpenseHistoryFilters({
    required this.dateRange,
    this.categoryId,
    this.categoryName,
  });

  // Default to All (like sales / receives / payments). Expenses are
  // infrequent, so a "today" default almost always shows an empty page.
  factory ExpenseHistoryFilters.initial() =>
      const ExpenseHistoryFilters(dateRange: DateRange.all);

  final DateRange dateRange;
  final String? categoryId;
  final String? categoryName;

  ExpenseHistoryFilters copyWith({
    DateRange? dateRange,
    String? categoryId,
    String? categoryName,
    bool clearCategory = false,
  }) {
    return ExpenseHistoryFilters(
      dateRange: dateRange ?? this.dateRange,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      categoryName:
          clearCategory ? null : (categoryName ?? this.categoryName),
    );
  }

  int get activeBeyondDate => (categoryId != null ? 1 : 0);
}

Future<ExpenseHistoryFilters?> showExpenseHistoryFilterSheet(
  BuildContext context, {
  required ShopSummary shop,
  required ExpenseHistoryFilters current,
}) {
  return showModalBottomSheet<ExpenseHistoryFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _Body(shop: shop, initial: current),
  );
}

class _Body extends StatefulWidget {
  const _Body({required this.shop, required this.initial});
  final ShopSummary shop;
  final ExpenseHistoryFilters initial;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late ExpenseHistoryFilters _draft;
  Future<List<ExpenseCategoryOption>>? _categoriesFuture;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _categoriesFuture ??= context.read<ShopApi>().listExpenseCategories(
          shopId: widget.shop.id,
          locale: Localizations.localeOf(context).languageCode,
        );
  }

  Future<void> _pickDate() async {
    final next = await showDateRangeSheet(context, current: _draft.dateRange);
    if (next != null && mounted) {
      setState(() => _draft = _draft.copyWith(dateRange: next));
    }
  }

  Future<void> _pickCategory() async {
    final categories = await _categoriesFuture!;
    if (!mounted) return;
    final picked = await showModalBottomSheet<ExpenseCategoryOption?>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final l = tr(sheetCtx);
        return SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(
                  l.filterCategoryAny,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
                onTap: () => Navigator.of(sheetCtx).pop(null),
              ),
              const Divider(height: 1),
              for (final c in categories)
                ListTile(
                  title: Text(c.name),
                  trailing: c.id == _draft.categoryId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(sheetCtx).pop(c),
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
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(dateRangeLabel(context, _draft.dateRange)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDate,
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
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop(ExpenseHistoryFilters.initial()),
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
