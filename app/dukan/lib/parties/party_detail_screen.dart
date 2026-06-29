// Party detail — opens from search/picker rows or the Receivables /
// Payables reports. Shows the party's outstanding balance, recent
// transactions, and a primary PAY button that drops into the Payment
// screen pre-filled with the party's id + direction.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/payment/payment_controller.dart';
import 'package:dukan/payment/payment_screen.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/shared/client_op_id.dart';
import 'package:dukan/shared/display_name.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/history_date.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/realtime.dart';
import 'package:dukan/shared/relative_time.dart';
import 'package:dukan/sync/local_repository.dart';

class PartyDetailScreen extends StatefulWidget {
  const PartyDetailScreen({
    required this.shop,
    required this.partyId,
    super.key,
  });

  final ShopSummary shop;
  final String partyId;

  @override
  State<PartyDetailScreen> createState() => _PartyDetailScreenState();
}

class _PartyBootstrap {
  const _PartyBootstrap({
    required this.detail,
    required this.openInvoices,
    this.editedAt,
  });
  final PartyDetail detail;
  /// Open sales (for customers) or open receives (for suppliers).
  /// Empty when nothing is unpaid. Drives the "Open invoices" section.
  final List<UnpaidInvoice> openInvoices;
  /// Latest `people.party.edit` audit timestamp; null when nothing
  /// has been logged for this party yet.
  final DateTime? editedAt;
}

