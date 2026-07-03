// Receipt view for a single sale. Reached two ways:
//   1. As a route from Sale history (Scaffold-wrapped `SaleDetailScreen`).
//   2. As a modal bottom sheet from the Sale screen right after a
//      successful SAVE (`showSaleReceiptSheet`).
//
// Both surfaces render the same `SaleReceiptView`, which fetches the
// header + lines for a txn_id and lays them out receipt-style with a
// SHARE button (v1 stub — opens a "coming soon" sheet wired for
// print + WhatsApp). The history path additionally surfaces VOID when
// the sale is within the 7-day window (decisions.md Q12).

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/sale/cart_controller.dart';
import 'package:dukan/sale/receipt_pdf.dart';
import 'package:dukan/shared/client_op_id.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/relative_time.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

/// Outcome of the void confirmation dialog. `null` = cashier
/// cancelled. A returned record means "go ahead and void"; the
/// `refundAmount` is null when the cashier didn't opt into refunding,
/// or a positive number to record an outbound payment for that amount.
typedef VoidDialogOutcome = ({num? refundAmount});

class SaleDetailScreen extends StatelessWidget {
  const SaleDetailScreen({required this.shop, required this.txnId, super.key});

  final ShopSummary shop;
  final String txnId;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.saleDetailTitle),
      body: SafeArea(
        child: SaleReceiptView(
          shop: shop,
          txnId: txnId,
          showVoidAffordance: true,
          onAfterVoid: () => Navigator.of(context).pop(true),
        ),
      ),
    );
  }
}

/// Bottom-sheet entry point used by the Sale screen right after a
/// successful SAVE. Pops with `void` — there's no return value the
/// caller needs (the post is already confirmed).
///
/// `fallback` carries the just-submitted cart so the receipt can
/// render instantly even when offline_mode=full AND the txn row
/// hasn't been mirrored locally yet (sync engine catches up via
/// realtime within seconds, but we don't want to block on it).
Future<void> showSaleReceiptSheet(
  BuildContext context, {
  required ShopSummary shop,
  required String txnId,
  SaleReceiptFallback? fallback,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SaleReceiptSheet(
      shop: shop,
      txnId: txnId,
      fallback: fallback,
    ),
  );
}

/// Local cart snapshot used as the receipt source when the txn
/// hasn't yet been mirrored into local_transaction. Built by
/// [SaleReceiptFallback.fromCart] in the SAVE path.
class SaleReceiptFallback {
  const SaleReceiptFallback({
    required this.totalAmount,
    required this.paidAmount,
    required this.paymentMethodCode,
    required this.partyName,
    required this.occurredAt,
    required this.lines,
  });

  factory SaleReceiptFallback.fromCart(CartSnapshot snapshot) {
    final lines = buildSaleLineDetails(snapshot);
    final total = lines.fold<double>(0, (sum, l) => sum + l.lineTotal);
    final cashSale = !snapshot.debt;
    return SaleReceiptFallback(
      totalAmount: total,
      paidAmount: cashSale ? total : 0,
      paymentMethodCode: cashSale ? 'cash' : null,
      partyName: snapshot.customer?.name,
      occurredAt: DateTime.now(),
      lines: lines,
    );
  }

  final double totalAmount;
  final double paidAmount;
  final String? paymentMethodCode;
  final String? partyName;
  final DateTime occurredAt;
  final List<SaleLineDetail> lines;
}

/// #385: builds the `SaleLineDetail` list a cart [snapshot]
/// represents. Shared between [SaleReceiptFallback.fromCart] (the
/// post-CONFIRM receipt sheet) and the optimistic-write path in
/// `_postSaleAndAfter` (so the row written to `local_transaction`
/// at enqueue time carries the same line shape the eventual
/// server payload will overwrite it with).
List<SaleLineDetail> buildSaleLineDetails(CartSnapshot snapshot) {
  final lines = <SaleLineDetail>[];
  var i = 1;
  for (final line in snapshot.lines.values) {
    lines.add(
      SaleLineDetail(
        lineNo: i++,
        itemId: line.itemId,
        shopItemUnitId: line.shopItemUnitId,
        itemName: line.displayName,
        quantity: line.quantity.toDouble(),
        unitLabel: line.baseUnitLabel,
        unitAmount: line.unitPrice.toDouble(),
        lineTotal: line.subtotal.toDouble(),
        packagingLabel: line.packagingLabel,
      ),
    );
  }
  return lines;
}

