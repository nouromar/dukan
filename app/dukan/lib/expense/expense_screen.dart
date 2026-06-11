// Expense entry — one of the four daily flows. Cashier picks a
// category chip, types the amount, hits SAVE. v1 hardcodes the
// payment method to 'cash'; categories come from the shop's
// configured expense_category table (seeded by the template,
// editable in the future admin portal).
//
// The system numeric keypad replaces the previous custom on-screen
// keypad from the prototype (which overflowed on smaller phones).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/expense/expense_controller.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  final _amountController = TextEditingController();
  final _random = math.Random();
  late Future<List<ExpenseCategoryOption>> _categoriesFuture;
  String? _locale;

  @override
  void initState() {
    super.initState();
    final amount = context.read<ExpenseController>().amount;
    if (amount > 0) {
      _amountController.text = _formatField(amount);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = Localizations.localeOf(context).languageCode;
    if (_locale != current) {
      _locale = current;
      _categoriesFuture = _fetchCategories();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<List<ExpenseCategoryOption>> _fetchCategories() {
    return context.read<ShopApi>().listExpenseCategories(
      shopId: widget.shop.id,
      locale: Localizations.localeOf(context).languageCode,
    );
  }

  String _formatField(num value) {
    if (value == value.toDouble().roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  void _onPickCategory(ExpenseCategoryOption category) {
    context.read<ExpenseController>().setCategory(category);
  }

  void _onAmountChanged(String value) {
    final parsed = num.tryParse(value.trim()) ?? 0;
    context.read<ExpenseController>().setAmount(parsed);
  }

  Future<void> _save() async {
    final l = tr(context);
    final controller = context.read<ExpenseController>();
    final category = controller.category;
    if (category == null) {
      showError(context, l.expenseNeedCategoryMessage);
      return;
    }
    if (controller.amount <= 0) {
      showError(context, l.expenseNeedAmountMessage);
      return;
    }

    // Optimistic SAVE per CLAUDE.md's speed contract. Snapshot the
    // typed state + messenger reference before clearing so a rare
    // post-pop failure can surface a top-level error toast.
    final api = context.read<ShopApi>();
    final messenger = ScaffoldMessenger.of(context);
    final categoryId = category.id;
    final amount = controller.amount;
    final clientOpId = _generateClientOpId();
    final failureMessage = l.expensePostFailedMessage;

    controller.clearAll();
    _amountController.clear();
    messenger.showSnackBar(SnackBar(content: Text(l.expenseSavedToast)));
    Navigator.of(context).maybePop();

    unawaited(
      _postExpenseInBackground(
        api: api,
        categoryId: categoryId,
        amount: amount,
        clientOpId: clientOpId,
        messenger: messenger,
        failureMessage: failureMessage,
      ),
    );
  }

  Future<void> _postExpenseInBackground({
    required ShopApi api,
    required String categoryId,
    required num amount,
    required String clientOpId,
    required ScaffoldMessengerState messenger,
    required String failureMessage,
  }) async {
    try {
      await api.postExpense(
        shopId: widget.shop.id,
        expenseCategoryId: categoryId,
        amount: amount,
        paymentMethodCode: 'cash',
        clientOpId: clientOpId,
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan expense',
          context: ErrorDescription('post_expense'),
        ),
      );
      messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  String _generateClientOpId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = _random.nextInt(1 << 32);
    return 'expense-$ts-$r';
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final controller = context.watch<ExpenseController>();
    final theme = Theme.of(context);
    final canSave = controller.category != null && controller.amount > 0;
    return Scaffold(
      appBar: dukanAppBar(context, l.expenseTitle),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.expenseCategoryLabel, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<ExpenseCategoryOption>>(
                  future: _categoriesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          l.expenseLoadFailedMessage,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                      );
                    }
                    final cats =
                        snapshot.data ?? const <ExpenseCategoryOption>[];
                    if (cats.isEmpty) {
                      return Center(
                        child: Text(
                          l.expenseEmptyMessage,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                      );
                    }
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: cats
                          .map(
                            (cat) => ChoiceChip(
                              label: Text(cat.name),
                              selected: controller.category?.id == cat.id,
                              onSelected: (_) => _onPickCategory(cat),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              labelStyle: theme.textTheme.titleMedium,
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: _onAmountChanged,
                style: theme.textTheme.headlineSmall,
                decoration: InputDecoration(
                  labelText:
                      '${widget.shop.currencySymbol} ${l.expenseAmountLabel}',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canSave ? _save : null,
                  child: Text(l.expenseSaveButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
