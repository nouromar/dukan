// Stock-adjust bottom sheet — the single place a shopkeeper changes
// the current stock of a product outside the daily Sale/Receive flow.
//
// Four modes, mapped to existing adjustment_reason codes:
//   * Opening   — opening balance from before the app (reason='opening')
//   * Add       — add to current (reason='correction', positive delta)
//   * Subtract  — subtract from current (reason='spoilage', negative delta)
//   * Set exact — type the new total; sheet computes the delta and
//                 posts as a 'correction'.
//
// All four hit post_inventory_adjustment. The sheet pops with `true`
// after a successful commit so the detail screen reloads.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/shared/client_op_id.dart';
import 'package:dukan/shared/digit_input.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/shared/quantity_format.dart';
import 'package:dukan/shared/stock_format.dart';

enum StockAdjustMode { opening, add, subtract, setExact }

extension on StockAdjustMode {
  /// Server-side reason_code for this UI mode.
  String reasonCode() => switch (this) {
        StockAdjustMode.opening => 'opening',
        StockAdjustMode.add => 'correction',
        StockAdjustMode.subtract => 'spoilage',
        StockAdjustMode.setExact => 'correction',
      };

  String label(BuildContext context) {
    final l = tr(context);
    return switch (this) {
      StockAdjustMode.opening => l.stockAdjustModeOpening,
      StockAdjustMode.add => l.stockAdjustModeAdd,
      StockAdjustMode.subtract => l.stockAdjustModeSubtract,
      StockAdjustMode.setExact => l.stockAdjustModeSetExact,
    };
  }

  String helper(BuildContext context) {
    final l = tr(context);
    return switch (this) {
      StockAdjustMode.opening => l.stockAdjustModeOpeningHelper,
      StockAdjustMode.add => l.stockAdjustModeAddHelper,
      StockAdjustMode.subtract => l.stockAdjustModeSubtractHelper,
      StockAdjustMode.setExact => l.stockAdjustModeSetExactHelper,
    };
  }
}

/// Returns `true` when the user successfully committed an adjustment;
/// `null` otherwise (cancelled or errored — error toast was shown).
Future<bool?> showStockAdjustSheet(
  BuildContext context, {
  required ShopSummary shop,
  required String shopItemId,
  required String productName,
  required num currentStock,
  required String baseUnitLabel,
  // The default-receive packaging the detail's readout renders in, so the
  // "Current" line here shows the SAME "45 Carton(12 bottle) + 4 bottle" the
  // shopkeeper just tapped — not the raw base total. Null (base-only item, or
  // conversion ≤ 1) → the Current line stays the plain base unit.
  String? packagingLabel,
  num? conversion,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _StockAdjustBody(
      shop: shop,
      shopItemId: shopItemId,
      productName: productName,
      currentStock: currentStock,
      baseUnitLabel: baseUnitLabel,
      packagingLabel: packagingLabel,
      conversion: conversion,
    ),
  );
}

class _StockAdjustBody extends StatefulWidget {
  const _StockAdjustBody({
    required this.shop,
    required this.shopItemId,
    required this.productName,
    required this.currentStock,
    required this.baseUnitLabel,
    this.packagingLabel,
    this.conversion,
  });

  final ShopSummary shop;
  final String shopItemId;
  final String productName;
  final num currentStock;
  final String baseUnitLabel;
  final String? packagingLabel;
  final num? conversion;

  @override
  State<_StockAdjustBody> createState() => _StockAdjustBodyState();
}

class _StockAdjustBodyState extends State<_StockAdjustBody> {
  // Default to "Set exact" — most intuitive for the common case
  // ("stock is -2, I want it to be 100"). The 'opening' mode is
  // server-rejected once setup_status leaves the opening window,
  // so it's hidden from the chip set below; opening-stock during
  // onboarding goes through the comprehensive editor's Section 4
  // instead (postOpeningStockAdjustment).
  StockAdjustMode _mode = StockAdjustMode.setExact;
  final _amountController = TextEditingController();
  final _unitCostController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;
  // Inline error banner. Toasts/SnackBars fire on the parent
  // ScaffoldMessenger which sits BEHIND this modal sheet on iPhone,
  // so the cashier doesn't see them. Rendering the message inline
  // is the only reliable way to surface a save failure.
  String? _errorMessage;

