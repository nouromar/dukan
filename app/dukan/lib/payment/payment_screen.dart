// One screen, both directions: customer-pays-the-shop (inbound) and
// shop-pays-the-supplier (outbound). Cashier picks a type, then a
// party, types the amount, hits SAVE. Backend post_payment validates
// direction × party type and refuses to overpay the balance.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/payment/allocation_sheet.dart';
import 'package:dukan/payment/payment_controller.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/shared/client_op_id.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/optimistic_save.dart';
import 'package:dukan/shared/party_picker_sheet.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    required this.shop,
    this.initialType = PaymentType.customer,
    super.key,
  });

  final ShopSummary shop;

  /// Which direction to open on — set by the Home "Money In" / "Money Out"
  /// tiles. The on-screen toggle can still switch it.
  final PaymentType initialType;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final controller = context.read<PaymentController>();
    // Pre-select the direction the Home tile requested (Money In = customer,
    // Money Out = supplier). initType is the non-notifying variant — safe in
    // initState; it clears stale party/amount only when the direction changes,
    // so read the amount AFTER.
    controller.initType(widget.initialType);
    final amount = controller.amount;
    if (amount > 0) {
      _amountController.text = _formatField(amount);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _formatField(num value) {
    if (value == value.toDouble().roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  void _onTypeChanged(PaymentType type) {
    context.read<PaymentController>().setType(type);
    _amountController.clear();
  }

  Future<void> _onPickParty() async {
    final controller = context.read<PaymentController>();
    final picked = await showPartyPicker(
      context,
      shop: widget.shop,
      typeCode: controller.type.partyTypeCode,
    );
    if (picked != null && mounted) {
      controller.setParty(picked);
    }
  }

  void _onAmountChanged(String value) {
    final parsed = num.tryParse(value.trim()) ?? 0;
    context.read<PaymentController>().setAmount(parsed);
  }

  Future<void> _onChooseInvoices() async {
    final controller = context.read<PaymentController>();
    final party = controller.party;
    if (party == null || controller.amount <= 0) return;
    final allocations = await showAllocationSheet(
      context: context,
      shop: widget.shop,
      partyId: party.id,
      partyName: party.name,
      direction: controller.type.direction,
      totalToAllocate: controller.amount,
      initial: controller.allocations,
    );
    if (allocations != null && mounted) {
      controller.setAllocations(allocations);
    }
  }

  Future<void> _save() async {
    final l = tr(context);
    final controller = context.read<PaymentController>();
    final party = controller.party;
    if (party == null) {
      showError(
        context,
        l.paymentNeedPartyMessage(controller.type.partyTypeCode),
      );
      return;
    }
    if (controller.amount <= 0) {
      showError(context, l.paymentNeedAmountMessage);
      return;
    }
    if (controller.amount > controller.outstandingBalance) {
      showError(
        context,
        l.paymentExceedsBalanceMessage(
          formatMoney(controller.outstandingBalance, widget.shop),
        ),
      );
      return;
    }

    final api = context.read<ShopApi>();
    final amount = controller.amount;
    final partyId = party.id;
    final direction = controller.type.direction;
    final allocations = controller.allocations;
    final clientOpId = generateClientOpId('payment');
    final failureMessage = l.paymentPostFailedMessage;
    final rawNotes = _notesController.text.trim();
    final notes = rawNotes.isEmpty ? null : rawNotes;

    // #383: useLocalDb=false → direct-post path; no queue, no
    // optimistic clear. Failure surfaces an inline toast so the
    // cashier knows the operation didn't land.
    if (!useLocalDb(context)) {
      await _saveDirect(
        api: api,
        controller: controller,
        partyId: partyId,
        direction: direction,
        amount: amount,
        clientOpId: clientOpId,
        allocations: allocations,
        notes: notes,
        failureMessage: failureMessage,
        savedToast: l.paymentSavedToast,
      );
      return;
    }

    final queue = context.read<OfflineQueueController>();
    final repo = context.read<LocalRepository>();
    // Capture cashier's user id before the screen pops; #367 stamps
    // it onto the queued post so Phase 5A's audit-stamping preserves
    // who originated the payment even if a different user drains.
    String actorId = '';
    try {
      actorId = Supabase.instance.client.auth.currentUser?.id ?? '';
    } catch (_) {
      actorId = '';
    }

    // #385: optimistic write to local_transaction so Payment
    // History reflects this payment instantly.
    try {
      await repo.writeOptimisticTransaction(
            clientOpId: clientOpId,
            shopId: widget.shop.id,
            typeCode: 'payment',
            occurredAtMs: DateTime.now().millisecondsSinceEpoch,
            total: amount,
            partyId: partyId,
            payload: <String, dynamic>{
              'party_name': party.name,
              'payment_method_code': 'cash',
              'direction': direction,
              'notes': notes,
              'is_refund': false,
              'lines_summary': const <Map<String, dynamic>>[],
            },
          );
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'dukan payment',
        context: ErrorDescription('write optimistic payment transaction'),
      ));
    }

    // Optimistically decrement the mirrored party balance so the
    // customers/suppliers LIST reflects the payment instantly (the list
    // reads local_party.receivable/payable directly; the detail page
    // re-fetches from the server). Sync reconciles to truth.
    try {
      await repo.applyOptimisticPartyPayment(
            partyId: partyId,
            direction: direction,
            amount: amount,
          );
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'dukan payment',
        context: ErrorDescription('optimistic party balance update'),
      ));
    }

    if (!mounted) return;
    final messenger = runOptimisticSaveShell(
      context: context,
      savedToast: l.paymentSavedToast,
      onClear: () {
        controller.clearAll();
        _amountController.clear();
        _notesController.clear();
      },
    );

    unawaited(
      _postPaymentInBackground(
        api: api,
        queue: queue,
        shopId: widget.shop.id,
        actorId: actorId,
        partyId: partyId,
        direction: direction,
        amount: amount,
        clientOpId: clientOpId,
        allocations: allocations,
        notes: notes,
        messenger: messenger,
        failureMessage: failureMessage,
      ),
    );
  }

  /// #383: direct-post path when useLocalDb=false. Awaits the
  /// server response; success clears form + pops; failure shows
  /// the error and keeps form state so the cashier can retry.
  Future<void> _saveDirect({
    required ShopApi api,
    required PaymentController controller,
    required String partyId,
    required String direction,
    required num amount,
    required String clientOpId,
    required List<PaymentAllocationInput>? allocations,
    required String? notes,
    required String failureMessage,
    required String savedToast,
  }) async {
    try {
      await api.postPayment(
        shopId: widget.shop.id,
        partyId: partyId,
        direction: direction,
        amount: amount,
        paymentMethodCode: 'cash',
        clientOpId: clientOpId,
        allocations: allocations,
        notes: notes,
      );
      if (!mounted) return;
      controller.clearAll();
      _amountController.clear();
      _notesController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(savedToast)),
      );
      Navigator.of(context).maybePop();
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan payment',
        context: ErrorDescription('post_payment (useLocalDb=false)'),
      ));
      if (!mounted) return;
      showError(context, '$failureMessage\n$error');
    }
  }

  Future<void> _postPaymentInBackground({
    required ShopApi api,
    required OfflineQueueController queue,
    required String shopId,
    required String actorId,
    required String partyId,
    required String direction,
    required num amount,
    required String clientOpId,
    required List<PaymentAllocationInput>? allocations,
    required String? notes,
    required ScaffoldMessengerState messenger,
    required String failureMessage,
  }) async {
    try {
      await api.postPayment(
        shopId: shopId,
        partyId: partyId,
        direction: direction,
        amount: amount,
        paymentMethodCode: 'cash',
        clientOpId: clientOpId,
        allocations: allocations,
        notes: notes,
      );
    } on PostgrestException catch (error, stackTrace) {
      // Server-side reject — retry won't help. Surface a toast; the
      // screen has already popped so the cashier needs the visible
      // signal to re-attempt manually.
      reportBackgroundFailure(
        error: error,
        stackTrace: stackTrace,
        messenger: messenger,
        library: 'dukan payment',
        context: 'post_payment',
        failureMessage: failureMessage,
      );
    } catch (error, stackTrace) {
      // Transient — enqueue for the offline queue to retry on
      // backoff. Mirrors Sale's pattern. No toast; the queue badge
      // in the home AppBar signals that work is pending.
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan payment',
        context: ErrorDescription('post_payment (queuing for retry)'),
      ));
      final post = PendingPost(
        id: generateClientOpId('payment'),
        clientOpId: clientOpId,
        shopId: shopId,
        originalActorUserId: actorId,
        rpc: 'post_payment',
        params: buildPostPaymentParams(
          partyId: partyId,
          direction: direction,
          amount: amount,
          paymentMethodCode: 'cash',
          notes: notes,
          allocations: allocations,
        ),
        queuedAt: DateTime.now(),
      );
      await queue.enqueue(post);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final controller = context.watch<PaymentController>();
    final type = controller.type;
    final party = controller.party;
    final theme = Theme.of(context);
    final isCustomer = type == PaymentType.customer;
    final pickButtonLabel = isCustomer
        ? l.paymentPickCustomerButton
        : l.paymentPickSupplierButton;
    final balanceLabel = party == null
        ? null
        : (isCustomer
              ? l.paymentCustomerOwesLabel(
                  formatMoney(controller.outstandingBalance, widget.shop),
                )
              : l.paymentSupplierOwedLabel(
                  formatMoney(controller.outstandingBalance, widget.shop),
                ));
    final canSave = party != null &&
        controller.amount > 0 &&
        controller.amount <= controller.outstandingBalance;

    return Scaffold(
      appBar: dukanAppBar(context, l.paymentTitle),
      // #379: SAVE lives in `bottomNavigationBar` so it floats
      // above the soft keyboard. Form content is scrollable so
      // the cashier can reach the invoice-allocation chip and
      // notes field when the keyboard is up.
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<PaymentType>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: PaymentType.customer,
                    label: Text(l.paymentTypeCustomer),
                    icon: const Icon(Icons.person),
                  ),
                  ButtonSegment(
                    value: PaymentType.supplier,
                    label: Text(l.paymentTypeSupplier),
                    icon: const Icon(Icons.local_shipping),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (set) => _onTypeChanged(set.first),
              ),
              const SizedBox(height: 8),
              // Short direction hint — non-tech shopkeepers don't always
              // map "Customer / Supplier" to who's giving whom money.
              Text(
                isCustomer
                    ? l.paymentTypeCustomerHint
                    : l.paymentTypeSupplierHint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: party == null
                    ? OutlinedButton.icon(
                        onPressed: _onPickParty,
                        icon: const Icon(Icons.person_search),
                        label: Text(pickButtonLabel),
                      )
                    : InputChip(
                        avatar: const Icon(Icons.person),
                        label: Text(
                          party.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: _onPickParty,
                      ),
              ),
              if (balanceLabel != null) ...[
                const SizedBox(height: 10),
                Text(balanceLabel, style: theme.textTheme.bodyLarge),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: _onAmountChanged,
                style: theme.textTheme.headlineSmall,
                decoration: InputDecoration(
                  labelText:
                      '${widget.shop.currencySymbol} ${l.paymentAmountLabel}',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                textInputAction: TextInputAction.done,
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: l.paymentNotesLabel,
                ),
              ),
              if (canSave && controller.outstandingBalance > 0) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.center,
                  child: ActionChip(
                    avatar: Icon(
                      controller.hasExplicitAllocations
                          ? Icons.check_circle
                          : Icons.tune,
                      size: 18,
                    ),
                    label: Text(
                      controller.hasExplicitAllocations
                          ? l.paymentChooseInvoicesChipDone(
                              controller.allocations!.length,
                            )
                          : l.paymentChooseInvoicesChip,
                    ),
                    onPressed: _onChooseInvoices,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: canSave ? _save : null,
              child: Text(l.paymentSaveButton),
            ),
          ),
        ),
      ),
    );
  }
}