/// JSON shape matching server `_build_transactions_payload`
/// `lines_summary` entries (per 0071). Used by the optimistic
/// write path to populate `local_transaction.payload_json.lines_
/// summary`.
List<Map<String, dynamic>> buildLinesSummaryJson(CartSnapshot snapshot) {
  final out = <Map<String, dynamic>>[];
  var i = 1;
  for (final line in snapshot.lines.values) {
    out.add(<String, dynamic>{
      'line_no': i++,
      'item_id': line.itemId,
      'shop_item_unit_id': line.shopItemUnitId,
      'item_name': line.displayName,
      'unit_code': line.baseUnitLabel,
      'unit_label': line.baseUnitLabel,
      'packaging_label': line.packagingLabel,
      'quantity': line.quantity.toDouble(),
      'unit_amount': line.unitPrice.toDouble(),
      'line_total': line.subtotal.toDouble(),
    });
  }
  return out;
}

class _SaleReceiptSheet extends StatelessWidget {
  const _SaleReceiptSheet({
    required this.shop,
    required this.txnId,
    this.fallback,
  });

  final ShopSummary shop;
  final String txnId;
  final SaleReceiptFallback? fallback;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + viewInsets),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.saleDetailTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l.saleReceiptDoneButton,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // SaleReceiptView's body uses Expanded(ListView) which
              // needs a bounded vertical constraint — Flexible inside
              // a Column with mainAxisSize.min provides exactly that.
              // No SingleChildScrollView wrapper (that would unbound
              // the height and break the Expanded).
              Flexible(
                child: SaleReceiptView(
                  shop: shop,
                  txnId: txnId,
                  fallback: fallback,
                  // Void from a freshly-completed sale is confusing —
                  // the cashier just rang it up. They can void from
                  // history if needed.
                  showVoidAffordance: false,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: Text(l.saleReceiptDoneButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SaleReceiptView extends StatefulWidget {
  const SaleReceiptView({
    required this.shop,
    required this.txnId,
    this.showVoidAffordance = true,
    this.onAfterVoid,
    this.fallback,
    super.key,
  });

  final ShopSummary shop;
  final String txnId;

  /// When false (post-save sheet), the VOID button is hidden and
  /// `onAfterVoid` is ignored.
  final bool showVoidAffordance;

  /// Called after a successful void so the host (history detail page)
  /// can pop back with a "refresh" flag. Ignored when
  /// `showVoidAffordance` is false.
  final VoidCallback? onAfterVoid;

  /// Cart-derived fallback used by the post-save sheet (#375).
  /// When offline_mode = full AND the txn isn't yet in local_*, we
  /// render from this snapshot. Otherwise unused.
  final SaleReceiptFallback? fallback;

  @override
  State<SaleReceiptView> createState() => _SaleReceiptViewState();
}

class _SaleReceiptViewState extends State<SaleReceiptView> {
  final _random = math.Random();
  late Future<_SaleBundle> _future;
  bool _voiding = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SaleBundle> _load() async {
    // #375: when offline_mode = full, render from the local mirror
    // first. If the row hasn't synced yet, fall back to the cart
    // snapshot the SAVE flow handed us, then — as a last resort —
    // fetch from the server. A receipt opened from party/history
    // before sync caught up must still open (and with the correct
    // cash/debt split), not show a "cannot load" frame.
    if (useLocalDb(context)) {
      try {
        final repo = context.read<LocalRepository>();
        final localTxn = await repo.getTransaction(widget.txnId);
        if (localTxn != null) {
          final lines = await repo.saleLinesFromLocal(widget.txnId);
          return _SaleBundle(
            header: repo.toSaleSummary(localTxn),
            lines: lines,
          );
        }
      } catch (_) {
        // Local probe failure shouldn't sink the receipt — fall
        // through to fallback / network.
      }
      final fallback = widget.fallback;
      if (fallback != null) {
        return _SaleBundle(
          header: SaleSummary(
            txnId: widget.txnId,
            occurredAt: fallback.occurredAt,
            postedAt: fallback.occurredAt,
            partyId: null,
            partyName: fallback.partyName,
            totalAmount: fallback.totalAmount,
            paidAmount: fallback.paidAmount,
            paymentMethodCode: fallback.paymentMethodCode,
            isVoided: false,
            reversalTxnId: null,
            voidedAt: null,
          ),
          lines: fallback.lines,
        );
      }
      // No local + no fallback — the row hasn't reached the mirror
      // yet. Fetch from the server rather than showing an error.
      return _loadFromNetwork();
    }
    return _loadFromNetwork();
  }

  Future<_SaleBundle> _loadFromNetwork() async {
    final api = context.read<ShopApi>();
    final header = await api.getSale(
      shopId: widget.shop.id,
      txnId: widget.txnId,
    );
    if (header == null) {
      throw StateError('Sale not found');
    }
    final lines = await api.getSaleLines(
      shopId: widget.shop.id,
      txnId: widget.txnId,
    );
    return _SaleBundle(header: header, lines: lines);
  }

  Future<void> _confirmAndVoid(SaleSummary header) async {
    final l = tr(context);
    final outcome = await showDialog<VoidDialogOutcome>(
      context: context,
      builder: (dialogCtx) =>
          _VoidConfirmDialog(shop: widget.shop, header: header),
    );
    if (outcome == null || !mounted) return;

    setState(() => _voiding = true);
    final api = context.read<ShopApi>();
    final queue = context.read<OfflineQueueController>();
    final repo = useLocalDb(context) ? context.read<LocalRepository>() : null;
    final opId = _generateClientOpId();
    String actorId = '';
    try {
      actorId = Supabase.instance.client.auth.currentUser?.id ?? '';
    } catch (_) {}

    void onVoided() {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.saleVoidedToast)),
      );
      widget.onAfterVoid?.call();
    }

    try {
      await api.voidSale(
        shopId: widget.shop.id,
        txnId: header.txnId,
        clientOpId: opId,
        refundAmount: outcome.refundAmount,
      );
      await repo?.applyOptimisticVoid(header.txnId);
      onVoided();
    } on PostgrestException catch (error, stackTrace) {
      // Structured reject (outside the void window, not owner…) — surface
      // it; nothing was voided.
      _handleVoidFailure(error, stackTrace);
    } catch (error, stackTrace) {
      // Transient (offline / network). With a local mirror, flag the void
      // optimistically + queue it — the server dedups the reversal on
      // client_op_id, so a re-drain is a safe no-op. Thin-client → surface.
      if (repo == null) {
        _handleVoidFailure(error, stackTrace);
      } else {
        await repo.applyOptimisticVoid(header.txnId);
        await queue.enqueue(PendingPost(
          id: generateClientOpId('post'),
          clientOpId: opId,
          shopId: widget.shop.id,
          originalActorUserId: actorId,
          rpc: 'void_sale',
          params: buildVoidSaleParams(
            txnId: header.txnId,
            refundAmount: outcome.refundAmount,
          ),
          queuedAt: DateTime.now(),
        ));
        onVoided();
      }
    } finally {
      if (mounted) setState(() => _voiding = false);
    }
  }

  void _handleVoidFailure(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan sale',
        context: ErrorDescription('void_sale'),
      ),
    );
    if (!mounted) return;
    showError(context, _voidErrorMessage(error));
  }

  /// Translates an exception from `void_sale` into a user-friendly
  /// snackbar string. Server-side business rules each have a known
  /// exception message in 0010_posting_rpcs.sql; we map by substring
  /// rather than coupling to error codes the RPC doesn't emit. The
  /// generic fallback no longer mentions internet (every business
  /// rule was landing there too, which was misleading).
  String _voidErrorMessage(Object error) {
    final l = tr(context);
    if (error is PostgrestException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('only the shop owner')) {
        return l.saleVoidErrorOwnerOnly;
      }
      if (msg.contains('void window') || msg.contains('outside the')) {
        return l.saleVoidErrorWindowExpired;
      }
      if (msg.contains('already') && msg.contains('void')) {
        return l.saleVoidErrorAlreadyVoided;
      }
      if (msg.contains('refund requires a customer')) {
        return l.saleVoidErrorRefundNeedsCustomer;
      }
      if (msg.contains('refund') && msg.contains('cannot exceed')) {
        return l.saleVoidErrorRefundExceedsPaid;
      }
      if (msg.contains('not found') ||
          msg.contains('only voids sale transactions')) {
        return l.saleVoidErrorNotFound;
      }
      // Partial-paid receivable guard (0085): the customer paid part of this
      // debt, so a full reversal would drive their balance negative. Not
      // transient — tell them to refund instead of implying "try again".
      if (msg.contains('paid down')) {
        return l.saleVoidErrorPartiallyPaid;
      }
    }
    return l.saleVoidFailedMessage;
  }

  String _generateClientOpId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = _random.nextInt(1 << 32);
    return 'void-$ts-$r';
  }

  /// Native share — opens the platform action sheet so the cashier can pick
  /// WhatsApp / SMS / Notes / Print / whatever they've installed. We share a
  /// formatted PDF receipt (#6) with a plain-text caption; the recipient can
  /// open/print the PDF from their viewer. Falls back to the plain-text receipt
  /// if PDF generation fails, so sharing never breaks.
  Future<void> _onShare(_SaleBundle bundle) async {
    final l = tr(context);
    final caption = _buildShareText(context, widget.shop, bundle, l);
    // Anchor the iPad popover at the screen centre — the share button's
    // RenderBox isn't easy to reach from here, and a centre origin is
    // the conventional fallback when the trigger isn't a fixed widget.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? Rect.zero
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final bytes = await buildSaleReceiptPdf(
        shop: widget.shop,
        header: bundle.header,
        lines: bundle.lines,
        l: l,
        dateText: _formatDateTime(bundle.header.occurredAt),
      );
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/${receiptNumberFor(bundle.header)}.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          text: caption,
          sharePositionOrigin: origin,
        ),
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan sale',
        context: ErrorDescription('share sale receipt PDF'),
      ));
      // Fallback: plain-text receipt still works everywhere.
      await SharePlus.instance.share(
        ShareParams(text: caption, sharePositionOrigin: origin),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return FutureBuilder<_SaleBundle>(
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
                l.saleDetailLoadFailedMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          );
        }
        return _SaleReceiptBody(
          shop: widget.shop,
          bundle: snapshot.data!,
          voiding: _voiding,
          showVoidAffordance: widget.showVoidAffordance,
          onVoid: () => _confirmAndVoid(snapshot.data!.header),
          onShare: () => _onShare(snapshot.data!),
        );
      },
    );
  }
}

