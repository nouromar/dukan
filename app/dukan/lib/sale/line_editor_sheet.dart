// Long-press / no-price line editor. Two entry modes drive the same UI:
//
//   * Power-edit a priced line (priceRequired: false) — qty stepper plus a
//     price field pre-filled from the existing line/item. DONE is enabled
//     immediately because the field already holds a valid number.
//   * Activate-with-no-price (priceRequired: true) — the price field
//     starts empty, the helper text tells the cashier they must enter
//     one, and DONE stays disabled until a non-negative number is typed.
//
// The cashier can enter 0 explicitly to confirm a free sale. Line-local
// only — the entered price is NOT written back to item.sale_price.
// Persisting it waits for the Products admin screen so we don't grant
// cashiers a "set the price" capability through a side effect of Sale.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dukan/shared/l10n.dart';

class LineEditorResult {
  const LineEditorResult({required this.quantity, required this.unitPrice});

  final int quantity;
  final num unitPrice;
}

Future<LineEditorResult?> showLineEditor(
  BuildContext context, {
  required String itemName,
  required String baseUnitLabel,
  int initialQuantity = 1,
  num? initialUnitPrice,
  bool priceRequired = false,
}) {
  return showModalBottomSheet<LineEditorResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LineEditorBody(
      itemName: itemName,
      baseUnitLabel: baseUnitLabel,
      initialQuantity: initialQuantity,
      initialUnitPrice: initialUnitPrice,
      priceRequired: priceRequired,
    ),
  );
}

class _LineEditorBody extends StatefulWidget {
  const _LineEditorBody({
    required this.itemName,
    required this.baseUnitLabel,
    required this.initialQuantity,
    required this.initialUnitPrice,
    required this.priceRequired,
  });

  final String itemName;
  final String baseUnitLabel;
  final int initialQuantity;
  final num? initialUnitPrice;
  final bool priceRequired;

  @override
  State<_LineEditorBody> createState() => _LineEditorBodyState();
}

class _LineEditorBodyState extends State<_LineEditorBody> {
  late int _quantity;
  late final TextEditingController _priceController;
  bool _priceInvalid = false;

  @override
  void initState() {
    super.initState();
    _quantity = widget.initialQuantity < 1 ? 1 : widget.initialQuantity;
    final initial = widget.initialUnitPrice;
    // priceRequired mode starts empty so the cashier must type a price.
    // For long-press on an already-priced item, pre-fill so DONE is one
    // tap away when only the quantity needs changing.
    final initialText = (widget.priceRequired || initial == null)
        ? ''
        : _formatPriceForField(initial);
    _priceController = TextEditingController(text: initialText);
    _priceController.addListener(_onPriceChanged);
  }

  @override
  void dispose() {
    _priceController.removeListener(_onPriceChanged);
    _priceController.dispose();
    super.dispose();
  }

  void _onPriceChanged() {
    final raw = _priceController.text.trim();
    final parsed = num.tryParse(raw);
    final invalid = raw.isNotEmpty && (parsed == null || parsed < 0);
    if (invalid != _priceInvalid) {
      setState(() => _priceInvalid = invalid);
    } else {
      // Refresh DONE enabled state without rebuilding error text.
      setState(() {});
    }
  }

  String _formatPriceForField(num value) {
    if (value == value.toInt()) return value.toInt().toString();
    return value.toString();
  }

  num? get _parsedPrice {
    final raw = _priceController.text.trim();
    if (raw.isEmpty) return null;
    final value = num.tryParse(raw);
    if (value == null || value < 0) return null;
    return value;
  }

  bool get _canSave => _quantity >= 1 && _parsedPrice != null;

  void _onIncrement() => setState(() => _quantity++);
  void _onDecrement() {
    if (_quantity > 1) setState(() => _quantity--);
  }

  void _onConfirm() {
    final price = _parsedPrice;
    if (price == null) return;
    Navigator.of(
      context,
    ).pop(LineEditorResult(quantity: _quantity, unitPrice: price));
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + viewInsets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.itemName,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              widget.baseUnitLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Text(l.quantity, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                _StepperButton(
                  icon: Icons.remove,
                  enabled: _quantity > 1,
                  onTap: _onDecrement,
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '$_quantity',
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                ),
                _StepperButton(
                  icon: Icons.add,
                  enabled: true,
                  onTap: _onIncrement,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(l.price, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              autofocus: widget.priceRequired,
              style: theme.textTheme.headlineSmall,
              decoration: InputDecoration(
                prefixText: '\$ ',
                errorText: _priceInvalid
                    ? l.lineEditorInvalidPriceMessage
                    : null,
                helperText: widget.priceRequired
                    ? l.lineEditorPriceRequiredHelper
                    : null,
                helperStyle: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(l.cartClearConfirmNo),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _canSave ? _onConfirm : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(l.lineEditorDoneButton),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
        child: Icon(icon, size: 28),
      ),
    );
  }
}
