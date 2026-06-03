// Receipt-style detail view for one past sale. Owner sees a VOID
// action when the sale is within the 7-day window and not already
// voided (decisions.md Q12). Pops back with `true` after a successful
// void so the history list refreshes.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';

/// Outcome of the void confirmation dialog. `null` = cashier
/// cancelled. A returned record means "go ahead and void"; the
/// `refundAmount` is null when the cashier didn't opt into refunding,
/// or a positive number to record an outbound payment for that amount.
typedef VoidDialogOutcome = ({num? refundAmount});

class SaleDetailScreen extends StatefulWidget {
  const SaleDetailScreen({required this.shop, required this.txnId, super.key});

  final ShopSummary shop;
  final String txnId;

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
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
    final header = await api.getSale(shopId: widget.shop.id, txnId: widget.txnId);
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
      Navigator.of(context).pop(true);
    } on PostgrestException catch (error, stackTrace) {
      _handleVoidFailure(error, stackTrace, l.saleVoidFailedMessage);
    } catch (error, stackTrace) {
      _handleVoidFailure(error, stackTrace, l.saleVoidFailedMessage);
    } finally {
      if (mounted) setState(() => _voiding = false);
    }
  }

  void _handleVoidFailure(
    Object error,
    StackTrace stackTrace,
    String message,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan sale',
        context: ErrorDescription('void_sale'),
      ),
    );
    if (!mounted) return;
    showError(context, message);
  }

  String _generateClientOpId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = _random.nextInt(1 << 32);
    return 'void-$ts-$r';
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.saleDetailTitle),
      body: SafeArea(
        child: FutureBuilder<_SaleBundle>(
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
            return _SaleDetailBody(
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

class _SaleBundle {
  const _SaleBundle({required this.header, required this.lines});
  final SaleSummary header;
  final List<SaleLineDetail> lines;
}

class _SaleDetailBody extends StatelessWidget {
  const _SaleDetailBody({
    required this.shop,
    required this.bundle,
    required this.voiding,
    required this.onVoid,
  });

  final ShopSummary shop;
  final _SaleBundle bundle;
  final bool voiding;
  final VoidCallback onVoid;

  bool get _canVoid {
    if (bundle.header.isVoided) return false;
    final posted = bundle.header.postedAt;
    if (posted == null) return false;
    return DateTime.now().difference(posted).inDays < 7;
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
              child: Text(
                l.saleDetailVoidedHeader,
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
                      line.unitLabel,
                      unitPriceText,
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(),
          // Just the total. The Cash/Debt label up top conveys the
          // sale mode; an "owing" amount here would be misleading
          // because we don't track per-sale payment allocation in v1
          // (subsequent customer payments reduce the rolling
          // receivable, not this specific sale).
          _amountRow(theme, l.saleDetailTotalLabel,
              formatMoney(header.totalAmount, shop), bold: true),
          const SizedBox(height: 8),
          if (_canVoid)
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

  bool get _hasCashPaid => widget.header.paidAmount > 0;

  @override
  void initState() {
    super.initState();
    _refundEnabled = _hasCashPaid;
    _refundController = TextEditingController(
      text: _hasCashPaid ? _formatField(widget.header.paidAmount) : '',
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
          if (_hasCashPaid) ...[
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
