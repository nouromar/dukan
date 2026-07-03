import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/shared/void_action.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/receive/receive_detail_screen.dart';
import 'package:dukan/sale/sale_detail_screen.dart';
import 'package:dukan/shared/client_op_id.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/history_date.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

/// Read-only detail for a single payment — opened from the party detail or
/// payment history. Shows the direction (Money In/Out), party, amount, date,
/// method and notes, then the sales/receives it settled (each tap-through).
class PaymentDetailScreen extends StatefulWidget {
  const PaymentDetailScreen({
    required this.shop,
    required this.paymentId,
    super.key,
  });

  final ShopSummary shop;
  final String paymentId;

  @override
  State<PaymentDetailScreen> createState() => _PaymentDetailScreenState();
}

class _PaymentBundle {
  const _PaymentBundle({
    required this.header,
    required this.allocations,
    this.sourceTxnId,
  });
  final PaymentDetail header;
  final List<PostedAllocation> allocations;

  /// For a settlement leg: the originating sale/receive txn id (resolved
  /// locally), so the detail can link back to it. Null otherwise.
  final String? sourceTxnId;
}

class _PaymentDetailScreenState extends State<PaymentDetailScreen> {
  late Future<_PaymentBundle> _future;
  bool _voiding = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// True when the VOID button should show: owner capability, not already
  /// voided, not a refund/​at-till leg, and within the per-shop window. Mirrors
  /// the server guards in void_payment (the server re-enforces regardless).
  bool _canVoid(BuildContext context, PaymentDetail h) {
    if (h.isVoided || h.isRefund || h.isSettlementLeg) return false;
    if (DateTime.now().difference(h.createdAt) >=
        widget.shop.voidSettings.paymentWindow) {
      return false;
    }
    return context.watch<AuthController>().capabilities.canVoidPayment;
  }

  /// The window expired on a payment that is otherwise structurally voidable —
  /// show a small disabled hint instead of silently hiding the affordance.
  bool _windowPassed(PaymentDetail h) {
    if (h.isVoided || h.isRefund || h.isSettlementLeg) return false;
    return DateTime.now().difference(h.createdAt) >=
        widget.shop.voidSettings.paymentWindow;
  }

  Future<void> _confirmAndVoid(PaymentDetail h) async {
    final l = tr(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.paymentVoidConfirmTitle),
        content: Text(l.paymentVoidConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cartClearConfirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.paymentVoidConfirmYes),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _voiding = true);
    final api = context.read<ShopApi>();
    final opId = generateClientOpId('void_payment');
    try {
      await voidWithQueueFallback(
        context: context,
        shopId: widget.shop.id,
        optimisticTxnId: h.paymentId,
        rpc: 'void_payment',
        params: buildVoidPaymentParams(paymentId: h.paymentId),
        clientOpId: opId,
        direct: () => api.voidPayment(
          shopId: widget.shop.id,
          paymentId: h.paymentId,
          clientOpId: opId,
        ),
        onDone: () {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.paymentVoidedToast)));
          Navigator.of(context).pop(true);
        },
        onFailure: (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'dukan payment',
              context: ErrorDescription('void_payment'),
            ),
          );
          if (mounted) showError(context, l.paymentVoidFailedMessage);
        },
      );
    } finally {
      if (mounted) setState(() => _voiding = false);
    }
  }

  Future<_PaymentBundle> _load() async {
    // Read providers up front (before any await) so the network fallback
    // doesn't touch `context` across an async gap.
    final api = context.read<ShopApi>();
    // Offline-first (mirrors sale/receive detail): read the header from
    // the local mirror so the screen opens in airplane mode. Allocations
    // aren't mirrored, so the "Settled" section shows its empty state
    // offline; the next online open backfills it.
    if (useLocalDb(context)) {
      final repo = context.read<LocalRepository>();
      final local = await repo.getPaymentDetailLocal(widget.paymentId);
      if (local != null) {
        // A settlement leg links back to its sale/receive instead of listing
        // allocations (it has none). Resolve the source txn from the mirror.
        final sourceTxnId = local.isSettlementLeg
            ? await repo.settlementLegSourceTxnId(local.clientOpId)
            : null;
        return _PaymentBundle(
          header: local,
          allocations: const [],
          sourceTxnId: sourceTxnId,
        );
      }
      // Not in the mirror — fall through to the network as a last resort.
    }
    final header = await api.getPayment(
      shopId: widget.shop.id,
      paymentId: widget.paymentId,
    );
    if (header == null) {
      throw StateError('payment ${widget.paymentId} not found');
    }
    final allocations = await api.listPaymentAllocations(
      shopId: widget.shop.id,
      paymentId: widget.paymentId,
    );
    return _PaymentBundle(header: header, allocations: allocations);
  }

  Future<void> _openTxn(PostedAllocation a) async {
    await _openSource(a.transactionId, a.txnType == 'sale');
  }

  Future<void> _openSource(String txnId, bool isSale) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => isSale
            ? SaleDetailScreen(shop: widget.shop, txnId: txnId)
            : ReceiveDetailScreen(shop: widget.shop, txnId: txnId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.paymentTitle),
      body: SafeArea(
        child: FutureBuilder<_PaymentBundle>(
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
                    l.paymentDetailLoadFailedMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              );
            }
            return _PaymentBody(
              shop: widget.shop,
              bundle: snapshot.data!,
              onOpenTxn: _openTxn,
              onOpenSource: _openSource,
              voiding: _voiding,
              canVoid: _canVoid(context, snapshot.data!.header),
              windowPassed: _windowPassed(snapshot.data!.header),
              onVoid: () => _confirmAndVoid(snapshot.data!.header),
            );
          },
        ),
      ),
    );
  }
}

