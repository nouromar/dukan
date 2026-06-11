// Long-press / no-price line editor. v2 shape:
//
//   * Identity is `shopItemUnitId` (the packaging) plus the item context
//     the cart needs to construct or update its line (displayName,
//     packagingLabel, baseUnitLabel). The editor never sees an
//     ItemSearchResult — its callers translate that for it.
//
//   * Two entry modes drive the same UI:
//       - Power-edit a priced line (priceRequired: false) — qty stepper
//         plus a price field pre-filled from the existing line/packaging.
//         DONE is enabled immediately because the field already holds a
//         valid number.
//       - Activate-with-no-price (priceRequired: true) — the price field
//         starts empty, helper text tells the cashier they must enter
//         one, and DONE stays disabled until a non-negative number is
//         typed.
//
//   * A packaging chip below the title lets the cashier swap packagings
//     mid-edit (e.g., "sold a single bottle from the 12-bottle carton").
//     The chip is tappable iff an `onPickPackaging` opener was passed;
//     callers that don't support switching (e.g., during +Add new item)
//     can leave it null and the chip degrades to a plain label.
//
// The cashier can enter 0 explicitly to confirm a free sale. On confirm
// the editor returns the resolved shopItemUnitId + qty + price plus the
// chosen packaging label and an optional `salePriceOverride` populated
// only when the cashier picked a different packaging (so the caller can
// decide whether to seed/replace the price). The Sale flow uses the
// `priceWasEntered` flag on its CartLine (set by addOrReplaceFromEditor /
// updateLineFromEditor / switchLinePackaging) to persist sale_price
// after a successful post.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/quantity_format.dart';

/// Opener for the packaging picker. The Sale screen plugs in the v2
/// `UnitPickerSheet.show(...)` here; this indirection keeps the editor
/// usable in test/preview contexts without forcing the picker import.
typedef PackagingPickerOpener =
    Future<ReceiveUnitOption?> Function(
      BuildContext context,
      String shopItemId,
      String currentShopItemUnitId,
    );

/// Returned from the editor on confirm. `salePriceOverride` is set only
/// when the cashier switched packaging AND the new packaging carried a
/// stored sale price (so the caller knows the price came from the chip
/// rather than the cashier's keystrokes).
class LineEditorResult {
  const LineEditorResult({
    required this.shopItemUnitId,
    required this.quantity,
    required this.unitPrice,
    required this.packagingLabel,
    this.salePriceOverride,
  });

  final String shopItemUnitId;
  /// Numeric so loose-by-weight items (0.5 kg) work alongside whole
  /// packages (1 bag). Server already accepts `numeric` here.
  final num quantity;
  final num unitPrice;
  final String packagingLabel;
  final num? salePriceOverride;
}

Future<LineEditorResult?> showLineEditor(
  BuildContext context, {
  required String shopItemUnitId,
  required String displayName,
  required String packagingLabel,
  required String baseUnitLabel,
  required String currencySymbol,
  num initialQuantity = 1,
  num? initialUnitPrice,
  bool priceRequired = false,
  String? shopItemId,
  PackagingPickerOpener? onPickPackaging,
  String? priceHint,
}) {
  return showModalBottomSheet<LineEditorResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LineEditorBody(
      shopItemUnitId: shopItemUnitId,
      displayName: displayName,
      packagingLabel: packagingLabel,
      baseUnitLabel: baseUnitLabel,
      currencySymbol: currencySymbol,
      initialQuantity: initialQuantity,
      initialUnitPrice: initialUnitPrice,
      priceRequired: priceRequired,
      shopItemId: shopItemId,
      onPickPackaging: onPickPackaging,
      priceHint: priceHint,
    ),
  );
}

class _LineEditorBody extends StatefulWidget {
  const _LineEditorBody({
    required this.shopItemUnitId,
    required this.displayName,
    required this.packagingLabel,
    required this.baseUnitLabel,
    required this.currencySymbol,
    required this.initialQuantity,
    required this.initialUnitPrice,
    required this.priceRequired,
    required this.shopItemId,
    required this.onPickPackaging,
    required this.priceHint,
  });

  final String shopItemUnitId;
  final String displayName;
  final String packagingLabel;
  final String baseUnitLabel;
  final String currencySymbol;
  final num initialQuantity;
  final num? initialUnitPrice;
  final bool priceRequired;
  final String? shopItemId;
  final PackagingPickerOpener? onPickPackaging;

  /// Read-only nudge rendered under the price field in `priceRequired`
  /// mode — e.g., "Your last cost: $10. Add your usual markup." Never
  /// auto-fills the input; the cashier always types the actual price.
  final String? priceHint;

  @override
  State<_LineEditorBody> createState() => _LineEditorBodyState();
}

class _LineEditorBodyState extends State<_LineEditorBody> {
  late num _quantity;
  late TextEditingController _qtyController;
  late TextEditingController _priceController;

