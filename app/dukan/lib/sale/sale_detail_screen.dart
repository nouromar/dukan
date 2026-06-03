// Receipt-style detail view for one past sale. Owner sees a VOID
// action when the sale is within the 7-day window and not already
// voided (decisions.md Q12). Pops back with `true` after a successful
// void so the history list refreshes.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l.saleVoidConfirmTitle),
        content: Text(l.saleVoidConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l.saleVoidConfirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l.saleVoidConfirmYes),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _voiding = true);
    final api = context.read<ShopApi>();
    try {
      await api.voidSale(
        shopId: widget.shop.id,
        txnId: header.txnId,
        clientOpId: _generateClientOpId(),
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
    final owing = header.totalAmount - header.paidAmount;
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
          _amountRow(theme, l.saleDetailTotalLabel,
              formatMoney(header.totalAmount, shop), bold: true),
          _amountRow(theme, l.saleDetailPaidLabel,
              formatMoney(header.paidAmount, shop)),
          if (owing > 0)
            _amountRow(theme, l.saleDetailOwingLabel,
                formatMoney(owing, shop)),
          const SizedBox(height: 16),
          if (_canVoid)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: voiding ? null : onVoid,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                ),
                child: voiding
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
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

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final mo = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final mi = local.minute.toString().padLeft(2, '0');
  return '$y-$mo-$d  $h:$mi';
}
