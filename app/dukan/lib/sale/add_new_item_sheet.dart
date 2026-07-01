// Shop-local "+ Add new item" bottom sheet. Opens from the Sale and
// Receive search affordances when no existing row matches the cashier's
// query. Creates a new shop_item — possibly with TWO packagings in one
// atomic call (a base packaging + a sold packaging like "25-Kg bag") —
// and returns the IDs the caller needs to drop the new item straight
// into the cart / line composer.
//
// Picker-first design (per docs/add-item-flows.md §2 & §4.1):
//   * The cashier picks one combined "How is it sold?" choice — either
//     a base-only row ("By kg") or a packaged row ("25-Kg bag" /
//     "12-Bottle carton"). Suggestions come from
//     `suggest_new_item_options`.
//   * A "+ Custom packaging" entry expands an inline form (base unit
//     dropdown + sold unit dropdown + conversion) for the long-tail
//     case where the picker has no match.
//   * Sale price field is only shown on the sale variant AND only after
//     a packaging has been picked; the label is packaging-aware.
//
// Variant flips two things:
//   * Title verb ("How is it sold?" vs "How did the supplier deliver?")
//     and button label (ADD TO SALE vs ADD TO RECEIVE).
//   * Whether the sale price field appears and is required at all. Sale
//     requires it; Receive omits it entirely — cost lands later via
//     `post_receive`.
//
// Receive re-exports this widget from `lib/receive/add_new_item_sheet.dart`
// so both call sites import from the path that matches their flow.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/sync/use_local_db.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/locale_controller.dart';
import 'package:dukan/shared/packaging_label.dart';
import 'package:dukan/shared/unit_compatibility.dart';

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

/// Sale variant requires a price; Receive doesn't. The shared widget
/// flips behaviour off this enum so both files end up tiny.
enum AddNewItemVariant { sale, receive }

class AddNewItemSheet {
  /// Sale-side entry point. The receive sibling forwards with
  /// `variant: AddNewItemVariant.receive`.
  static Future<AddNewItemResult?> show(
    BuildContext context,
    ShopSummary shop, {
    required String initialName,
    AddNewItemVariant variant = AddNewItemVariant.sale,
  }) {
    return showModalBottomSheet<AddNewItemResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddNewItemBody(
        shop: shop,
        initialName: initialName,
        variant: variant,
      ),
    );
  }
}

/// One picker choice. Either a base-only ("By kg", conversion implicit
/// = 1) or a packaged option ("25-Kg bag"). The custom form is rendered
/// as a separate path — not a `_PickerChoice` instance — so its state
/// (base/sold/conversion controllers) stays out of the picker model.
class _PickerChoice {
  const _PickerChoice.baseOnly({
    required this.baseUnitCode,
    required this.baseUnitLabel,
  }) : soldUnitCode = null,
       soldUnitLabel = null,
       conversion = null,
       source = 'base';

  const _PickerChoice.packaged({
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required String this.soldUnitCode,
    required String this.soldUnitLabel,
    required num this.conversion,
    required this.source,
  });

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
  });

  final ShopSummary shop;
  final String initialName;
  final AddNewItemVariant variant;

  @override
  State<_AddNewItemBody> createState() => _AddNewItemBodyState();
}