  // Mutable mirror of widget.* so the packaging chip can re-target the
  // editor when the cashier picks a different packaging mid-edit.
  late String _shopItemUnitId;
  late String _packagingLabel;

  // Tracks whether the cashier (vs an automatic packaging switch) last
  // touched the price field. Used to decide whether to surface the new
  // packaging's stored price as `salePriceOverride` on confirm.
  bool _priceCameFromPackaging = false;
  num? _lastPickedSalePrice;

  bool _priceInvalid = false;

  @override
  void initState() {
    super.initState();
    _quantity =
        widget.initialQuantity <= 0 ? 1 : widget.initialQuantity;
    _shopItemUnitId = widget.shopItemUnitId;
    _packagingLabel = widget.packagingLabel;
    _qtyController = TextEditingController(text: formatQty(_quantity));
    _qtyController.addListener(_onQtyChanged);
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
    _qtyController.removeListener(_onQtyChanged);
    _qtyController.dispose();
    _priceController.removeListener(_onPriceChanged);
    _priceController.dispose();
    super.dispose();
  }

  void _onQtyChanged() {
    final raw = _qtyController.text.trim();
    final parsed = num.tryParse(raw);
    if (parsed != null && parsed > 0) {
      _quantity = parsed;
    }
    if (mounted) setState(() {});
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
    // Any explicit edit invalidates the "price came from packaging"
    // marker — the cashier's typed value wins.
    if (_priceCameFromPackaging) {
      final parsedValue = parsed;
      if (parsedValue == null || parsedValue != _lastPickedSalePrice) {
        _priceCameFromPackaging = false;
      }
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

  num? get _parsedQty {
    final raw = _qtyController.text.trim();
    if (raw.isEmpty) return null;
    final v = num.tryParse(raw);
    if (v == null || v <= 0) return null;
    return v;
  }

  bool get _canSave =>
      _parsedQty != null && _parsedQty! > 0 && _parsedPrice != null;

  void _onIncrement() {
    final v = (_parsedQty ?? _quantity) + 1;
    _qtyController.text = formatQty(v);
    _qtyController.selection =
        TextSelection.collapsed(offset: _qtyController.text.length);
  }

  void _onDecrement() {
    final current = _parsedQty ?? _quantity;
    if (current <= 1) return;
    final v = current - 1;
    _qtyController.text = formatQty(v);
    _qtyController.selection =
        TextSelection.collapsed(offset: _qtyController.text.length);
  }

  Future<void> _onTapPackaging() async {
    final opener = widget.onPickPackaging;
    final shopItemId = widget.shopItemId;
    if (opener == null || shopItemId == null) return;
    final picked = await opener(context, shopItemId, _shopItemUnitId);
    if (picked == null || !mounted) return;
    // Pre-fill the price from the picked packaging if it has one; the
    // cashier can still type over it. We do NOT overwrite a price the
    // cashier already typed in priceRequired mode unless they haven't
    // touched the field yet.
    final priceText = _priceController.text.trim();
    final shouldSeed = picked.salePrice != null &&
        (priceText.isEmpty || _priceCameFromPackaging);
    setState(() {
      _shopItemUnitId = picked.shopItemUnitId;
      _packagingLabel = picked.packagingLabel;
      if (shouldSeed) {
        _priceController.text = _formatPriceForField(picked.salePrice!);
        _priceCameFromPackaging = true;
        _lastPickedSalePrice = picked.salePrice;
      } else {
        _priceCameFromPackaging = false;
        _lastPickedSalePrice = null;
      }
    });
  }

  void _onConfirm() {
    final price = _parsedPrice;
    final qty = _parsedQty;
    if (price == null || qty == null) return;
    Navigator.of(context).pop(
      LineEditorResult(
        shopItemUnitId: _shopItemUnitId,
        quantity: qty,
        unitPrice: price,
        packagingLabel: _packagingLabel,
        salePriceOverride: _priceCameFromPackaging ? price : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final canSwitchPackaging =
        widget.onPickPackaging != null && widget.shopItemId != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + viewInsets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.displayName,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Center(
              child: canSwitchPackaging
                  ? ActionChip(
                      avatar: const Icon(Icons.swap_horiz, size: 18),
                      label: Text(_packagingLabel),
                      onPressed: _onTapPackaging,
                    )
                  : Chip(
                      label: Text(_packagingLabel),
                    ),
            ),
            const SizedBox(height: 16),
            Text(l.quantity, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                _StepperButton(
                  icon: Icons.remove,
                  enabled: (_parsedQty ?? 0) > 1,
                  onTap: _onDecrement,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _qtyController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                      ),
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
                prefixText: '${widget.currencySymbol} ',
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
            if (widget.priceRequired && widget.priceHint != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.priceHint!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
