// Bono (receive) history — reverse-chronological list of past bonos
// for the current shop. Reached via the history menu on Home or the
// history icon on the Receive screen's app bar. Tap a row → detail
// screen with the bono lines + VOID action (mistakes only).
//
// Mirrors SaleHistoryScreen tightly — same shape, but receives in v1
// are always credit, so there's no Cash branch; subtitle always shows
// the supplier.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/receive/receive_detail_screen.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';

class ReceiveHistoryScreen extends StatefulWidget {
  const ReceiveHistoryScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<ReceiveHistoryScreen> createState() => _ReceiveHistoryScreenState();
}

class _ReceiveHistoryScreenState extends State<ReceiveHistoryScreen> {
  static const int _pageLimit = 50;
  late Future<List<ReceiveSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<ReceiveSummary>> _fetch() {
    return context.read<ShopApi>().listReceives(
      shopId: widget.shop.id,
      limit: _pageLimit,
    );
  }

  void _reload() {
    setState(() => _future = _fetch());
  }

  Future<void> _openDetail(ReceiveSummary receive) async {
    final didChange = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ReceiveDetailScreen(shop: widget.shop, txnId: receive.txnId),
      ),
    );
    if (didChange == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.receiveHistoryTitle),
      body: SafeArea(
        child: FutureBuilder<List<ReceiveSummary>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    l.receiveHistoryLoadFailedMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              );
            }
            final receives = snapshot.data ?? const <ReceiveSummary>[];
            if (receives.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    l.receiveHistoryEmptyMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: receives.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _ReceiveRow(
                shop: widget.shop,
                receive: receives[i],
                onTap: () => _openDetail(receives[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReceiveRow extends StatelessWidget {
  const _ReceiveRow({
    required this.shop,
    required this.receive,
    required this.onTap,
  });

  final ShopSummary shop;
  final ReceiveSummary receive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    // Receives in v1 always have a supplier; partyName is non-null.
    // Fallback to "—" defensively so a corrupt row doesn't crash the
    // list rather than the list silently dropping it.
    final supplierName = receive.partyName ?? '—';
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _formatTime(receive.occurredAt),
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (receive.isVoided) ...[
            const SizedBox(width: 8),
            _VoidedBadge(text: l.receiveHistoryVoidedBadge),
            const SizedBox(width: 8),
          ],
          Text(
            formatMoney(receive.totalAmount, shop),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              decoration:
                  receive.isVoided ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
      subtitle: Text(l.receiveHistorySupplierLabel(supplierName)),
    );
  }
}

class _VoidedBadge extends StatelessWidget {
  const _VoidedBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _formatTime(DateTime dt) {
  final local = dt.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