class _SaleBundle {
  const _SaleBundle({required this.header, required this.lines});
  final SaleSummary header;
  final List<SaleLineDetail> lines;
}

class _SaleReceiptBody extends StatelessWidget {
  const _SaleReceiptBody({
    required this.shop,
    required this.bundle,
    required this.voiding,
    required this.showVoidAffordance,
    required this.onVoid,
    required this.onShare,
  });

  final ShopSummary shop;
  final _SaleBundle bundle;
  final bool voiding;
  final bool showVoidAffordance;
  final VoidCallback onVoid;
  final VoidCallback onShare;

  bool _canVoid(BuildContext context) {
    if (!showVoidAffordance) return false;
    if (bundle.header.isVoided) return false;
    // An offline-created sale the server hasn't seen yet carries a client_op_id
    // placeholder id (not a UUID); voiding it would send that non-UUID to
    // void_sale (22P02). Since 0099 an offline sale is minted with a client
    // UUID, so gate on the id shape (like Expense/Payment) rather than
    // postedAt==null — and measure the window from postedAt, falling back to
    // occurredAt for a not-yet-synced row (which has no server posted_at).
    if (!isServerAssignedId(bundle.header.txnId)) return false;
    final windowRef = bundle.header.postedAt ?? bundle.header.occurredAt;
    if (DateTime.now().difference(windowRef) >= shop.voidSettings.saleWindow) {
      return false;
    }
    // Capability gate — cashier role lacks sales.void. The receipt
    // sheet (showVoidAffordance: false) skips this branch entirely
    // since it's already gated above; we read capabilities on the
    // history path only.
    return context.watch<AuthController>().capabilities.canVoidSale;
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final header = bundle.header;
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
              child: Column(
                children: [
                  Text(
                    l.saleDetailVoidedHeader,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (header.voidedAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      l.saleHistoryVoidedSubtitle(
                        formatRelativeTime(context, header.voidedAt!),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          if (header.isVoided) const SizedBox(height: 12),
          Text(
            _formatDateTime(header.occurredAt),
            style: theme.textTheme.titleMedium,
          ),
          if (header.partyName != null) ...[
            const SizedBox(height: 4),
            Text(
              l.saleHistoryDebtLabel(header.partyName!),
              style: theme.textTheme.bodyLarge,
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              l.saleHistoryCashLabel,
              style: theme.textTheme.bodyLarge,
            ),
          ],
          const SizedBox(height: 16),
          const Divider(),
          Expanded(
            child: ListView.separated(
              itemCount: bundle.lines.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final line = bundle.lines[i];
                final unitPriceText = line.unitAmount == null
                    ? '—'
                    : formatMoney(line.unitAmount!, shop);
                final qtyText = line.quantity == line.quantity.roundToDouble()
                    ? line.quantity.toInt().toString()
                    : line.quantity.toString();
                // v2 receipts carry a packaging snapshot ("25 kg bag")
                // separate from the unit label ("Kg"). Render with the
                // packaging when present; fall back to the unit label
                // for older receipts (pre-redesign rows where
                // packaging_label is null).
                final unitLabel = line.packagingLabel ?? line.unitLabel;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(
                    line.itemName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    // Gen signature is alphabetical: (quantity,
                    // subtotal, unit, unitPrice).
                    l.saleDetailLineSubtotal(
                      qtyText,
                      formatMoney(line.lineTotal, shop),
                      unitLabel,
                      unitPriceText,
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(),
          _amountRow(theme, l.saleDetailTotalLabel,
              formatMoney(header.totalAmount, shop), bold: true),
          // Time-of-sale snapshot. `paid_amount` on the txn row is
          // fixed at posting and never moves, so these stay accurate
          // even after subsequent customer payments reduce the rolling
          // receivable. Showing both regardless of value keeps the
          // layout predictable across cash / debt / mixed sales.
          _amountRow(theme, l.saleDetailCashLabel,
              formatMoney(header.paidAmount, shop)),
          _amountRow(theme, l.saleDetailDebtLabel,
              formatMoney(header.totalAmount - header.paidAmount, shop)),
          const SizedBox(height: 12),
          // Primary action: share the receipt. Same widget in both the
          // post-save sheet and the history route — keeps the share
          // affordance one place even if its implementation evolves.
          if (!header.isVoided)
            FilledButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.ios_share),
              label: Text(l.saleReceiptShareButton),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          if (_canVoid(context)) ...[
            const SizedBox(height: 4),
            // Destructive secondary action: muted grey text, right-aligned,
            // no fill. Deliberately low-key — findable but far from the
            // screen's primary CTA. The confirm dialog carries the warning.
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
                    : Text(l.saleDetailVoidButton),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _amountRow(ThemeData theme, String label, String value,
      {bool bold = false}) {
    final style = (bold ? theme.textTheme.titleLarge : theme.textTheme.bodyLarge)
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

class _VoidConfirmDialog extends StatefulWidget {
  const _VoidConfirmDialog({required this.shop, required this.header});

  final ShopSummary shop;
  final SaleSummary header;

  @override
  State<_VoidConfirmDialog> createState() => _VoidConfirmDialogState();
}

class _VoidConfirmDialogState extends State<_VoidConfirmDialog> {
  late TextEditingController _refundController;
  late bool _refundEnabled;
  String? _refundError;

  /// Refund is only offered when the sale was cash-paid AND attached
  /// to a customer — the RPC refuses `Refund requires a customer
  /// party on the sale` for walk-ins. Hiding the affordance up-front
  /// stops the user from ever tripping that rule.
  bool get _canOfferRefund =>
      widget.header.paidAmount > 0 && widget.header.partyId != null;

  @override
  void initState() {
    super.initState();
    // Default OFF: a plain VOID reverses the sale without returning cash. The
    // owner ticks the box to refund only when they actually handed cash back
    // at the till. Auto-refunding on every void was a trap — it sent a refund
    // for sales the customer still owed, which the RPC then rejected.
    _refundEnabled = false;
    _refundController = TextEditingController(
      text: _canOfferRefund ? _formatField(widget.header.paidAmount) : '',
    );
    _refundController.addListener(_onRefundChanged);
  }

  @override
  void dispose() {
    _refundController.removeListener(_onRefundChanged);
    _refundController.dispose();
    super.dispose();
  }

  String _formatField(num value) {
    if (value == value.toDouble().roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  num? _parsedRefund() {
    final raw = _refundController.text.trim();
    if (raw.isEmpty) return null;
    return num.tryParse(raw);
  }

  void _onRefundChanged() {
    final l = tr(context);
    final parsed = _parsedRefund();
    final paid = widget.header.paidAmount;
    setState(() {
      if (!_refundEnabled || parsed == null) {
        _refundError = null;
      } else if (parsed > paid) {
        _refundError = l.saleVoidRefundExceedsPaidMessage(
          formatMoney(paid, widget.shop),
        );
      } else {
        _refundError = null;
      }
    });
  }

  void _onToggleRefund(bool? value) {
    setState(() {
      _refundEnabled = value ?? false;
      _refundError = null;
      if (_refundEnabled && _refundController.text.trim().isEmpty) {
        _refundController.text = _formatField(widget.header.paidAmount);
      }
    });
  }

  bool get _canConfirm {
    if (!_refundEnabled) return true;
    final parsed = _parsedRefund();
    if (parsed == null || parsed <= 0) return false;
    if (parsed > widget.header.paidAmount) return false;
    return true;
  }

  void _onConfirm() {
    if (!_canConfirm) return;
    num? refund = _refundEnabled ? _parsedRefund() : null;
    if (refund != null) {
      // Never send more than paid, and round to 2dp to match the server's
      // numeric(14,2) — belt-and-suspenders against the refund-exceeds-paid
      // rejection from a float edge.
      final paid = widget.header.paidAmount;
      refund = double.parse((refund > paid ? paid : refund).toStringAsFixed(2));
    }
    Navigator.of(context).pop<VoidDialogOutcome>((refundAmount: refund));
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.saleVoidConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.saleVoidConfirmBody),
          if (_canOfferRefund) ...[
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _refundEnabled,
              onChanged: _onToggleRefund,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l.saleVoidRefundCheckboxLabel),
              subtitle: Text(
                l.saleVoidRefundPaidHint(
                  formatMoney(widget.header.paidAmount, widget.shop),
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (_refundEnabled) ...[
              const SizedBox(height: 4),
              TextField(
                controller: _refundController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText:
                      '${widget.shop.currencySymbol} ${l.saleVoidRefundAmountLabel}',
                  errorText: _refundError,
                  isDense: true,
                ),
              ),
            ],
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.saleVoidConfirmNo),
        ),
        FilledButton(
          onPressed: _canConfirm ? _onConfirm : null,
          child: Text(l.saleVoidConfirmYes),
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

/// Plain-text receipt the user can paste into WhatsApp / SMS / Notes /
/// Mail via the native share sheet. Format is intentionally simple
/// (no monospace ASCII tables) — WhatsApp / SMS render proportional
/// fonts and ASCII alignment falls apart there. Each line item shows
/// its quantity + unit price + subtotal; totals show as "label: value"
/// rows. Uses existing i18n keys so nothing here is hardcoded English.
String _buildShareText(
  BuildContext context,
  ShopSummary shop,
  _SaleBundle bundle,
  AppLocalizations l,
) {
  final buf = StringBuffer();
  buf.writeln(shop.name);
  buf.writeln(l.saleDetailTitle);
  buf.writeln(_formatDateTime(bundle.header.occurredAt));
  if (bundle.header.partyName != null) {
    buf.writeln(l.saleHistoryDebtLabel(bundle.header.partyName!));
  } else {
    buf.writeln(l.saleHistoryCashLabel);
  }
  buf.writeln();
  for (final line in bundle.lines) {
    final qtyText = line.quantity == line.quantity.roundToDouble()
        ? line.quantity.toInt().toString()
        : line.quantity.toString();
    final unitLabel = line.packagingLabel ?? line.unitLabel;
    final unitPriceText = line.unitAmount == null
        ? '—'
        : formatMoney(line.unitAmount!, shop);
    buf.writeln(line.itemName);
    buf.writeln(
      '  ${l.saleDetailLineSubtotal(qtyText, formatMoney(line.lineTotal, shop), unitLabel, unitPriceText)}',
    );
  }
  buf.writeln();
  buf.writeln(
    '${l.saleDetailTotalLabel}: ${formatMoney(bundle.header.totalAmount, shop)}',
  );
  buf.writeln(
    '${l.saleDetailCashLabel}: ${formatMoney(bundle.header.paidAmount, shop)}',
  );
  final debt = bundle.header.totalAmount - bundle.header.paidAmount;
  if (debt > 0) {
    buf.writeln('${l.saleDetailDebtLabel}: ${formatMoney(debt, shop)}');
  }
  return buf.toString().trimRight();
}
