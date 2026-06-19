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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/config/business_rules.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/relative_time.dart';

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
Future<void> showSaleReceiptSheet(
  BuildContext context, {
  required ShopSummary shop,
  required String txnId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SaleReceiptSheet(shop: shop, txnId: txnId),
  );
}

class _SaleReceiptSheet extends StatelessWidget {
  const _SaleReceiptSheet({required this.shop, required this.txnId});

  final ShopSummary shop;
  final String txnId;

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
    try {
      await api.voidSale(
        shopId: widget.shop.id,
        txnId: header.txnId,
        clientOpId: _generateClientOpId(),
        refundAmount: outcome.refundAmount,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.saleVoidedToast)),
      );
      widget.onAfterVoid?.call();
    } on PostgrestException catch (error, stackTrace) {
      _handleVoidFailure(error, stackTrace);
    } catch (error, stackTrace) {
      _handleVoidFailure(error, stackTrace);
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
    }
    return l.saleVoidFailedMessage;
  }

  String _generateClientOpId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = _random.nextInt(1 << 32);
    return 'void-$ts-$r';
  }

  /// Native share — opens the platform action sheet so the cashier can
  /// pick WhatsApp / SMS / Notes / Print / whatever they've installed.
  /// We hand SharePlus a plain-text receipt; it preserves line breaks
  /// across every target the user typically lands on (WhatsApp, SMS,
  /// Notes, Mail). Per-target richer formats (PDF for print, vCard for
  /// contacts) would need separate adapters; out of scope for v1.
  Future<void> _onShare(_SaleBundle bundle) async {
    final l = tr(context);
    final text = _buildShareText(context, widget.shop, bundle, l);
    // Anchor the iPad popover at the screen centre — the share button's
    // RenderBox isn't easy to reach from here, and a centre origin is
    // the conventional fallback when the trigger isn't a fixed widget.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? Rect.zero
        : box.localToGlobal(Offset.zero) & box.size;
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        sharePositionOrigin: origin,
      ),
    );
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
    final posted = bundle.header.postedAt;
    if (posted == null) return false;
    if (DateTime.now().difference(posted) >= saleVoidWindow) return false;
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
            // Destructive secondary action: red text, right-aligned,
            // no fill. Findable but not the screen's primary CTA.
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: voiding ? null : onVoid,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
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
    _refundEnabled = _canOfferRefund;
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
    final refund = _refundEnabled ? _parsedRefund() : null;
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
