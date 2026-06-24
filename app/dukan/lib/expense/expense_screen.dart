// Expense entry — one of the four daily flows. Cashier picks a
// category chip, types the amount, hits SAVE. v1 hardcodes the
// payment method to 'cash'; categories come from the shop's
// configured expense_category table (seeded by the template,
// editable in the future admin portal).
//
// The system numeric keypad replaces the previous custom on-screen
// keypad from the prototype (which overflowed on smaller phones).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/expense/expense_controller.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/shared/client_op_id.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/optimistic_save.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
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
    _notesController.dispose();
    super.dispose();
  }

  Future<List<ExpenseCategoryOption>> _fetchCategories() async {
    // #374: when offline_mode = full, categories come from the
    // local mirror (synced by SyncEngine). Light mode keeps the
    // existing live RPC path.
    if (useLocalDb(context)) {
      final repo = context.read<LocalRepository>();
      final rows = await repo.expenseCategories(shopId: widget.shop.id);
      return rows.map(repo.toExpenseCategoryOption).toList(growable: false);
    }
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

    final api = context.read<ShopApi>();
    final categoryId = category.id;
    final amount = controller.amount;
    final clientOpId = generateClientOpId('expense');
    final rawNotes = _notesController.text.trim();
    final notes = rawNotes.isEmpty ? null : rawNotes;

    // #383: when useLocalDb=false, post directly to the server and
    // surface success/failure inline — no queue, no optimistic
    // clear. See docs/offline-first-architecture.md.
    if (!useLocalDb(context)) {
      await _saveDirect(
        api: api,
        controller: controller,
        categoryId: categoryId,
        amount: amount,
        clientOpId: clientOpId,
        notes: notes,
        failureMessage: l.expensePostFailedMessage,
        savedToast: l.expenseSavedToast,
      );
      return;
    }

    final queue = context.read<OfflineQueueController>();
    // Capture cashier id before pop; #367 stamps onto the queued post.
    String actorId = '';
    try {
      actorId = Supabase.instance.client.auth.currentUser?.id ?? '';
    } catch (_) {
      actorId = '';
    }

    final messenger = runOptimisticSaveShell(
      context: context,
      savedToast: l.expenseSavedToast,
      onClear: () {
        controller.clearAll();
        _amountController.clear();
        _notesController.clear();
      },
    );

    unawaited(
      _postExpenseInBackground(
        api: api,
        queue: queue,
        shopId: widget.shop.id,
        actorId: actorId,
        categoryId: categoryId,
        amount: amount,
        clientOpId: clientOpId,
        notes: notes,
        messenger: messenger,
        failureMessage: l.expensePostFailedMessage,
      ),
    );
  }

  /// #383: direct-post path for useLocalDb=false. Awaits the
  /// server response; on success clears the form + pops; on
  /// failure shows the error and keeps form state so the cashier
  /// can retry.
  Future<void> _saveDirect({
    required ShopApi api,
    required ExpenseController controller,
    required String categoryId,
    required num amount,
    required String clientOpId,
    required String? notes,
    required String failureMessage,
    required String savedToast,
  }) async {
    try {
      await api.postExpense(
        shopId: widget.shop.id,
        expenseCategoryId: categoryId,
        amount: amount,
        paymentMethodCode: 'cash',
        clientOpId: clientOpId,
        notes: notes,
      );
      if (!mounted) return;
      controller.clearAll();
      _amountController.clear();
      _notesController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(savedToast)),
      );
      Navigator.of(context).maybePop();
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan expense',
        context: ErrorDescription('post_expense (useLocalDb=false)'),
      ));
      if (!mounted) return;
      showError(context, '$failureMessage\n$error');
    }
  }

  Future<void> _postExpenseInBackground({
    required ShopApi api,
    required OfflineQueueController queue,
    required String shopId,
    required String actorId,
    required String categoryId,
    required num amount,
    required String clientOpId,
    required String? notes,
    required ScaffoldMessengerState messenger,
    required String failureMessage,
  }) async {
    try {
      await api.postExpense(
        shopId: shopId,
        expenseCategoryId: categoryId,
        amount: amount,
        paymentMethodCode: 'cash',
        clientOpId: clientOpId,
        notes: notes,
      );
    } on PostgrestException catch (error, stackTrace) {
      // Server-side reject — retry won't help. Toast.
      reportBackgroundFailure(
        error: error,
        stackTrace: stackTrace,
        messenger: messenger,
        library: 'dukan expense',
        context: 'post_expense',
        failureMessage: failureMessage,
      );
    } catch (error, stackTrace) {
      // Transient — enqueue. Queue badge signals pending work; no
      // toast since the screen popped already.
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan expense',
        context: ErrorDescription('post_expense (queuing for retry)'),
      ));
      final post = PendingPost(
        id: generateClientOpId('expense'),
        clientOpId: clientOpId,
        shopId: shopId,
        originalActorUserId: actorId,
        rpc: 'post_expense',
        params: buildPostExpenseParams(
          expenseCategoryId: categoryId,
          amount: amount,
          paymentMethodCode: 'cash',
          notes: notes,
        ),
        queuedAt: DateTime.now(),
      );
      await queue.enqueue(post);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final controller = context.watch<ExpenseController>();
    final theme = Theme.of(context);
    final canSave = controller.category != null && controller.amount > 0;
    return Scaffold(
      appBar: dukanAppBar(context, l.expenseTitle),
      // #379: SAVE moved to `bottomNavigationBar` so it floats
      // above the soft keyboard. Body is unchanged otherwise —
      // Expanded categories area shrinks naturally when the
      // keyboard takes screen space.
      body: SafeArea(
        bottom: false,
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
                      // #372: append raw error to surface actual
                      // server failure during smoke testing.
                      // Temporary — revert to friendly-only once
                      // root cause is identified.
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '${l.expenseLoadFailedMessage}\n'
                                '${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
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
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                textInputAction: TextInputAction.done,
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: l.expenseNotesLabel,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: canSave ? _save : null,
              child: Text(l.expenseSaveButton),
            ),
          ),
        ),
      ),
    );
  }
}
