// Shop-local "+ Add new item" bottom sheet. Opens from Sale/Receive search
// (no matching row) and from the Products "+" / setup onboarding. Creates a
// new shop_item (base-only) and returns the IDs the caller drops straight into
// the cart / line composer.
//
// Simplified, dropdown-first (per shopkeeper feedback):
//   * "How is it sold?" / "How did the supplier deliver?" is a plain dropdown
//     of every unit — the cashier picks the unit the item is sold and counted
//     in. No chips, no per-packaging conversion here. Splitting an item into a
//     pack of smaller units is done afterward on ShopItemDetailScreen.
//   * The sale price field shows on sale + product (not receive — cost lands
//     via post_receive); required once a unit is picked.
//
// Variant differences:
//   * sale/receive — quick-add; title verb + button (ADD TO SALE / RECEIVE),
//     and whether the price field appears.
//   * product — the deliberate "Add product" flow: price + "Save & add
//     another". Stock is set later via the detail screen's adjust sheet.
//
// Receive re-exports this widget from `lib/receive/add_new_item_sheet.dart`
// so both call sites import from the path that matches their flow.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/products/item_creator.dart';
import 'package:dukan/sync/use_local_db.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/locale_controller.dart';
import 'package:dukan/shared/packaging_label.dart';

/// What the caller gets back on a successful save. Mirrors the fields the
/// Sale cart / Receive line composer pre-fill from after a "+ Add new
/// item" round-trip.
class AddNewItemResult {
  const AddNewItemResult({
    required this.shopItemId,
    required this.shopItemUnitId,
    required this.displayName,
    required this.packagingLabel,
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required this.salePrice,
  });

  final String shopItemId;
  final String shopItemUnitId;
  final String displayName;
  final String packagingLabel;
  /// Both code + label are surfaced — code drives subsequent picker
  /// queries (e.g., AddPackagingSheet), label is for display.
  final String baseUnitCode;
  final String baseUnitLabel;

  /// Null when the cashier didn't price the item (Receive variant only).
  final num? salePrice;
}

/// Sale requires a price; Receive omits it. `product` is the deliberate
/// "Add a product" flow (Products "+" / setup onboarding): price shown, plus
/// "Save & add another" for fast setup. Advanced bits (opening stock, extra
/// packagings, aliases, supplier, barcode) are added afterward on
/// ShopItemDetailScreen — so creation stays one screen, one packaging, no
/// hidden base-unit split.
enum AddNewItemVariant { sale, receive, product }

class AddNewItemSheet {
  /// Sale-side entry point. The receive sibling forwards with
  /// `variant: AddNewItemVariant.receive`.
  static Future<AddNewItemResult?> show(
    BuildContext context,
    ShopSummary shop, {
    required String initialName,
    AddNewItemVariant variant = AddNewItemVariant.sale,
    String? initialCategoryId,
    String? initialBaseUnitCode,
    String? initialPackUnitCode,
    num? initialPackSize,
  }) {
    return showModalBottomSheet<AddNewItemResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddNewItemBody(
        shop: shop,
        initialName: initialName,
        variant: variant,
        initialCategoryId: initialCategoryId,
        initialBaseUnitCode: initialBaseUnitCode,
        initialPackUnitCode: initialPackUnitCode,
        initialPackSize: initialPackSize,
      ),
    );
  }
}

/// The picked "How is it sold?" unit — the unit an item is sold and counted
/// in (always base-only now; packs of smaller units are added later on the
/// detail screen). The sold/conversion fields are retained (always null) so the
/// save path stays uniform.
class _PickerChoice {
  const _PickerChoice.baseOnly({
    required this.baseUnitCode,
    required this.baseUnitLabel,
  }) : soldUnitCode = null,
       soldUnitLabel = null,
       conversion = null,
       source = 'base';

  final String baseUnitCode;
  final String baseUnitLabel;
  final String? soldUnitCode;
  final String? soldUnitLabel;
  final num? conversion;

  /// 'base' | 'category' | 'cross_category' | 'custom'.
  final String source;

  bool get isBaseOnly => soldUnitCode == null;
}

class _AddNewItemBody extends StatefulWidget {
  const _AddNewItemBody({
    required this.shop,
    required this.initialName,
    required this.variant,
    this.initialCategoryId,
    this.initialBaseUnitCode,
    this.initialPackUnitCode,
    this.initialPackSize,
  });

  final ShopSummary shop;
  final String initialName;
  final AddNewItemVariant variant;
  final String? initialCategoryId;
  final String? initialBaseUnitCode;
  final String? initialPackUnitCode;
  final num? initialPackSize;

  @override
  State<_AddNewItemBody> createState() => _AddNewItemBodyState();
}