class _PaymentBody extends StatelessWidget {
  const _PaymentBody({
    required this.shop,
    required this.bundle,
    required this.onOpenTxn,
    required this.onOpenSource,
    required this.voiding,
    required this.canVoid,
    required this.windowPassed,
    required this.onVoid,
  });

  final ShopSummary shop;
  final _PaymentBundle bundle;
  final Future<void> Function(PostedAllocation) onOpenTxn;
  final Future<void> Function(String txnId, bool isSale) onOpenSource;
  final bool voiding;
  final bool canVoid;
  final bool windowPassed;
  final VoidCallback onVoid;

  String _methodLabel(String code) =>
      code.isEmpty ? code : code[0].toUpperCase() + code.substring(1);

  /// The "what this payment was for" section — four mutually exclusive shapes:
  ///   1. Settlement leg → "From a cash sale / stock receive" (+ link to it).
  ///   2. Allocations loaded (online) → the "Paid for" invoice list.
  ///   3. Party payment, allocations not mirrored (offline) → a plain, always-
  ///      true effect line ("Lowered X's debt by …") — never a false "not
  ///      linked yet" message.
  ///   4. Nothing concrete to show → the section is omitted entirely.
  List<Widget> _settledSection(
    BuildContext context,
    L10n l,
    ThemeData theme,
    PaymentDetail header,
    bool isIn,
  ) {
    // 1. Till-cash leg of a walk-in sale/receive.
    if (header.isSettlementLeg) {
      return [
        const SizedBox(height: 24),
        Text(
          isIn ? l.paymentFromSaleHeader : l.paymentFromReceiveHeader,
          style: theme.textTheme.titleMedium,
        ),
        if (bundle.sourceTxnId != null) ...[
          const SizedBox(height: 4),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            dense: true,
            onTap: () => onOpenSource(bundle.sourceTxnId!, isIn),
            leading: Icon(
              isIn ? Icons.point_of_sale : Icons.local_shipping,
              size: 20,
            ),
            title: Text(
              '${isIn ? l.saleDetailTitle : l.receiveDetailTitle}'
              ' · ${formatHistoryStamp(context, header.occurredAt)}',
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ];
    }

    // 2. Real allocations loaded — the itemized "Paid for" list.
    if (bundle.allocations.isNotEmpty) {
      return [
        const SizedBox(height: 24),
        Text(l.paymentDetailSettledHeader, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final a in bundle.allocations)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            dense: true,
            onTap: () => onOpenTxn(a),
            leading: Icon(
              a.txnType == 'sale'
                  ? Icons.point_of_sale
                  : Icons.local_shipping,
              size: 20,
            ),
            title: Text(
              '${a.txnType == 'sale' ? l.saleDetailTitle : l.receiveDetailTitle}'
              ' · ${formatHistoryStamp(context, a.occurredAt)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatMoney(a.amount, shop),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
      ];
    }

    // 3. Party payment whose allocations aren't mirrored — plain effect line.
    if (header.partyName != null) {
      final money = formatMoney(header.amount, shop);
      return [
        const SizedBox(height: 24),
        Text(
          isIn
              ? l.paymentEffectIn(header.partyName!, money)
              : l.paymentEffectOut(header.partyName!, money),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ];
    }

    // 4. Nothing concrete to show.
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final header = bundle.header;
    final isIn = header.direction == 'I';
    // Same direction accent as the Money In / Money Out screen.
    final accent = isIn ? Colors.green.shade700 : Colors.orange.shade800;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (header.isVoided) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              l.paymentVoidedHeader,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: accent.withValues(alpha: 0.18),
                child: Icon(
                  isIn ? Icons.call_received : Icons.call_made,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isIn ? l.paymentInLabel : l.paymentOutLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                    if (header.partyName != null)
                      Text(header.partyName!, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
              Text(
                formatMoney(header.amount, shop),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  decoration: header.isVoided
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          formatHistoryStamp(context, header.occurredAt),
          style: theme.textTheme.titleMedium,
        ),
        if (header.paymentMethodCode != null) ...[
          const SizedBox(height: 4),
          Text(
            _methodLabel(header.paymentMethodCode!),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (header.notes != null && header.notes!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(header.notes!.trim(), style: theme.textTheme.bodyMedium),
        ],
        ..._settledSection(context, l, theme, header, isIn),
        if (canVoid) ...[
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: voiding ? null : onVoid,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
            child: voiding
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.paymentDetailVoidButton),
          ),
        ] else if (windowPassed) ...[
          const SizedBox(height: 24),
          Center(
            child: Text(
              l.paymentVoidWindowPassedHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