class _PartyDetailScreenState extends State<PartyDetailScreen> {
  late Future<_PartyBootstrap> _future;
  RealtimeWatcher? _watcher;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Refetch when this party's name, phone, or running balance changes
    // — e.g. an owner edits the contact info on web, or a sale/payment
    // post by another cashier shifts the receivable/payable.
    _watcher = RealtimeWatcher.tryCreate(
      channelName: 'party_detail:${widget.partyId}',
      subscriptions: [
        RealtimeSubscription(
          table: 'party',
          filter: realtimeEq('id', widget.partyId),
        ),
      ],
      onChange: () {
        if (!mounted) return;
        setState(() {
          _future = _load();
        });
      },
    );
  }

  @override
  void dispose() {
    _watcher?.dispose();
    super.dispose();
  }

  Future<_PartyBootstrap> _load() async {
    final api = context.read<ShopApi>();
    final detailF = api.getPartyDetail(
      shopId: widget.shop.id,
      partyId: widget.partyId,
    );
    final auditF = api
        .listAuditEntriesForEntity(
          shopId: widget.shop.id,
          entityType: 'party',
          entityId: widget.partyId,
          limit: 1,
        )
        .catchError((_) => const <AuditEntry>[]);
    final detail = await detailF;
    // Direction is derived from the party type: customer → inbound,
    // supplier → outbound. A `both` party defaults to customer view.
    final direction =
        detail.header.typeCode == 'supplier' ? 'O' : 'I';
    final openInvoicesF = api
        .listUnpaidInvoices(
          shopId: widget.shop.id,
          partyId: widget.partyId,
          direction: direction,
        )
        .catchError((_) => const <UnpaidInvoice>[]);
    final audits = await auditF;
    final openInvoices = await openInvoicesF;
    final editedAt = audits.isEmpty ? null : audits.first.occurredAt;
    return _PartyBootstrap(
      detail: detail,
      openInvoices: openInvoices,
      editedAt: editedAt,
    );
  }

  /// Inline edit — opens a small dialog with name + phone fields,
  /// commits via `update_party`, then reloads so the header shows
  /// the new values.
  Future<void> _onEdit(PartyDetail detail) async {
    final l = tr(context);
    final result = await showDialog<({String name, String? phone})>(
      context: context,
      builder: (ctx) => _EditPartyDialog(initial: detail.header),
    );
    if (result == null || !mounted) return;
    // #390: queue the rename + optimistic local mirror update so
    // the new name shows immediately and the post drains when
    // online. Server-side idempotency (0074) makes retries safe.
    final clientOpId = generateClientOpId('rename_party');
    String actorId = '';
    try {
      actorId = Supabase.instance.client.auth.currentUser?.id ?? '';
    } catch (_) {}
    final queue = context.read<OfflineQueueController>();
    final repo = context.read<LocalRepository>();
    try {
      try {
        await repo.renameLocalParty(
          partyId: widget.partyId,
          name: result.name,
          phone: result.phone,
        );
      } catch (_) {
        // Mirror write failure non-fatal — queue + delta will
        // reconcile.
      }
      final post = PendingPost(
        id: generateClientOpId('post'),
        clientOpId: clientOpId,
        shopId: widget.shop.id,
        originalActorUserId: actorId,
        rpc: 'update_party',
        params: buildUpdatePartyParams(
          partyId: widget.partyId,
          name: result.name,
          phone: result.phone,
        ),
        queuedAt: DateTime.now(),
      );
      await queue.enqueue(post);
      if (!mounted) return;
      setState(() { _future = _load(); });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settingsSavedToast)),
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan parties',
        context: ErrorDescription('updating party'),
      ));
      if (mounted) showError(context, l.partyNewSaveFailedMessage);
    }
  }

  /// Hide this customer/supplier (soft-delete). Confirm → optimistic local
  /// hide → queued idempotent `set_party_active` → back to the list. Owner-only
  /// server-side (0082); search filters is_active so it disappears at once.
  Future<void> _onDeactivate() async {
    final l = tr(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.partyHideConfirmTitle),
        content: Text(l.partyHideConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cartClearConfirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.partyHideConfirmYes),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final clientOpId = generateClientOpId('set_party_active');
    String actorId = '';
    try {
      actorId = Supabase.instance.client.auth.currentUser?.id ?? '';
    } catch (_) {}
    final queue = context.read<OfflineQueueController>();
    final repo = context.read<LocalRepository>();
    try {
      try {
        await repo.setLocalPartyActive(
          partyId: widget.partyId,
          isActive: false,
        );
      } catch (_) {
        // Mirror write failure non-fatal — queue + delta reconcile.
      }
      await queue.enqueue(PendingPost(
        id: generateClientOpId('post'),
        clientOpId: clientOpId,
        shopId: widget.shop.id,
        originalActorUserId: actorId,
        rpc: 'set_party_active',
        params: buildSetPartyActiveParams(
          partyId: widget.partyId,
          isActive: false,
        ),
        queuedAt: DateTime.now(),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.partyHiddenToast)),
      );
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan parties',
        context: ErrorDescription('deactivating party'),
      ));
      if (mounted) showError(context, l.partyNewSaveFailedMessage);
    }
  }

  void _onPay(PartyDetail detail) {
    // Open the matching dedicated page (customer → Money In; supplier → Money
    // Out) with this party pre-selected. The screen locks the direction and
    // pre-fills the party in its initState.
    final type = detail.header.typeCode == 'supplier'
        ? PaymentType.supplier
        : PaymentType.customer;
    // PartyDetail.header isn't a PartySearchResult; build a minimal one.
    final party = PartySearchResult(
      id: detail.header.id,
      name: detail.header.name,
      phone: detail.header.phone,
      typeCode: detail.header.typeCode,
      receivable: detail.header.receivable,
      payable: detail.header.payable,
    );
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PaymentScreen(
              shop: widget.shop,
              initialType: type,
              initialParty: party,
            ),
          ),
        )
        .then((_) {
      // Refresh balances when returning from Payment — the payment may
      // have settled some receivable/payable.
      if (mounted) {
        setState(() { _future = _load(); });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(
        context,
        l.partyDetailTitle,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l.partyHideTooltip,
            onPressed: _onDeactivate,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_PartyBootstrap>(
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
                    l.partyDetailLoadFailedMessage,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final bootstrap = snapshot.data!;
            return _Body(
              shop: widget.shop,
              detail: bootstrap.detail,
              openInvoices: bootstrap.openInvoices,
              editedAt: bootstrap.editedAt,
              onPay: () => _onPay(bootstrap.detail),
              onEdit: () => _onEdit(bootstrap.detail),
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
    required this.detail,
    required this.openInvoices,
    required this.onPay,
    required this.onEdit,
    this.editedAt,
  });

  final ShopSummary shop;
  final PartyDetail detail;
  final List<UnpaidInvoice> openInvoices;
  final VoidCallback onPay;
  final VoidCallback onEdit;
  final DateTime? editedAt;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final header = detail.header;
    // Customer → receivable (they owe shop); supplier → payable
    // (shop owes them). Display the relevant one in red when > 0.
    final isCustomer = header.typeCode == 'customer';
    final balance = isCustomer ? header.receivable : header.payable;
    final balanceLabel = isCustomer
        ? l.partyDetailReceivableLabel
        : l.partyDetailPayableLabel;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        displayName(header.name),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: l.partyDetailEditTooltip,
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (header.phone != null && header.phone!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    header.phone!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (editedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    l.partyDetailEditedAt(
                      formatRelativeTime(context, editedAt!),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        balanceLabel,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    Text(
                      formatMoney(balance, shop),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: balance > 0 ? theme.colorScheme.error : null,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: balance > 0 ? onPay : null,
                  icon: const Icon(Icons.payments),
                  label: Text(l.partyDetailPayButton),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (openInvoices.isNotEmpty) ...[
          _SectionHeader(label: l.partyDetailOpenInvoicesHeader),
          for (final inv in openInvoices)
            _OpenInvoiceTile(shop: shop, invoice: inv),
          const SizedBox(height: 16),
        ],
        if (detail.sales.isNotEmpty) ...[
          _SectionHeader(label: l.partyDetailSalesHeader),
          for (final s in detail.sales)
            _TxnTile(
              shop: shop,
              dateTime: s.occurredAt,
              amount: s.totalAmount,
              paidAmount: s.paidAmount,
              voided: s.isVoided,
            ),
          const SizedBox(height: 16),
        ],
        if (detail.receives.isNotEmpty) ...[
          _SectionHeader(label: l.partyDetailReceivesHeader),
          for (final r in detail.receives)
            _TxnTile(
              shop: shop,
              dateTime: r.occurredAt,
              amount: r.totalAmount,
              paidAmount: r.paidAmount,
              voided: r.isVoided,
            ),
          const SizedBox(height: 16),
        ],
        if (detail.payments.isNotEmpty) ...[
          _SectionHeader(label: l.partyDetailPaymentsHeader),
          for (final p in detail.payments)
            _PaymentTile(
              shop: shop,
              dateTime: p.occurredAt,
              amount: p.amount,
              direction: p.direction,
            ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({
    required this.shop,
    required this.dateTime,
    required this.amount,
    required this.paidAmount,
    required this.voided,
  });

  final ShopSummary shop;
  final DateTime dateTime;
  final num amount;
  final num paidAmount;
  final bool voided;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      title: Text(formatHistoryStamp(context, dateTime)),
      trailing: Text(
        formatMoney(amount, shop),
        style: theme.textTheme.titleMedium?.copyWith(
          decoration: voided ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

class _OpenInvoiceTile extends StatelessWidget {
  const _OpenInvoiceTile({required this.shop, required this.invoice});

  final ShopSummary shop;
  final UnpaidInvoice invoice;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      title: Text(formatHistoryStamp(context, invoice.occurredAt)),
      subtitle: Text(
        l.partyDetailOpenInvoiceRow(
          formatMoney(invoice.remaining, shop),
          formatMoney(invoice.originalAmount, shop),
        ),
      ),
      trailing: Text(
        formatMoney(invoice.remaining, shop),
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.error,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.shop,
    required this.dateTime,
    required this.amount,
    required this.direction,
  });

  final ShopSummary shop;
  final DateTime dateTime;
  final num amount;
  final String direction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Inbound (I): money came IN — green-ish positive feel.
    // Outbound (O): money went OUT — neutral text.
    final isInbound = direction == 'I';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      leading: Icon(
        isInbound ? Icons.arrow_downward : Icons.arrow_upward,
        size: 20,
      ),
      title: Text(formatHistoryStamp(context, dateTime)),
      trailing: Text(
        formatMoney(amount, shop),
        style: theme.textTheme.titleMedium,
      ),
    );
  }
}

class _EditPartyDialog extends StatefulWidget {
  const _EditPartyDialog({required this.initial});
  final PartyDetailHeader initial;

  @override
  State<_EditPartyDialog> createState() => _EditPartyDialogState();
}

class _EditPartyDialogState extends State<_EditPartyDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial.name);
    _phoneController =
        TextEditingController(text: widget.initial.phone ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return AlertDialog(
      title: Text(l.partyDetailEditTooltip),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: l.partyNewNameLabel),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: l.partyNewPhoneLabel),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            final phone = _phoneController.text.trim();
            Navigator.of(context).pop(
              (name: name, phone: phone.isEmpty ? null : phone),
            );
          },
          child: Text(l.shopItemEditorSaveButton),
        ),
      ],
    );
  }
}
