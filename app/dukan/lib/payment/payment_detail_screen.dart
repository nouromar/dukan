import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/receive/receive_detail_screen.dart';
import 'package:dukan/sale/sale_detail_screen.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/history_date.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';

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
  const _PaymentBundle({required this.header, required this.allocations});
  final PaymentDetail header;
  final List<PostedAllocation> allocations;
}

class _PaymentDetailScreenState extends State<PaymentDetailScreen> {
  late Future<_PaymentBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PaymentBundle> _load() async {
    final api = context.read<ShopApi>();
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
    final isSale = a.txnType == 'sale';
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => isSale
            ? SaleDetailScreen(shop: widget.shop, txnId: a.transactionId)
            : ReceiveDetailScreen(shop: widget.shop, txnId: a.transactionId),
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
  });

  final ShopSummary shop;
  final _PaymentBundle bundle;
  final Future<void> Function(PostedAllocation) onOpenTxn;

  String _methodLabel(String code) =>
      code.isEmpty ? code : code[0].toUpperCase() + code.substring(1);

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
        const SizedBox(height: 24),
        Text(l.paymentDetailSettledHeader, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        if (bundle.allocations.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l.paymentDetailNoAllocations,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
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
              trailing: Text(
                formatMoney(a.amount, shop),
                style: theme.textTheme.titleMedium,
              ),
            ),
      ],
    );
  }
}
