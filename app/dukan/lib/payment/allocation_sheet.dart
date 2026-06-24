// Per-invoice allocation editor — opens from the Payment screen's
// "Choose invoices" chip. Pre-fills with the same FIFO defaults the
// server would produce so doing-nothing == FIFO; the cashier only
// edits to override. See docs/payment-allocation.md § 8.3.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/history_date.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

/// Returns the cashier-chosen allocations, or null if they dismissed
/// the sheet without applying.
Future<List<PaymentAllocationInput>?> showAllocationSheet({
  required BuildContext context,
  required ShopSummary shop,
  required String partyId,
  required String direction,
  required num totalToAllocate,
  required String partyName,
  List<PaymentAllocationInput>? initial,
}) {
  return showModalBottomSheet<List<PaymentAllocationInput>?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AllocationSheet(
      shop: shop,
      partyId: partyId,
      partyName: partyName,
      direction: direction,
      totalToAllocate: totalToAllocate,
      initial: initial,
    ),
  );
}

class _AllocationSheet extends StatefulWidget {
  const _AllocationSheet({
    required this.shop,
    required this.partyId,
    required this.partyName,
    required this.direction,
    required this.totalToAllocate,
    this.initial,
  });

  final ShopSummary shop;
  final String partyId;
  final String partyName;
  final String direction;
  final num totalToAllocate;
  final List<PaymentAllocationInput>? initial;

  @override
  State<_AllocationSheet> createState() => _AllocationSheetState();
}

class _AllocationSheetState extends State<_AllocationSheet> {
  List<UnpaidInvoice>? _invoices;
  Object? _loadError;
  final _allocated = <String, num>{};
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // #391: useLocalDb=true reads from local_unpaid_invoice
      // mirror so the allocation sheet works offline. Behavior
      // unchanged in useLocalDb=false (live RPC).
      final List<UnpaidInvoice> invoices;
      if (useLocalDb(context)) {
        final repo = context.read<LocalRepository>();
        invoices = await repo.listUnpaidInvoices(
          shopId: widget.shop.id,
          partyId: widget.partyId,
          direction: widget.direction,
        );
      } else {
        final api = context.read<ShopApi>();
        invoices = await api.listUnpaidInvoices(
          shopId: widget.shop.id,
          partyId: widget.partyId,
          direction: widget.direction,
        );
      }
      if (!mounted) return;
      _seedAllocations(invoices);
      setState(() => _invoices = invoices);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  /// FIFO simulation: walk invoices oldest first, consume up to the
  /// budget, then mark each row's allocated amount. Existing edits from
  /// `widget.initial` override the simulation.
  void _seedAllocations(List<UnpaidInvoice> invoices) {
    final initial = widget.initial;
    if (initial != null && initial.isNotEmpty) {
      for (final a in initial) {
        _allocated[a.transactionId] = a.amount;
      }
    } else {
      var remaining = widget.totalToAllocate;
      for (final inv in invoices) {
        if (remaining <= 0) break;
        final take = inv.remaining <= remaining ? inv.remaining : remaining;
        _allocated[inv.transactionId] = take;
        remaining -= take;
      }
    }
    for (final inv in invoices) {
      _controllers[inv.transactionId] = TextEditingController(
        text: _formatField(_allocated[inv.transactionId] ?? 0),
      );
    }
  }

  String _formatField(num value) {
    if (value == 0) return '';
    if (value == value.toDouble().roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTickboxChanged(UnpaidInvoice inv, bool checked) {
    setState(() {
      if (checked) {
        final unallocated = widget.totalToAllocate - _totalAllocated();
        if (unallocated <= 0) return;
        final take = inv.remaining <= unallocated ? inv.remaining : unallocated;
        _allocated[inv.transactionId] = take;
      } else {
        _allocated[inv.transactionId] = 0;
      }
      _controllers[inv.transactionId]?.text =
          _formatField(_allocated[inv.transactionId] ?? 0);
    });
  }

  void _onAmountChanged(UnpaidInvoice inv, String raw) {
    final parsed = num.tryParse(raw.trim()) ?? 0;
    setState(() {
      _allocated[inv.transactionId] = parsed < 0 ? 0 : parsed;
    });
  }

  num _totalAllocated() {
    var sum = 0.0;
    for (final v in _allocated.values) {
      sum += v.toDouble();
    }
    return sum;
  }

  void _onApply() {
    final l = tr(context);
    final allocations = <PaymentAllocationInput>[];
    for (final entry in _allocated.entries) {
      if (entry.value > 0) {
        allocations.add(
          PaymentAllocationInput(
            transactionId: entry.key,
            amount: entry.value,
          ),
        );
      }
    }
    if (allocations.isEmpty) {
      showError(context, l.allocationNeedAtLeastOne);
      return;
    }
    Navigator.of(context).pop(allocations);
  }

  Widget _buildInvoiceList(AppLocalizations l) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(l.allocationLoadFailed, textAlign: TextAlign.center),
        ),
      );
    }
    final invoices = _invoices;
    if (invoices == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (invoices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(l.allocationNoOpenInvoices, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: invoices.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _InvoiceRow(
        shop: widget.shop,
        invoice: invoices[i],
        allocated: _allocated[invoices[i].transactionId] ?? 0,
        controller: _controllers[invoices[i].transactionId]!,
        onTicked: (v) => _onTickboxChanged(invoices[i], v),
        onAmountChanged: (raw) => _onAmountChanged(invoices[i], raw),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    return SafeArea(
      child: SizedBox(
        height: media.size.height * 0.9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.allocationHeader(widget.partyName),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l.allocationToAllocate(
                            formatMoney(widget.totalToAllocate, widget.shop),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildInvoiceList(l)),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                children: [
                  _StatusLine(
                    shop: widget.shop,
                    target: widget.totalToAllocate,
                    allocated: _totalAllocated(),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          _totalAllocated() == widget.totalToAllocate
                              ? _onApply
                              : null,
                      child: Text(l.allocationApplyButton),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({
    required this.shop,
    required this.invoice,
    required this.allocated,
    required this.controller,
    required this.onTicked,
    required this.onAmountChanged,
  });

  final ShopSummary shop;
  final UnpaidInvoice invoice;
  final num allocated;
  final TextEditingController controller;
  final ValueChanged<bool> onTicked;
  final ValueChanged<String> onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final checked = allocated > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: checked,
            onChanged: (v) => onTicked(v ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatInvoiceDate(context, invoice.occurredAt),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  l.allocationRowOpen(
                    formatMoney(invoice.remaining, shop),
                    formatMoney(invoice.originalAmount, shop),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              textAlign: TextAlign.right,
              onChanged: onAmountChanged,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.shop,
    required this.target,
    required this.allocated,
  });

  final ShopSummary shop;
  final num target;
  final num allocated;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final remainder = target - allocated;
    final Color color;
    final String text;
    if (remainder > 0) {
      color = theme.colorScheme.error;
      text = l.allocationStillToAllocate(formatMoney(remainder, shop));
    } else if (remainder < 0) {
      color = theme.colorScheme.error;
      text = l.allocationOverAllocated(formatMoney(-remainder, shop));
    } else {
      color = Colors.green.shade700;
      text = l.allocationBalanced;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          remainder == 0 ? Icons.check_circle : Icons.error_outline,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}
