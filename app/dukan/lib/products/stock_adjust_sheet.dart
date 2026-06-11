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

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/shared/digit_input.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/quantity_format.dart';

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
  });

  final ShopSummary shop;
  final String shopItemId;
  final String productName;
  final num currentStock;
  final String baseUnitLabel;

  @override
  State<_StockAdjustBody> createState() => _StockAdjustBodyState();
}

class _StockAdjustBodyState extends State<_StockAdjustBody> {
  StockAdjustMode _mode = StockAdjustMode.opening;
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
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
      showError(context, l.stockAdjustInvalidAmountMessage);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<ShopApi>().postInventoryAdjustment(
            shopId: widget.shop.id,
            reasonCode: change.reason,
            shopItemId: widget.shopItemId,
            quantityDelta: change.delta,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan products',
        context: ErrorDescription('post_inventory_adjustment'),
      ));
      if (mounted) showError(context, l.stockAdjustFailedMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
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
              l.stockAdjustCurrentLabel(
                formatQty(widget.currentStock),
                widget.baseUnitLabel,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // Mode picker — segmented buttons keep all four visible.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in StockAdjustMode.values)
                  ChoiceChip(
                    label: Text(m.label(context)),
                    selected: _mode == m,
                    onSelected: (sel) {
                      if (!sel) return;
                      setState(() {
                        _mode = m;
                        _amountController.clear();
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
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l.stockAdjustAmountLabel(widget.baseUnitLabel),
              ),
            ),
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
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving || preview == null ? null : _onSave,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(l.stockAdjustSaveButton),
            ),
          ],
        ),
      ),
    );
  }
}