class _AddNewItemBodyState extends State<_AddNewItemBody> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  final FocusNode _nameFocus = FocusNode();
  Future<List<CategoryOption>>? _categoriesFuture;
  // "How is it sold?" is a plain all-units dropdown (every variant) — pick the
  // unit it's sold/counted in (base-only). Packs of smaller units are set up
  // later on the product detail screen.
  Future<List<UnitOption>>? _unitsFuture;
  UnitOption? _soldUnit;
  _PickerChoice? _picked;
  String? _categoryId;
  bool _saving = false;
  String? _locale;
  bool _prefilledPackaging = false;

  bool get _isProduct => widget.variant == AddNewItemVariant.product;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _priceController = TextEditingController();
    // Prefill the category from an AI/caller suggestion (e.g. a bono line).
    _categoryId = widget.initialCategoryId;
    _nameController.addListener(_rebuild);
    _priceController.addListener(_rebuild);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = Localizations.localeOf(context).languageCode;
    if (_locale != current) {
      _locale = current;
      final api = context.read<ShopApi>();
      // The all-units dropdown source (session-cached in ShopApi).
      _unitsFuture = api.listUnits();
      // #393: local-mirror-aware so the category picker works offline.
      _categoriesFuture = loadCategoryOptions(
        context,
        shopId: widget.shop.id,
        locale: current,
      );
    }
    // One-time: pre-select the packaging from a caller/AI suggestion (a bono
    // line). Async (needs the unit table for code→label), so it can't ride in
    // initState like the category. Guarded so the locale re-fire never repeats it.
    if (!_prefilledPackaging) {
      _prefilledPackaging = true;
      _prefillPackaging();
    }
  }

  // Resolve the caller's packaging codes to a concrete _PickerChoice, exactly
  // as the custom-packaging form synthesizes one — so the sheet opens with the
  // packaging already chosen (SAVE lit, no tap). Silently no-ops if there's no
  // base code, a code can't be resolved, or the cashier already picked during
  // the load.
  Future<void> _prefillPackaging() async {
    // Bono flow: pre-select the unit dropdown from the caller's suggested codes
    // (prefer the pack/selling unit, else the base) as a base-only pick, so the
    // sheet opens ready to save. No-op if there's no code, it can't be resolved,
    // or the cashier already picked during the load.
    final preferred =
        widget.initialPackUnitCode ?? widget.initialBaseUnitCode;
    if (preferred == null) return;
    final List<UnitOption> units;
    try {
      units = await context.read<ShopApi>().listUnits();
    } catch (_) {
      return; // offline / lookup failed → cashier picks manually
    }
    if (!mounted || _picked != null) return;
    UnitOption? unit;
    for (final u in units) {
      if (u.code == preferred) {
        unit = u;
        break;
      }
    }
    if (unit == null) return;
    final resolved = unit;
    setState(() {
      _soldUnit = resolved;
      _picked = _PickerChoice.baseOnly(
        baseUnitCode: resolved.code,
        baseUnitLabel: resolved.label,
      );
    });
  }

  @override
  void dispose() {
    _nameController.removeListener(_rebuild);
    _priceController.removeListener(_rebuild);
    _nameController.dispose();
    _priceController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// "Save & add another" (product variant): keep the sheet open, clear the
  /// per-item fields, keep the chosen category, and refocus the name.
  void _resetForAddAnother() {
    _nameController.clear();
    _priceController.clear();
    setState(() {
      _picked = null;
      _soldUnit = null;
    });
    _nameFocus.requestFocus();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  num? get _parsedPrice {
    final raw = _priceController.text.trim();
    if (raw.isEmpty) return null;
    final value = num.tryParse(raw);
    if (value == null || value < 0) return null;
    return value;
  }

  // Sale + product both price the item; receive omits it (cost lands via
  // post_receive). Required once a packaging is picked on those variants.
  bool get _priceShown => widget.variant != AddNewItemVariant.receive;
  bool get _priceRequired => _priceShown && _picked != null;

  bool get _canSave {
    if (_saving) return false;
    if (_nameController.text.trim().isEmpty) return false;
    if (_picked == null) return false;
    if (_priceRequired && _parsedPrice == null) return false;
    if (!_priceRequired && _priceController.text.trim().isNotEmpty) {
      if (_parsedPrice == null) return false;
    }
    return true;
  }

  Future<void> _onSave({bool addAnother = false}) async {
    // Guard re-entrancy: a fast double-tap (before the _saving rebuild lands)
    // would otherwise mint a SECOND item and fire two creates.
    if (_saving) return;
    final l = tr(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showError(context, l.addNewItemMissingNameMessage);
      return;
    }
    final choice = _picked;
    if (choice == null) {
      showError(context, l.addNewItemMissingPackagingMessage);
      return;
    }
    final priceText = _priceController.text.trim();
    final price = _parsedPrice;
    if (_priceRequired && price == null) {
      showError(context, l.addNewItemInvalidPriceMessage);
      return;
    }
    if (!_priceRequired && priceText.isNotEmpty && price == null) {
      showError(context, l.addNewItemInvalidPriceMessage);
      return;
    }

    final languageCode = context.read<LocaleController>().locale.languageCode;
    final defaultSide =
        widget.variant == AddNewItemVariant.receive ? 'receive' : 'sale';
    setState(() => _saving = true);
    try {
      // The offline-robust create (mint ids → optimistic mirror → createShopItem
      // w/ timeout → queue on transient failure) lives in the shared headless
      // helper — the bono review's one-tap Create reuses it. The streamlined
      // sheet is base-only (soldUnit* null); a caller that needs a base+pack
      // passes them + defaultSide.
      final result = await createShopItemDraft(
        context,
        shop: widget.shop,
        name: name,
        categoryId: _categoryId,
        baseUnitCode: choice.baseUnitCode,
        baseUnitLabel: choice.baseUnitLabel,
        soldUnitCode: choice.isBaseOnly ? null : choice.soldUnitCode,
        soldUnitLabel: choice.isBaseOnly ? null : choice.soldUnitLabel,
        soldConversion: choice.isBaseOnly ? null : choice.conversion,
        salePrice: price,
        languageCode: languageCode,
        defaultSide: defaultSide,
        errorMessage: l.addNewItemFailedMessage,
      );
      if (result == null || !mounted) return; // hard reject already surfaced
      if (addAnother) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.addNewItemSavedToast(name))),
        );
        _resetForAddAnother();
      } else {
        Navigator.of(context).pop(result);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final variantHeader = widget.variant == AddNewItemVariant.receive
        ? l.addNewItemHowDeliveredHeader
        : l.addNewItemHowSoldHeader;
    final buttonLabel = switch (widget.variant) {
      AddNewItemVariant.sale => l.addNewItemAddToSaleButton,
      AddNewItemVariant.receive => l.addNewItemAddToReceiveButton,
      AddNewItemVariant.product => l.addNewItemSaveButton,
    };
    final sheetTitle =
        _isProduct ? l.addProductSheetTitle : l.addNewItemSheetTitle;
    final choice = _picked;
    final pickedLabel = choice == null
        ? null
        : (choice.isBaseOnly
            ? choice.baseUnitLabel
            : packagingLabel(
                choice.conversion!,
                choice.baseUnitLabel,
                choice.soldUnitLabel!,
              ));

    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + viewInsets),
          // Three-zone layout — header (fixed), scrollable body, sticky
          // button row. Keeps SAVE within thumb reach even when the
          // picker has 15+ chips and the keyboard is open.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sheetTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l.addNewItemCancelButton,
                    icon: const Icon(Icons.close),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _nameController,
                        focusNode: _nameFocus,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.sentences,
                        // Somali item names get mangled by iOS/Android
                        // autocorrect ("hilib" → "kilo", "ware" → "qare").
                        // Disable both autocorrect and the suggestion
                        // strip so the keystrokes land literally.
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: l.addNewItemNameLabel,
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<List<CategoryOption>>(
                        future: _categoriesFuture,
                        builder: (context, snapshot) {
                          final categories =
                              snapshot.data ?? const <CategoryOption>[];
                          return DropdownButtonFormField<String?>(
                            initialValue: _categoryId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l.addNewItemCategoryLabel,
                              isDense: true,
                            ),
                            items: [
                              // null = "Uncategorized" sentinel.
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(l.other),
                              ),
                              for (final c in categories)
                                DropdownMenuItem<String?>(
                                  value: c.id,
                                  child: Text(c.name),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _categoryId = v),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      // "How is it sold?" / "How did the supplier deliver?" —
                      // a plain dropdown of every unit. Pick the unit it's sold
                      // and counted in (base-only). Packs of smaller units are
                      // set up later on the product detail screen.
                      FutureBuilder<List<UnitOption>>(
                        future: _unitsFuture,
                        builder: (context, snapshot) {
                          final units = snapshot.data ?? const <UnitOption>[];
                          return DropdownButtonFormField<UnitOption>(
                            initialValue: _soldUnit,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: variantHeader,
                              isDense: true,
                            ),
                            items: [
                              for (final u in units)
                                DropdownMenuItem(
                                  value: u,
                                  child: Text(u.label),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (u) => setState(() {
                                      _soldUnit = u;
                                      _picked = u == null
                                          ? null
                                          : _PickerChoice.baseOnly(
                                              baseUnitCode: u.code,
                                              baseUnitLabel: u.label,
                                            );
                                    }),
                          );
                        },
                      ),
                      if (_priceShown && choice != null) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText:
                                l.addNewItemPickedPriceLabel(pickedLabel!),
                            prefixText: '${widget.shop.currencySymbol} ',
                            isDense: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_isProduct)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: _canSave ? () => _onSave() : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : Text(buttonLabel),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed:
                          _canSave ? () => _onSave(addAnother: true) : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Text(l.addNewItemSaveAndAddAnotherButton),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                        child: Text(l.addNewItemCancelButton),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _canSave ? () => _onSave() : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(buttonLabel),
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
