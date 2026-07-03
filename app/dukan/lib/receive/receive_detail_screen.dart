// Bono (receive) detail — receipt-style view for one past bono.
// Owner sees a VOID action when the bono is within the 24-hour window
// (same-shift correction, narrower than the sale's 7-day window) and
// no item from the bono has had subsequent stock activity. The
// backend enforces both guards; this screen only mirrors them so the
// button is hidden when we already know voiding will be refused.
//
// Pops back with `true` after a successful void so the history list
// refreshes the strikethrough + voided badge.
//
// v2 model: each line carries a `packagingLabel` snapshot from the
// transaction line (e.g., "25 kg bag"). The receipt reads that
// snapshot rather than the live shop_item_unit so it stays consistent
// even if the packaging was later renamed or had its conversion
// changed.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/shared/void_action.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

class ReceiveDetailScreen extends StatefulWidget {
  const ReceiveDetailScreen({
    required this.shop,
    required this.txnId,
    super.key,
  });

  final ShopSummary shop;
  final String txnId;

  @override
  State<ReceiveDetailScreen> createState() => _ReceiveDetailScreenState();
}

class _ReceiveDetailScreenState extends State<ReceiveDetailScreen> {
  final _random = math.Random();
  late Future<_ReceiveBundle> _future;
  bool _voiding = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ReceiveBundle> _load() async {
    // Capture context-derived dependencies up front so the rest of
    // the method is await-safe (no use_build_context_synchronously).
    final api = context.read<ShopApi>();
    final useLocal = useLocalDb(context);
    LocalRepository? localRepo;
    if (useLocal) {
      try {
        localRepo = context.read<LocalRepository>();
      } catch (_) {
        localRepo = null;
      }
    }
    // #385-fixup: in useLocalDb=on mode, the history shows optimistic
    // rows whose txn_id = client_op_id (placeholder per #385). The
    // server has no record with that ID, so a direct api.getReceive
    // would return null and throw → empty page. Mirror what
    // sale_detail_screen.dart did in #385: try the local mirror first,
    // fall through to network as last resort.
    if (localRepo != null) {
      try {
        final localTxn = await localRepo.getTransaction(widget.txnId);
        if (localTxn != null) {
          final lines = await localRepo.receiveLinesFromLocal(widget.txnId);
          return _ReceiveBundle(
            header: localRepo.toReceiveSummary(localTxn),
            lines: lines,
          );
        }
      } catch (_) {
        // Local probe failure shouldn't sink the page — fall through.
      }
      // No local row yet — fall through to network as last resort
      // (covers the newly-arrived-from-realtime case before the
      // delta sync has filled the mirror).
    }
    final header = await api.getReceive(
      shopId: widget.shop.id,
      txnId: widget.txnId,
    );
    if (header == null) {
      throw StateError('Bono not found');
    }
    final lines = await api.getReceiveLines(
      shopId: widget.shop.id,
      txnId: widget.txnId,
    );
    return _ReceiveBundle(header: header, lines: lines);
  }

  Future<void> _confirmAndVoid(ReceiveSummary header) async {
    final l = tr(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _VoidConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _voiding = true);
    final api = context.read<ShopApi>();
    final opId = _generateClientOpId();
    try {
      await voidWithQueueFallback(
        context: context,
        shopId: widget.shop.id,
        optimisticTxnId: header.txnId,
        rpc: 'void_receive',
        params: buildVoidReceiveParams(txnId: header.txnId),
        clientOpId: opId,
        direct: () => api.voidReceive(
          shopId: widget.shop.id,
          txnId: header.txnId,
          clientOpId: opId,
        ),
        onDone: () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.receiveVoidedToast)),
          );
          Navigator.of(context).pop(true);
        },
        onFailure: _handleVoidFailure,
      );
    } finally {
      if (mounted) setState(() => _voiding = false);
    }
  }

  void _handleVoidFailure(Object error, StackTrace stackTrace) {
    final l = tr(context);
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan receive',
        context: ErrorDescription('void_receive'),
      ),
    );
    if (!mounted) return;
    // Map the server's business-rule guards to friendly Somali/EN lines so
    // the cashier knows what to do instead. Any other error (network, timing
    // window) falls back to the generic message.
    final raw = error.toString();
    final String message;
    if (raw.contains('stock activity')) {
      message = l.receiveVoidBlockedStockMessage;
    } else if (raw.contains('paid down')) {
      // Partial-paid payable guard (0085): the shop already paid part of this
      // bono, so a full reversal would drive the supplier balance negative.
      message = l.receiveVoidBlockedPaidMessage;
    } else {
      message = l.receiveVoidFailedMessage;
    }
    showError(context, message);
  }

  String _generateClientOpId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = _random.nextInt(1 << 32);
    return 'void-recv-$ts-$r';
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.receiveDetailTitle),
      body: SafeArea(
        child: FutureBuilder<_ReceiveBundle>(
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
                    l.receiveDetailLoadFailedMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              );
            }
            return _ReceiveDetailBody(
              shop: widget.shop,
              bundle: snapshot.data!,
              voiding: _voiding,
              onVoid: () => _confirmAndVoid(snapshot.data!.header),
            );
          },
        ),
      ),
    );
  }
}

