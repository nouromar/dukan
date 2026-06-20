// Modal bottom sheet for adding / editing an "additional" packaging on
// the New Item editor. The BASE packaging stays inline on the parent
// form (unit + conversion are derived; only sale price + cost + stock +
// barcode are editable inline). Everything ELSE goes through this
// sheet so the parent form's packagings list reads as compact summary
// rows instead of expanded multi-field cards.
//
// Returns a `PackagingDraftSubmission` on SAVE, or `null` on CANCEL /
// scrim-dismiss. The parent applies the result to the underlying
// `_PackagingDraft` (controller-owning model in the editor screen).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/scanner/scanner_sheet.dart';
import 'package:dukan/shared/l10n.dart';

/// Plain-data payload that crosses the sheet ↔ parent boundary. The
/// sheet doesn't share Flutter controllers across files; instead it
/// returns the parsed values and lets the parent write them into its
/// own `_PackagingDraft` controllers.
class PackagingDraftSubmission {
  const PackagingDraftSubmission({
    required this.unitCode,
    required this.conversion,
    this.salePrice,
    this.cost,
    this.openingStock,
    this.barcode,
  });

  /// Selected packaging unit (e.g. "bag"). Required.
  final String unitCode;

  /// How many base units in one of this packaging. Required, > 0.
  final num conversion;

  /// Sale price per pack (optional).
  final num? salePrice;

  /// Cost per pack from supplier (optional).
  final num? cost;

  /// Opening stock count IN PACKS (sheet keeps it in pack-count;
  /// parent multiplies by [conversion] when summing to base units).
  final num? openingStock;

  /// EAN / barcode bound to this packaging (optional).
  final String? barcode;
}

/// Open the packaging editor.
///
/// - [initial] non-null = edit existing packaging; sheet pre-fills.
/// - [initial] null      = add new; sheet opens empty.
/// - [baseUnitLabel] is plugged into the "How many [base] in 1 [unit]?"
///   conversion label so the cashier sees a clear question.
Future<PackagingDraftSubmission?> showPackagingEditorSheet(
  BuildContext context, {
  required ShopSummary shop,
  required List<UnitOption> units,
  required String baseUnitLabel,
  PackagingDraftSubmission? initial,
}) {
  return showModalBottomSheet<PackagingDraftSubmission>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PackagingEditorBody(
      shop: shop,
      units: units,
      baseUnitLabel: baseUnitLabel,
      initial: initial,
    ),
  );
}

class _PackagingEditorBody extends StatefulWidget {
  const _PackagingEditorBody({
    required this.shop,
    required this.units,
    required this.baseUnitLabel,
    required this.initial,
  });

  final ShopSummary shop;
  final List<UnitOption> units;
  final String baseUnitLabel;
  final PackagingDraftSubmission? initial;

  @override
  State<_PackagingEditorBody> createState() => _PackagingEditorBodyState();
}

class _PackagingEditorBodyState extends State<_PackagingEditorBody> {
  late String? _unitCode;
  late final TextEditingController _conversionController;
  late final TextEditingController _saleController;
  late final TextEditingController _costController;
  late final TextEditingController _stockController;
  String? _barcode;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _unitCode = init?.unitCode;
    _conversionController = TextEditingController(
      text: init?.conversion.toString() ?? '',
    );
    _saleController = TextEditingController(
      text: init?.salePrice?.toString() ?? '',
    );
    _costController = TextEditingController(
      text: init?.cost?.toString() ?? '',
    );
    _stockController = TextEditingController(
      text: init?.openingStock?.toString() ?? '',
    );
    _barcode = init?.barcode;
  }

  @override
  void dispose() {
    _conversionController.dispose();
    _saleController.dispose();
    _costController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  String _unitLabel() {
    if (_unitCode == null) return '—';
    for (final u in widget.units) {
      if (u.code == _unitCode) return u.label;
    }
    return _unitCode!;
  }

  Future<void> _onScan() async {
    final event = await Scanner.open(context);
    if (event == null || !mounted) return;
    setState(() {
      _barcode = event.code;
      if (_errorMessage != null) _errorMessage = null;
    });
  }

  void _onSave() {
    final l = tr(context);
    if (_unitCode == null) {
      setState(() => _errorMessage = l.packagingEditorMissingUnitMessage);
      return;
    }
    final convText = _conversionController.text.trim();
    final conv = num.tryParse(convText);
    if (conv == null || conv <= 0) {
      setState(() => _errorMessage = l.packagingEditorMissingConversionMessage);
      return;
    }
    final sale = num.tryParse(_saleController.text.trim());
    final cost = num.tryParse(_costController.text.trim());
    final stock = num.tryParse(_stockController.text.trim());
    Navigator.of(context).pop(
      PackagingDraftSubmission(
        unitCode: _unitCode!,
        conversion: conv,
        salePrice: sale,
        cost: cost,
        openingStock: stock,
        barcode: _barcode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final isEdit = widget.initial != null;
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
                isEdit
                    ? l.packagingEditorEditTitle
                    : l.packagingEditorAddTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _unitCode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l.addPackagingUnitLabel,
                ),
                items: [
                  for (final u in widget.units)
                    DropdownMenuItem(value: u.code, child: Text(u.label)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _unitCode = value;
                    if (_errorMessage != null) _errorMessage = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _conversionController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: l.addPackagingConversionLabel(
                    widget.baseUnitLabel,
                    _unitLabel(),
                  ),
                ),
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _saleController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: l.addPackagingPriceLabel(_unitLabel()),
                  prefixText: '${widget.shop.currencySymbol} ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _costController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: l.packagingEditorCostLabel(_unitLabel()),
                  prefixText: '${widget.shop.currencySymbol} ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stockController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: l.packagingEditorStockLabel(_unitLabel()),
                ),
              ),
              const SizedBox(height: 12),
              // Barcode strip: empty → "Scan" button; bound → code + Rescan
              // + Remove. Same shape as the inline _BarcodeRow widget on
              // the parent screen.
              if (_barcode == null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _onScan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(l.shopItemEditorScanBarcodeButton),
                  ),
                )
              else
                Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l.shopItemEditorBarcodeBoundLabel(_barcode!),
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _onScan,
                      child: Text(l.shopItemEditorRescanBarcodeButton),
                    ),
                    IconButton(
                      tooltip: l.shopItemEditorRemoveBarcodeTooltip,
                      onPressed: () => setState(() => _barcode = null),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
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
                      onPressed: _onSave,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(l.packagingEditorSaveButton),
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
