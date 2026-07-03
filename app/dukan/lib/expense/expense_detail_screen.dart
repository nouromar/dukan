import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/shared/void_action.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/shared/client_op_id.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/history_date.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

/// Read-only expense detail with an owner-only VOID. Opened from the expense
/// history. Mirrors the sale/receive detail void flow: a direct `void_expense`
/// RPC (not queued), gated by the `expense.void` capability and the per-shop
/// window. Pops `true` after a void so the history can refresh.
class ExpenseDetailScreen extends StatefulWidget {
  const ExpenseDetailScreen({
    required this.shop,
    required this.txnId,
    super.key,
  });

  final ShopSummary shop;
  final String txnId;

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  late Future<ExpenseSummary> _future;
  String? _locale;
  bool _voiding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Localizations is only available here, not in initState.
    final current = Localizations.localeOf(context).languageCode;
    if (_locale != current) {
      _locale = current;
      _future = _load();
    }
  }

  Future<ExpenseSummary> _load() async {
    // Read the provider up front (before any await) so the network fallback
    // doesn't touch `context` across an async gap.
    final api = context.read<ShopApi>();
    // Offline-first (mirrors sale/receive/payment detail): read from the
    // local mirror so the screen opens in airplane mode.
    if (useLocalDb(context)) {
      final repo = context.read<LocalRepository>();
      final local = await repo.getExpenseDetailLocal(widget.txnId);
      if (local != null) return local;
      // Not in the mirror — fall through to the network as a last resort.
    }
    final expense = await api.getExpense(
      shopId: widget.shop.id,
      txnId: widget.txnId,
      locale: _locale,
    );
    if (expense == null) {
      throw StateError('expense ${widget.txnId} not found');
    }
    return expense;
  }

  bool _canVoid(BuildContext context, ExpenseSummary e) {
    if (e.isVoided) return false;
    if (DateTime.now().difference(e.postedAt) >=
        widget.shop.voidSettings.expenseWindow) {
      return false;
    }
    return context.watch<AuthController>().capabilities.canVoidExpense;
  }

  Future<void> _confirmAndVoid(ExpenseSummary e) async {
    final l = tr(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.expenseVoidConfirmTitle),
        content: Text(l.expenseVoidConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cartClearConfirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.expenseVoidConfirmYes),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _voiding = true);
    final api = context.read<ShopApi>();
    final opId = generateClientOpId('void_expense');
    try {
      await voidWithQueueFallback(
        context: context,
        shopId: widget.shop.id,
        optimisticTxnId: e.txnId,
        rpc: 'void_expense',
        params: buildVoidExpenseParams(txnId: e.txnId),
        clientOpId: opId,
        direct: () => api.voidExpense(
          shopId: widget.shop.id,
          txnId: e.txnId,
          clientOpId: opId,
        ),
        onDone: () {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.expenseVoidedToast)));
          Navigator.of(context).pop(true);
        },
        onFailure: (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'dukan expense',
              context: ErrorDescription('void_expense'),
            ),
          );
          if (mounted) showError(context, l.expenseVoidFailedMessage);
        },
      );
    } finally {
      if (mounted) setState(() => _voiding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.expenseDetailTitle),
      body: SafeArea(
        child: FutureBuilder<ExpenseSummary>(
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
                    l.expenseDetailLoadFailedMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              );
            }
            return _Body(
              shop: widget.shop,
              expense: snapshot.data!,
              voiding: _voiding,
              canVoid: _canVoid(context, snapshot.data!),
              onVoid: () => _confirmAndVoid(snapshot.data!),
            );
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.shop,
    required this.expense,
    required this.voiding,
    required this.canVoid,
    required this.onVoid,
  });

  final ShopSummary shop;
  final ExpenseSummary expense;
  final bool voiding;
  final bool canVoid;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (expense.isVoided)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                l.saleDetailVoidedHeader,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          if (expense.isVoided) const SizedBox(height: 12),
          Text(
            formatHistoryStamp(context, expense.occurredAt),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  expense.categoryName ?? l.expenseDetailTitle,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              Text(
                formatMoney(expense.amount, shop),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  decoration: expense.isVoided
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ],
          ),
          if (expense.paymentMethodCode != null) ...[
            const SizedBox(height: 4),
            Text(
              _methodLabel(expense.paymentMethodCode!),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (expense.notes != null && expense.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(expense.notes!.trim(), style: theme.textTheme.bodyMedium),
          ],
          const Spacer(),
          if (canVoid)
            // Destructive secondary action: muted grey text, right-aligned,
            // no fill. Deliberately low-key — findable but far from a primary
            // CTA. The confirm dialog carries the warning. Mirrors sale/receive.
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: voiding ? null : onVoid,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
                child: voiding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.expenseDetailVoidButton),
              ),
            ),
        ],
      ),
    );
  }

  String _methodLabel(String code) =>
      code.isEmpty ? code : code[0].toUpperCase() + code.substring(1);
}