class _ReceiveBundle {
  const _ReceiveBundle({required this.header, required this.lines});
  final ReceiveSummary header;
  final List<ReceiveLineDetail> lines;
}

class _ReceiveDetailBody extends StatelessWidget {
  const _ReceiveDetailBody({
    required this.shop,
    required this.bundle,
    required this.voiding,
    required this.onVoid,
  });

  final ShopSummary shop;
  final _ReceiveBundle bundle;
  final bool voiding;
  final VoidCallback onVoid;

  /// Same-shift window: 24 h from posted_at. Tighter than sale's 7
  /// days because real returns belong in v1.1 Returns, not in this
  /// typo-correction tool. Also gated by `canVoidReceive` — the
  /// cashier role lacks that capability and would otherwise tap a
  /// button only to hit the backend's owner-only check.
  bool _canVoid(BuildContext context) {
    if (bundle.header.isVoided) return false;
    final posted = bundle.header.postedAt;
    if (posted == null) return false;
    if (DateTime.now().difference(posted) >= shop.voidSettings.receiveWindow) {
      return false;
    }
    return context.watch<AuthController>().capabilities.canVoidReceive;
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final header = bundle.header;
    final supplierName = header.partyName ?? '—';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header.isVoided)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                l.receiveDetailVoidedHeader,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          if (header.isVoided) const SizedBox(height: 12),
          Text(
            _formatDateTime(header.occurredAt),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            l.receiveHistorySupplierLabel(supplierName),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          const Divider(),
          Expanded(
            child: ListView.separated(
              itemCount: bundle.lines.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final line = bundle.lines[i];
                final unitCostText = line.unitAmount == null
                    ? '—'
                    : formatMoney(line.unitAmount!, shop);
                final qtyText = line.quantity == line.quantity.roundToDouble()
                    ? line.quantity.toInt().toString()
                    : line.quantity.toString();
                // The v2 packaging snapshot lives on the line as
                // `packagingLabel` (e.g., "25 kg bag"). Fall back to
                // the bare unit label for legacy/expense rows that
                // don't carry a packaging.
                final unitText = line.packagingLabel ?? line.unitLabel;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(
                    line.itemName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    // Gen signature is alphabetical:
                    // (quantity, subtotal, unit, unitCost).
                    l.receiveDetailLineSubtotal(
                      qtyText,
                      formatMoney(line.lineTotal, shop),
                      unitText,
                      unitCostText,
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(),
          _amountRow(
            theme,
            l.receiveDetailTotalLabel,
            formatMoney(header.totalAmount, shop),
            bold: true,
          ),
          const SizedBox(height: 8),
          if (_canVoid(context))
            // Destructive secondary action: muted grey text, right-aligned,
            // no fill. Mirrors the sale-detail layout (also low-key now) so
            // cashiers see the same pattern across both history surfaces.
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
                    : Text(l.receiveDetailVoidButton),
              ),
            ),
        ],
      ),
    );
  }

  Widget _amountRow(
    ThemeData theme,
    String label,
    String value, {
    bool bold = false,
  }) {
    final style =
        (bold ? theme.textTheme.titleLarge : theme.textTheme.bodyLarge)
            ?.copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _VoidConfirmDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.receiveVoidConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.receiveVoidConfirmBody),
          const SizedBox(height: 12),
          // Explicit "mistakes only" copy so cashiers don't reach for
          // void as a general undo-receive button.
          Text(
            l.receiveVoidMistakesOnlyHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.receiveVoidConfirmNo),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.receiveVoidConfirmYes),
        ),
      ],
    );
  }
}

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final mo = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final mi = local.minute.toString().padLeft(2, '0');
  return '$y-$mo-$d  $h:$mi';
}
