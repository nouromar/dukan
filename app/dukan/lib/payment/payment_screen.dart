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
import 'package:dukan/shared/dismiss_keyboard.dart';
import 'package:dukan/shared/working_date.dart';
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
    this.initialParty,
    super.key,
  });

  final ShopSummary shop;

  /// Which direction this page is locked to — Money In (customer pays the shop)
  /// or Money Out (shop pays a supplier). Set by the Home tile or the
  /// party-detail Pay button; there is no on-screen direction toggle.
  final PaymentType initialType;

  /// Party to pre-select on open (the party-detail Pay button). Null otherwise.
  final PartySearchResult? initialParty;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  /// Re-entrancy guard for SAVE. Payment has no `saving` UI state (the
  /// optimistic shell clears + pops), so a fast double-tap would otherwise
  /// run _save twice against the still-filled form, minting two client_op_ids
  /// and posting the payment TWICE — double-settling the debt.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final controller = context.read<PaymentController>();
    // Lock the direction this page opened on (Money In = customer, Money Out =
    // supplier) and pre-select a party if one was passed. Non-notifying — safe
    // in initState; read the amount AFTER.
    controller.initType(widget.initialType, party: widget.initialParty);
    // Backdating (#5): reset to today on fresh entry (sticky within a session).
    controller.initWorkingDate();
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
    // Re-entrancy guard (synchronous, before any await) — see [_saving].
    if (_saving) return;
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
    // Set AFTER validation (so a rejected-input save doesn't wedge the flag);
    // cleared in the finally below — after the direct post OR after the
    // optimistic path schedules its background post (the form is cleared by
    // then, so re-entry is harmless and input re-opens immediately).
    _saving = true;
    try {
      await _saveInner(controller, party, l);
    } finally {
      _saving = false;
    }
  }

  Future<void> _saveInner(
    PaymentController controller,
    PartySearchResult party,
    L10n l,
  ) async {
    final api = context.read<ShopApi>();
    final amount = controller.amount;
    final partyId = party.id;
    final direction = controller.type.direction;
    final allocations = controller.allocations;
    final clientOpId = generateClientOpId('payment');
    // Client-minted payment UUID shared by the optimistic mirror, the direct
    // post, and the queued post — a stable id so an offline payment can be
    // voided before it syncs (post_payment returns/keys on the payment id).
    final paymentId = generateUuidV4();
    final failureMessage = l.paymentPostFailedMessage;
    final rawNotes = _notesController.text.trim();
    final notes = rawNotes.isEmpty ? null : rawNotes;
    // Backdating (#5): captured once so the background post + optimistic write
    // agree. null = today.
    final occurredAt = controller.workingDate;

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
        paymentId: paymentId,
        allocations: allocations,
        notes: notes,
        occurredAt: occurredAt,
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
        txnId: paymentId,
        shopId: widget.shop.id,
        typeCode: 'payment',
        occurredAtMs: (occurredAt ?? DateTime.now()).millisecondsSinceEpoch,
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
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'dukan payment',
          context: ErrorDescription('write optimistic payment transaction'),
        ),
      );
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
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'dukan payment',
          context: ErrorDescription('optimistic party balance update'),
        ),
      );
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
        repo: repo,
        shopId: widget.shop.id,
        actorId: actorId,
        partyId: partyId,
        direction: direction,
        amount: amount,
        clientOpId: clientOpId,
        paymentId: paymentId,
        allocations: allocations,
        notes: notes,
        occurredAt: occurredAt,
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
    required String paymentId,
    required List<PaymentAllocationInput>? allocations,
    required String? notes,
    required DateTime? occurredAt,
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
        occurredAt: occurredAt,
        paymentId: paymentId,
      );
      if (!mounted) return;
      controller.clearAll();
      _amountController.clear();
      _notesController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(savedToast)));
      Navigator.of(context).maybePop();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan payment',
          context: ErrorDescription('post_payment (useLocalDb=false)'),
        ),
      );
      if (!mounted) return;
      showError(context, '$failureMessage\n$error');
    }
  }

  Future<void> _postPaymentInBackground({
    required ShopApi api,
    required OfflineQueueController queue,
    required LocalRepository repo,
    required String shopId,
    required String actorId,
    required String partyId,
    required String direction,
    required num amount,
    required String clientOpId,
    required String paymentId,
    required List<PaymentAllocationInput>? allocations,
    required String? notes,
    required DateTime? occurredAt,
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
        occurredAt: occurredAt,
        paymentId: paymentId,
      );
    } on PostgrestException catch (error, stackTrace) {
      // Server-side reject — retry won't help. Revert the optimistic mirror
      // writes BEFORE surfacing the error: re-charge the party balance
      // (undo the optimistic payment decrement — else the debt would show as
      // settled when it isn't) and drop the phantom payment from history.
      // Both are best-effort; the next parties/txn sync reconciles regardless.
      try {
        await repo.applyOptimisticPartyCharge(
          partyId: partyId,
          direction: direction,
          amount: amount,
        );
        await repo.deleteOptimisticTransaction(txnId: paymentId);
      } catch (_) {
        /* best-effort revert; sync reconciles */
      }
      // Screen has already popped, so the cashier needs the visible toast to
      // re-attempt manually.
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
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan payment',
          context: ErrorDescription('post_payment (queuing for retry)'),
        ),
      );
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
          occurredAt: occurredAt,
          allocations: allocations,
          paymentId: paymentId,
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
    // Direction accent: green for Money In, amber for Money Out.
    final accent = isCustomer ? Colors.green.shade700 : Colors.orange.shade800;
    final directionIcon = isCustomer ? Icons.call_received : Icons.call_made;
    final directionHint = isCustomer
        ? l.paymentTypeCustomerHint
        : l.paymentTypeSupplierHint;
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
    final canSave =
        party != null &&
        controller.amount > 0 &&
        controller.amount <= controller.outstandingBalance;

    return Scaffold(
      appBar: dukanAppBar(
        context,
        isCustomer ? l.paymentInLabel : l.paymentOutLabel,
        actions: [
          WorkingDateChip(
            workingDate: controller.workingDate,
            onChanged: controller.setWorkingDate,
          ),
        ],
      ),
      // #379: SAVE lives in `bottomNavigationBar` so it floats
      // above the soft keyboard. Form content is scrollable so
      // the cashier can reach the invoice-allocation chip and
      // notes field when the keyboard is up.
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (controller.isBackdated)
                      BackdateBanner(
                        date: controller.workingDate!,
                        onClear: () => controller.setWorkingDate(null),
                      ),
                    // Direction header — replaces the old customer/supplier
                    // toggle. The page is locked to Money In (customer) or Money
                    // Out (supplier); the colour + icon + hint make which one
                    // unmistakable.
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: accent.withValues(alpha: 0.18),
                            child: Icon(directionIcon, color: accent),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              directionHint,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                        ],
                      ),
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
                      onTapOutside: dismissKeyboardOnTapOutside,
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
                      onTapOutside: dismissKeyboardOnTapOutside,
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
            // SAVE in the body (not bottomNavigationBar) so it stays above the
            // keyboard — the bottom nav bar does not lift on iOS.
            Padding(
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
          ],
        ),
      ),
    );
  }
}