class _AddNewItemBodyState extends State<_AddNewItemBody> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  Future<NewItemOptions>? _optionsFuture;
  Future<List<CategoryOption>>? _categoriesFuture;
  _PickerChoice? _picked;
  String? _categoryId;
  bool _saving = false;
  String? _locale;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _priceController = TextEditingController();
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
      _optionsFuture =
          api.fetchNewItemOptions(categoryId: _categoryId, locale: current);
      // #393: local-mirror-aware so the category picker works offline.
      _categoriesFuture = loadCategoryOptions(
        context,
        shopId: widget.shop.id,
        locale: current,
      );
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_rebuild);
    _priceController.removeListener(_rebuild);
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
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

  bool get _priceShown => widget.variant == AddNewItemVariant.sale;
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

  /// Tier-1 tap on a packaged type ("Bag" / "Box" / …). Auto-picks
  /// when only one size exists for that type; otherwise opens a small
  /// sub-sheet listing just the sizes for that type.
  Future<void> _onTapType(
    String typeCode,
    List<PackagedUnitSuggestion> rowsForType,
  ) async {
    if (rowsForType.length == 1) {
      final p = rowsForType.first;
      setState(() {
        _picked = _PickerChoice.packaged(
          baseUnitCode: p.baseUnitCode,
          baseUnitLabel: p.baseUnitLabel,
          soldUnitCode: p.unitCode,
          soldUnitLabel: p.unitLabel,
          conversion: p.conversionToBase,
          source: p.source,
        );
      });
      return;
    }
    final picked = await _PackagingPickerSheet.show(
      context,
      variant: widget.variant,
      mode: _PickerMode.sizesForType(typeCode),
      rows: rowsForType,
      baseUnits: const [],
    );
    if (!mounted || picked == null) return;
    setState(() => _picked = picked);
  }

  /// Tier-1 tap on the "Loose" chip — opens a sub-sheet listing the
  /// base-unit chips ("By Packet", "By Kg", …). Auto-picks when there's
  /// only one base unit.
  Future<void> _onTapLoose(List<BaseUnitOption> baseUnits) async {
    if (baseUnits.length == 1) {
      final b = baseUnits.first;
      setState(() {
        _picked = _PickerChoice.baseOnly(
          baseUnitCode: b.unitCode,
          baseUnitLabel: b.unitLabel,
        );
      });
      return;
    }
    final picked = await _PackagingPickerSheet.show(
      context,
      variant: widget.variant,
      mode: const _PickerMode.loose(),
      rows: const [],
      baseUnits: baseUnits,
    );
    if (!mounted || picked == null) return;
    setState(() => _picked = picked);
  }

  /// Tier-1 tap on the "+ Custom packaging" chip — opens the custom
  /// form sub-sheet.
  Future<void> _onTapCustom() async {
    final picked = await _PackagingPickerSheet.show(
      context,
      variant: widget.variant,
      mode: const _PickerMode.custom(),
      rows: const [],
      baseUnits: const [],
    );
    if (!mounted || picked == null) return;
    setState(() => _picked = picked);
  }

  Future<void> _onSave() async {
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

    setState(() => _saving = true);
    final api = context.read<ShopApi>();
    final languageCode = context.read<LocaleController>().locale.languageCode;
    try {
      final created = await api.createShopItem(
        shopId: widget.shop.id,
        name: name,
        languageCode: languageCode,
        baseUnitCode: choice.baseUnitCode,
        salePrice: price,
        categoryId: _categoryId,
        soldUnitCode: choice.isBaseOnly ? null : choice.soldUnitCode,
        soldConversion: choice.isBaseOnly ? null : choice.conversion,
        defaultSide: widget.variant == AddNewItemVariant.sale
            ? 'sale'
            : 'receive',
      );
      // Synthesize the packaging label locally (mirrors the server's
      // `_format_conversion` helper) so we don't need a round trip just
      // to fetch the new row's display name.
      final label = choice.isBaseOnly
          ? choice.baseUnitLabel
          : packagingLabel(
              choice.conversion!,
              choice.baseUnitLabel,
              choice.soldUnitLabel!,
            );
      if (!mounted) return;
      Navigator.of(context).pop(
        AddNewItemResult(
          shopItemId: created.shopItemId,
          shopItemUnitId: created.defaultShopItemUnitId,
          displayName: name,
          packagingLabel: label,
          baseUnitCode: choice.baseUnitCode,
          baseUnitLabel: choice.baseUnitLabel,
          salePrice: price,
        ),
      );
    } on PostgrestException catch (error, stackTrace) {
      _handleFailure(error, stackTrace, l.addNewItemFailedMessage);
    } catch (error, stackTrace) {
      _handleFailure(error, stackTrace, l.addNewItemFailedMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _handleFailure(Object error, StackTrace stackTrace, String message) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan add-new-item',
        context: ErrorDescription('create_shop_item'),
      ),
    );
    if (!mounted) return;
    showError(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final variantHeader = widget.variant == AddNewItemVariant.sale
        ? l.addNewItemHowSoldHeader
        : l.addNewItemHowDeliveredHeader;
    final buttonLabel = widget.variant == AddNewItemVariant.sale
        ? l.addNewItemAddToSaleButton
        : l.addNewItemAddToReceiveButton;
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
                      l.addNewItemSheetTitle,
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
                      Text(
                        variantHeader,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _Tier1Chips(
                        optionsFuture: _optionsFuture,
                        picked: choice,
                        saving: _saving,
                        onTapType: _onTapType,
                        onTapLoose: _onTapLoose,
                        onTapCustom: _onTapCustom,
                      ),
                      if (choice != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '→ ${pickedLabel!}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
                      onPressed: _canSave ? _onSave : null,
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

/// Inline Tier-1 chip strip rendered directly in the main "Add new item"
/// sheet — saves a tap vs the previous trigger-then-sub-sheet path.
/// One chip per distinct packaging type code seen in the catalog, plus
/// a synthetic "Loose" chip (drills into the base-unit list) and a
/// "+ Custom packaging" escape hatch.
class _Tier1Chips extends StatelessWidget {
  const _Tier1Chips({
    required this.optionsFuture,
    required this.picked,
    required this.saving,
    required this.onTapType,
    required this.onTapLoose,
    required this.onTapCustom,
  });

  final Future<NewItemOptions>? optionsFuture;
  final _PickerChoice? picked;
  final bool saving;
  final Future<void> Function(
    String typeCode,
    List<PackagedUnitSuggestion> rowsForType,
  ) onTapType;
  final Future<void> Function(List<BaseUnitOption> baseUnits) onTapLoose;
  final Future<void> Function() onTapCustom;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return FutureBuilder<NewItemOptions>(
      future: optionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final options =
            snapshot.data ?? const NewItemOptions(baseUnits: [], packagedUnits: []);
        final byType = <String, List<PackagedUnitSuggestion>>{};
        for (final p in options.packagedUnits) {
          byType.putIfAbsent(p.unitCode, () => []).add(p);
        }
        final isPickedBaseOnly = picked != null && picked!.isBaseOnly;
        final pickedTypeCode = picked != null && !picked!.isBaseOnly
            ? picked!.soldUnitCode
            : null;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (options.baseUnits.isNotEmpty)
              _ChoiceTile(
                label: l.addNewItemLooseType,
                selected: isPickedBaseOnly,
                onTap: saving ? null : () => onTapLoose(options.baseUnits),
              ),
            for (final entry in byType.entries)
              _ChoiceTile(
                label: entry.value.first.unitLabel,
                selected: pickedTypeCode == entry.key,
                onTap: saving
                    ? null
                    : () => onTapType(entry.key, entry.value),
              ),
            _ChoiceTile(
              label: l.addNewItemCustomPackagingEntry,
              icon: Icons.tune,
              selected: picked != null && picked!.source == 'custom',
              onTap: saving ? null : onTapCustom,
            ),
            // Soft hint when both arrays come back empty (e.g., the
            // catalog has no packaged items in this category yet). The
            // Custom chip above still works.
            if (options.baseUnits.isEmpty && options.packagedUnits.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l.addNewItemLoadOptionsFailedHint,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Tier-2 / custom mode for the sub-sheet. The main sheet's chip strip
/// picks a Tier-1 type code; this mode flags how to populate the
/// sub-sheet body.
sealed class _PickerMode {
  const _PickerMode();
  const factory _PickerMode.sizesForType(String typeCode) = _SizesForType;
  const factory _PickerMode.loose() = _LooseMode;
  const factory _PickerMode.custom() = _CustomMode;
}

class _SizesForType extends _PickerMode {
  const _SizesForType(this.typeCode);
  final String typeCode;
}

class _LooseMode extends _PickerMode {
  const _LooseMode();
}

class _CustomMode extends _PickerMode {
  const _CustomMode();
}

/// Sub-sheet picker — Tier-1 lives inline on the main sheet now, so this
/// sub-sheet only handles:
///   * sizes for one specific type ("Box" → 12 Packet / 20 Packet / …),
///   * loose mode ("Loose" → By Packet / By Kg / …), or
///   * the custom-packaging form (unit dropdown + conversion field).
/// Pops back a `_PickerChoice` on confirm (or null on dismiss).
class _PackagingPickerSheet {
  static Future<_PickerChoice?> show(
    BuildContext context, {
    required AddNewItemVariant variant,
    required _PickerMode mode,
    required List<PackagedUnitSuggestion> rows,
    required List<BaseUnitOption> baseUnits,
  }) {
    return showModalBottomSheet<_PickerChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PackagingPickerBody(
        variant: variant,
        mode: mode,
        rows: rows,
        baseUnits: baseUnits,
      ),
    );
  }
}

class _PackagingPickerBody extends StatefulWidget {
  const _PackagingPickerBody({
    required this.variant,
    required this.mode,
    required this.rows,
    required this.baseUnits,
  });

  final AddNewItemVariant variant;
  final _PickerMode mode;
  final List<PackagedUnitSuggestion> rows;
  final List<BaseUnitOption> baseUnits;

  @override
  State<_PackagingPickerBody> createState() => _PackagingPickerBodyState();
}

class _PackagingPickerBodyState extends State<_PackagingPickerBody> {
  late bool _customMode;
  Future<List<UnitOption>>? _unitsFuture;
  UnitOption? _customBaseUnit;
  UnitOption? _customSoldUnit;
  late final TextEditingController _customConversionController;

  /// Grocery-first ordering for the custom dropdowns. Server-ranked
  /// suggestions don't need this.
  static const _groceryOrder = <String>[
    'kg',
    'piece',
    'packet',
    'bottle',
    'bag',
    'carton',
    'box',
    'litre',
    'ml',
    'gram',
    'sack',
    'dozen',
  ];

  @override
  void initState() {
    super.initState();
    _customConversionController = TextEditingController();
    _customConversionController.addListener(_rebuild);
    _customMode = widget.mode is _CustomMode;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lazy-load the unit list the moment the body needs it: opens
    // straight into custom mode if the main sheet routed us there.
    if (_customMode && _unitsFuture == null) {
      _unitsFuture = context.read<ShopApi>().listUnits().then(_sortUnits);
    }
  }

  @override
  void dispose() {
    _customConversionController.removeListener(_rebuild);
    _customConversionController.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  num? get _parsedCustomConversion {
    final raw = _customConversionController.text.trim();
    if (raw.isEmpty) return null;
    final value = num.tryParse(raw);
    if (value == null || value <= 0) return null;
    // Conversion = 1 means "same size as the base" — that IS the base
    // packaging. Server rejects it; we filter so the confirm CTA stays
    // disabled.
    if (value == 1) return null;
    return value;
  }

  _PickerChoice? get _customCandidate {
    final base = _customBaseUnit;
    final sold = _customSoldUnit;
    if (base == null || sold == null) return null;
    if (sold.code == base.code) {
      // sold == base degenerates into a base-only pick.
      return _PickerChoice.baseOnly(
        baseUnitCode: base.code,
        baseUnitLabel: base.label,
      );
    }
    final conv = _parsedCustomConversion;
    if (conv == null) return null;
    return _PickerChoice.packaged(
      baseUnitCode: base.code,
      baseUnitLabel: base.label,
      soldUnitCode: sold.code,
      soldUnitLabel: sold.label,
      conversion: conv,
      source: 'custom',
    );
  }

  List<UnitOption> _sortUnits(List<UnitOption> units) {
    final ordered = [...units]..sort((a, b) {
        final ai = _groceryOrder.indexOf(a.code);
        final bi = _groceryOrder.indexOf(b.code);
        if (ai == -1 && bi == -1) return a.code.compareTo(b.code);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });
    return ordered;
  }

  void _confirmCustom() {
    final candidate = _customCandidate;
    if (candidate == null) return;
    Navigator.of(context).pop(candidate);
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final title = widget.variant == AddNewItemVariant.sale
        ? l.addNewItemHowSoldHeader
        : l.addNewItemHowDeliveredHeader;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + viewInsets),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l.addNewItemCancelButton,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: _customMode
                      ? _customForm(theme, l)
                      : _sizesOrBaseUnits(theme, l),
                ),
              ),
              if (_customMode) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed:
                      _customCandidate == null ? null : _confirmCustom,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: Text(l.addNewItemUseCustomButton),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Renders the body for the chip-only modes (loose or sizesForType).
  /// Custom mode is handled by `_customForm` higher up; this builder is
  /// only ever called when `_customMode` is false.
  Widget _sizesOrBaseUnits(ThemeData theme, AppLocalizations l) {
    final children = <Widget>[];
    final mode = widget.mode;
    if (mode is _LooseMode) {
      for (final b in widget.baseUnits) {
        children.add(_ChoiceTile(
          label: l.addNewItemBaseOnlyTile(b.unitLabel),
          selected: false,
          onTap: () => Navigator.of(context).pop(
            _PickerChoice.baseOnly(
              baseUnitCode: b.unitCode,
              baseUnitLabel: b.unitLabel,
            ),
          ),
        ));
      }
    } else if (mode is _SizesForType) {
      for (final p in widget.rows) {
        children.add(_ChoiceTile(
          label: packagingLabel(
            p.conversionToBase,
            p.baseUnitLabel,
            p.unitLabel,
          ),
          selected: false,
          onTap: () => Navigator.of(context).pop(
            _PickerChoice.packaged(
              baseUnitCode: p.baseUnitCode,
              baseUnitLabel: p.baseUnitLabel,
              soldUnitCode: p.unitCode,
              soldUnitLabel: p.unitLabel,
              conversion: p.conversionToBase,
              source: p.source,
            ),
          ),
        ));
      }
    }
    return Wrap(spacing: 8, runSpacing: 8, children: children);
  }

  Widget _customForm(ThemeData theme, AppLocalizations l) {
    return FutureBuilder<List<UnitOption>>(
      future: _unitsFuture,
      builder: (context, snapshot) {
        final units = snapshot.data ?? const <UnitOption>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<UnitOption>(
              initialValue: _customBaseUnit,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l.addNewItemCustomBaseUnitLabel,
                isDense: true,
              ),
              items: [
                for (final u in units)
                  DropdownMenuItem(value: u, child: Text(u.label)),
              ],
              onChanged: (u) => setState(() {
                _customBaseUnit = u;
                _customSoldUnit = null;
              }),
            ),
            if (_customBaseUnit != null) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<UnitOption>(
                initialValue: _customSoldUnit,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l.addNewItemCustomSoldUnitLabel,
                  isDense: true,
                ),
                items: [
                  // Filter to packagings that make sense for the picked
                  // base (e.g., kg-base → no bottle/litre/piece).
                  for (final u in filterPackagingsForBase<UnitOption>(
                    _customBaseUnit!.code,
                    units,
                    (u) => u.code,
                  ))
                    DropdownMenuItem(value: u, child: Text(u.label)),
                ],
                onChanged: (u) => setState(() => _customSoldUnit = u),
              ),
            ],
            if (_customSoldUnit != null &&
                _customSoldUnit!.code != _customBaseUnit?.code) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customConversionController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: l.addNewItemCustomConversionLabel(
                    _customBaseUnit!.label,
                    _customSoldUnit!.label,
                  ),
                  isDense: true,
                ),
              ),
              if (_parsedCustomConversion != null) ...[
                const SizedBox(height: 4),
                Text(
                  l.packagingConversionPreview(
                    _customSoldUnit!.label,
                    _formatConversionPreview(_parsedCustomConversion!),
                    _customBaseUnit!.label,
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

String _formatConversionPreview(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

/// One row in the "How is it sold?" grouped picker. Visual treatment:
/// outlined when unselected, filled when selected — gives a clear
/// at-a-glance "this is what I picked" without making the whole list
/// hard to read. Sized to its content so it can live inside a Wrap and
/// pack many options per row.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surface;
    final fg = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          // ≥ 44dp tall keeps the tap target close to the 56dp guideline
          // even though the chip itself shrinks to its label.
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