  @override
  void dispose() {
    _amountController.dispose();
    _unitCostController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  num? get _parsedAmount {
    final raw = _amountController.text.trim();
    if (raw.isEmpty) return null;
    final v = num.tryParse(raw);
    if (v == null || v < 0) return null;
    // setExact accepts 0 (clearing); others require > 0.
    if (v == 0 && _mode != StockAdjustMode.setExact) return null;
    return v;
  }

  /// Parsed unit cost from the cost field, or null when the field is
  /// empty / non-numeric / negative.
  num? get _parsedUnitCost {
    final raw = _unitCostController.text.trim();
    if (raw.isEmpty) return null;
    final v = num.tryParse(raw);
    if (v == null || v < 0) return null;
    return v;
  }

  /// Convert the UI amount + mode into the (delta, reason) the RPC
  /// expects. Returns null when input is invalid.
  ({num delta, String reason})? _computeChange() {
    final amount = _parsedAmount;
    if (amount == null) return null;
    switch (_mode) {
      case StockAdjustMode.opening:
      case StockAdjustMode.add:
        return (delta: amount, reason: _mode.reasonCode());
      case StockAdjustMode.subtract:
        return (delta: -amount, reason: _mode.reasonCode());
      case StockAdjustMode.setExact:
        final delta = amount - widget.currentStock;
        // No-op set keeps the sheet open with a helper.
        if (delta == 0) return null;
        return (delta: delta, reason: _mode.reasonCode());
    }
  }

  Future<void> _onSave() async {
    final l = tr(context);
    final change = _computeChange();
    if (change == null) {
      setState(() => _errorMessage = l.stockAdjustInvalidAmountMessage);
      return;
    }
    // Positive deltas need a unit cost so the server can update
    // avg_cost correctly (the RPC rejects increases without it).
    // Negative deltas use the running ledger's existing avg_cost.
    num? unitCost;
    if (change.delta > 0) {
      unitCost = _parsedUnitCost;
      if (unitCost == null) {
        setState(() =>
            _errorMessage = l.stockAdjustUnitCostRequiredMessage);
        return;
      }
    }
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    final repo = context.read<LocalRepository>();
    final queue = context.read<OfflineQueueController>();
    final clientOpId = generateClientOpId('adjust');
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();
    String actorId = '';
    try {
      actorId = Supabase.instance.client.auth.currentUser?.id ?? '';
    } catch (_) {}
    final post = PendingPost(
      id: generateClientOpId('post'),
      clientOpId: clientOpId,
      shopId: widget.shop.id,
      originalActorUserId: actorId,
      rpc: 'post_inventory_adjustment',
      params: buildPostInventoryAdjustmentParams(
        reasonCode: change.reason,
        shopItemId: widget.shopItemId,
        quantityDelta: change.delta,
        unitCost: unitCost,
        notes: notes,
      ),
      queuedAt: DateTime.now(),
    );
    try {
      await context.read<ShopApi>().postInventoryAdjustment(
            shopId: widget.shop.id,
            reasonCode: change.reason,
            shopItemId: widget.shopItemId,
            quantityDelta: change.delta,
            unitCost: unitCost,
            clientOpId: clientOpId,
            notes: notes,
          );
      // Online success: bump the mirror directly so the item detail +
      // product list show the new count immediately (the server already
      // has it; sync reconciles). Delta is already in base units.
      try {
        await repo.applyOptimisticStockDelta(
          shopItemId: widget.shopItemId,
          baseUnitDelta: change.delta,
        );
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (error, stackTrace) {
      // Server validation reject (e.g. "reason_code 'opening' not allowed
      // after setup", permission denied) — a retry won't help, so surface
      // it inline and do NOT queue.
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan products',
        context: ErrorDescription('post_inventory_adjustment (reject)'),
      ));
      if (!mounted) return;
      final raw = _errorDetail(error);
      setState(() {
        _errorMessage = raw == null
            ? l.stockAdjustFailedMessage
            : '${l.stockAdjustFailedMessage}\n$raw';
      });
    } catch (error, stackTrace) {
      // Transient / offline — queue for retry and project the delta so the
      // UI reflects the adjustment now; the projection clears when the
      // post drains (or reverts on permanent failure).
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan products',
        context: ErrorDescription('post_inventory_adjustment (queuing)'),
      ));
      try {
        await repo.writeProjection(
          pendingPostId: post.id,
          shopItemId: widget.shopItemId,
          delta: change.delta,
        );
      } catch (_) {}
      await queue.enqueue(post);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Extract a one-line server message from common error shapes so the
  /// inline banner shows something more informative than the generic
  /// copy. Returns null for opaque errors.
  static String? _errorDetail(Object error) {
    final msg = error.toString();
    if (msg.isEmpty) return null;
    final trimmed = msg.replaceFirst('Exception: ', '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final preview = _computeChange();
    final previewLine = preview == null
        ? null
        : l.stockAdjustPreview(
            formatQty(widget.currentStock + preview.delta),
            widget.baseUnitLabel,
          );
    // Wrap the body in a SingleChildScrollView so the SAVE button
    // stays reachable when the keyboard is up. Without it the
    // amount/notes fields + helper text + preview can push SAVE
    // below the visible area (iPhone 14: ~290px keyboard).
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.stockAdjustTitle(widget.productName),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                // Show the current stock in the SAME packaging the detail's
                // readout used (default-receive), so the two screens agree.
                // The amount field below stays in the base unit. Base-only
                // items keep the plain base line.
                (widget.packagingLabel != null &&
                        widget.conversion != null &&
                        widget.conversion! > 1)
                    ? l.stockAdjustCurrentValueLabel(
                        formatCompoundStock(
                          stock: widget.currentStock,
                          baseLabel: widget.baseUnitLabel,
                          packagingLabel: widget.packagingLabel,
                          conversion: widget.conversion,
                        ),
                      )
                    : l.stockAdjustCurrentLabel(
                        formatQty(widget.currentStock),
                        widget.baseUnitLabel,
                      ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              // Mode picker — Opening is hidden post-onboarding because
              // the RPC refuses it once setup_status leaves the
              // opening window. Add / Subtract / Set exact cover every
              // daily case.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in StockAdjustMode.values)
                    if (m != StockAdjustMode.opening)
                      ChoiceChip(
                        label: Text(m.label(context)),
                        selected: _mode == m,
                        onSelected: (sel) {
                          if (!sel) return;
                          setState(() {
                            _mode = m;
                            _amountController.clear();
                            // Switching modes also resets the unit
                            // cost field — it's only relevant on the
                            // ADD path (and the new mode might not
                            // need it at all).
                            _unitCostController.clear();
                            if (_errorMessage != null) {
                              _errorMessage = null;
                            }
                          });
                        },
                      ),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              _mode.helper(context),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              inputFormatters: const [DecimalDigitsInputFormatter()],
              onChanged: (_) => setState(() {
                // Typing should clear any stale error banner so the
                // cashier can retry without confusion.
                if (_errorMessage != null) _errorMessage = null;
              }),
              decoration: InputDecoration(
                labelText: l.stockAdjustAmountLabel(widget.baseUnitLabel),
              ),
            ),
            // Unit cost — shown only when the resulting delta is
            // positive. The server's post_inventory_adjustment requires
            // unit_cost on stock INCREASES so it can keep avg_cost
            // correct; subtractions/spoilage use the existing
            // ledger-resolved avg_cost and don't need the field.
            if (preview != null && preview.delta > 0) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _unitCostController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                inputFormatters: const [DecimalDigitsInputFormatter()],
                onChanged: (_) => setState(() {
                  if (_errorMessage != null) _errorMessage = null;
                }),
                decoration: InputDecoration(
                  labelText: l.stockAdjustUnitCostLabel(
                    widget.shop.currencySymbol,
                    widget.baseUnitLabel,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: l.stockAdjustNotesLabel,
              ),
            ),
            if (previewLine != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  previewLine,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            // CANCEL + SAVE side-by-side. Without a Cancel button the
            // shopkeeper had no way back to the product screen when
            // the keyboard covered the drag handle on iPhone — the
            // sheet read as a dead end.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(l.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving || preview == null ? null : _onSave,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child:
                                CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Text(l.stockAdjustSaveButton),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}
