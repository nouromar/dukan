// New-product (shop_item) form screen — CREATE-only. Used from the
// Products FAB and the setup-onboarding "Add my own items" entry.
//
// Form fields:
//   * Name (required, language-tagged via current locale)
//   * Base unit (required, picked from listUnits)
//   * Category (optional; defaults to "Other" / unset)
//   * Reorder threshold (optional; in base unit)
//   * Packagings: first row is the base packaging (conversion=1, unit
//     locked to the chosen base unit). The cashier can append more
//     packagings with `+ Add packaging`; each extra row picks any unit
//     and types its conversion-to-base plus an optional sale price.
//
// Save calls `createShopItem` for the row and `createShopItemUnit` for
// each additional packaging. Editing existing products lives on the
// detail screen (per-tile commits) — there is no EDIT mode here.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

class ShopItemEditorScreen extends StatefulWidget {
  const ShopItemEditorScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<ShopItemEditorScreen> createState() => _ShopItemEditorScreenState();
}

class _ShopItemEditorScreenState extends State<ShopItemEditorScreen> {
  final _nameController = TextEditingController();
  final _reorderThresholdController = TextEditingController();
  final _nameFocusNode = FocusNode();
  String? _categoryId;

  /// Index 0 is always the base packaging (conversion=1, unit locked
  /// to the chosen base unit). Subsequent rows are user-added.
  final List<_PackagingDraft> _packagings = [_PackagingDraft.base()];

  String? _baseUnitCode;
  Future<_EditorBootstrap>? _bootstrapFuture;
  bool _saving = false;
  bool _nameMissing = false;
  bool _baseUnitMissing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Localizations.localeOf can't be read in initState — wait for the
    // first didChangeDependencies, then kick off the bootstrap once.
    _bootstrapFuture ??= _loadBootstrap();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _reorderThresholdController.dispose();
    _nameFocusNode.dispose();
    for (final p in _packagings) {
      p.dispose();
    }
    super.dispose();
  }

  num? get _parsedReorderThreshold {
    final raw = _reorderThresholdController.text.trim();
    if (raw.isEmpty) return null;
    final value = num.tryParse(raw);
    if (value == null || value < 0) return null;
    return value;
  }

  Future<_EditorBootstrap> _loadBootstrap() async {
    final api = context.read<ShopApi>();
    final locale = Localizations.localeOf(context).languageCode;
    final units = await api.listUnits();
    final categories = await api.listCategories(locale: locale);
    return _EditorBootstrap(units: units, categories: categories);
  }

  void _onAddPackaging() {
    setState(() => _packagings.add(_PackagingDraft.empty()));
  }

  void _onRemovePackaging(int index) {
    if (index == 0) return; // base packaging is non-removable
    final draft = _packagings.removeAt(index);
    draft.dispose();
    setState(() {});
  }

  /// Commits the form. `keepGoing` true keeps the screen mounted and
  /// resets the per-item fields (name, threshold, packagings) so the
  /// shopkeeper can immediately type the next product without bouncing
  /// back to the list. The chosen base unit + category persist across
  /// resets — they're typically the same for a stocking session
  /// ("I'm adding 8 more rice packagings to my shop").
  Future<void> _onSave({bool keepGoing = false}) async {
    final l = tr(context);
    final name = _nameController.text.trim();
    final baseUnit = _baseUnitCode;
    setState(() {
      _nameMissing = name.isEmpty;
      _baseUnitMissing = baseUnit == null;
    });
    if (name.isEmpty || baseUnit == null) return;
    setState(() => _saving = true);
    final api = context.read<ShopApi>();
    final languageCode = Localizations.localeOf(context).languageCode;
    try {
      final basePackaging = _packagings.first;
      final created = await api.createShopItem(
        shopId: widget.shop.id,
        name: name,
        languageCode: languageCode,
        baseUnitCode: baseUnit,
        salePrice: basePackaging.parsedSalePrice,
        categoryId: _categoryId,
      );
      final shopItemId = created.shopItemId;
      // Additional packagings (rows 1..n) — each requires unit + conversion.
      for (var i = 1; i < _packagings.length; i++) {
        final p = _packagings[i];
        final unitCode = p.unitCode;
        final conversion = p.parsedConversion;
        if (unitCode == null || conversion == null || conversion <= 0) continue;
        await api.createShopItemUnit(
          shopId: widget.shop.id,
          shopItemId: shopItemId,
          unitCode: unitCode,
          conversionToBase: conversion,
          salePrice: p.parsedSalePrice,
        );
      }
      // Reorder threshold is optional — skip when unset.
      final threshold = _parsedReorderThreshold;
      if (threshold != null) {
        await api.setShopItemReorderThreshold(
          shopId: widget.shop.id,
          shopItemId: shopItemId,
          reorderThreshold: threshold,
        );
      }
      if (!mounted) return;
      if (keepGoing) {
        // Toast acknowledges the save without nav. Then reset to
        // blank for the next product so the cashier keeps typing.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.shopItemEditorSavedAndContinueToast(name)),
            duration: const Duration(seconds: 2),
          ),
        );
        _resetForNextItem();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.settingsSavedToast)),
        );
        Navigator.of(context).pop<String?>(shopItemId);
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan products',
        context: ErrorDescription('creating shop item'),
      ));
      if (mounted) showError(context, l.addNewItemFailedMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Clears per-item form state after a successful "Save & add another".
  /// Keeps base unit + category sticky (typical stocking session pattern);
  /// resets name, threshold, and packagings (back to a single base row).
  void _resetForNextItem() {
    _nameController.clear();
    _reorderThresholdController.clear();
    for (final p in _packagings) {
      p.dispose();
    }
    setState(() {
      _packagings
        ..clear()
        ..add(_PackagingDraft.base());
      _nameMissing = false;
      _baseUnitMissing = false;
    });
    _nameFocusNode.requestFocus();
  }

  String _baseUnitLabelFor(List<UnitOption> units) {
    final code = _baseUnitCode;
    if (code == null) return '';
    for (final u in units) {
      if (u.code == code) return u.label;
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.shopItemEditorTitleCreate),
      body: SafeArea(
        child: FutureBuilder<_EditorBootstrap>(
          future: _bootstrapFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              if (snapshot.error != null) {
                FlutterError.reportError(FlutterErrorDetails(
                  exception: snapshot.error!,
                  stack: snapshot.stackTrace,
                  library: 'dukan products editor',
                  context: ErrorDescription('bootstrapping new-item editor'),
                ));
              }
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l.addNewItemFailedMessage,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return _buildForm(snapshot.data!);
          },
        ),
      ),
    );
  }

  Widget _buildForm(_EditorBootstrap bootstrap) {
    final l = tr(context);
    final units = bootstrap.units;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        TextField(
          controller: _nameController,
          focusNode: _nameFocusNode,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l.shopItemEditorNameLabel,
            errorText: _nameMissing ? l.addNewItemMissingNameMessage : null,
          ),
          onChanged: (_) {
            if (_nameMissing) setState(() => _nameMissing = false);
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _baseUnitCode,
          decoration: InputDecoration(
            labelText: l.shopItemEditorBaseUnitLabel,
            errorText: _baseUnitMissing
                ? l.addNewItemMissingUnitMessage
                : null,
          ),
          items: [
            for (final u in units)
              DropdownMenuItem(value: u.code, child: Text(u.label)),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _baseUnitCode = value;
              _baseUnitMissing = false;
            });
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          initialValue: _categoryId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l.shopItemEditorCategoryLabel,
          ),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(l.other)),
            for (final c in bootstrap.categories)
              DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => setState(() => _categoryId = v),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _reorderThresholdController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            labelText: l.shopItemEditorReorderThresholdLabel,
            helperText: _baseUnitCode == null
                ? null
                : l.shopItemEditorReorderThresholdHelper(
                    _baseUnitLabelFor(bootstrap.units),
                  ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          l.shopItemEditorPackagingsHeader,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _packagings.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PackagingRow(
              draft: _packagings[i],
              units: units,
              baseUnitCode: _baseUnitCode,
              shop: widget.shop,
              onChanged: () => setState(() {}),
              onRemove: i == 0 ? null : () => _onRemovePackaging(i),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _baseUnitCode == null ? null : _onAddPackaging,
          icon: const Icon(Icons.add),
          label: Text(l.shopItemEditorAddPackagingButton),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
        ),
        const SizedBox(height: 32),
        // Save & Add another — secondary action, sits ABOVE the primary
        // SAVE so the cashier sees it during a stocking session but
        // SAVE remains the muscle-memory bottom button.
        OutlinedButton.icon(
          onPressed: _saving ? null : () => _onSave(keepGoing: true),
          icon: const Icon(Icons.add),
          label: Text(l.shopItemEditorSaveAndAddAnotherButton),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : () => _onSave(),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.shopItemEditorSaveButton),
        ),
      ],
    );
  }
}

class _EditorBootstrap {
  const _EditorBootstrap({required this.units, required this.categories});
  final List<UnitOption> units;
  final List<CategoryOption> categories;
}

class _PackagingDraft {
  _PackagingDraft._({
    required this.isBase,
    required this.unitCode,
    required String conversionInitial,
    required String salePriceInitial,
  })  : conversionController =
            TextEditingController(text: conversionInitial),
        salePriceController =
            TextEditingController(text: salePriceInitial);

  factory _PackagingDraft.base() => _PackagingDraft._(
        isBase: true,
        unitCode: null,
        conversionInitial: '1',
        salePriceInitial: '',
      );

  factory _PackagingDraft.empty() => _PackagingDraft._(
        isBase: false,
        unitCode: null,
        conversionInitial: '',
        salePriceInitial: '',
      );

  final bool isBase;
  String? unitCode;
  final TextEditingController conversionController;
  final TextEditingController salePriceController;

  num? get parsedConversion {
    final raw = conversionController.text.trim();
    return raw.isEmpty ? null : num.tryParse(raw);
  }

  num? get parsedSalePrice {
    final raw = salePriceController.text.trim();
    return raw.isEmpty ? null : num.tryParse(raw);
  }

  void dispose() {
    conversionController.dispose();
    salePriceController.dispose();
  }
}

class _PackagingRow extends StatelessWidget {
  const _PackagingRow({
    required this.draft,
    required this.units,
    required this.baseUnitCode,
    required this.shop,
    required this.onChanged,
    required this.onRemove,
  });

  final _PackagingDraft draft;
  final List<UnitOption> units;
  final String? baseUnitCode;
  final ShopSummary shop;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final unitCodeForRow =
        draft.isBase ? baseUnitCode ?? draft.unitCode : draft.unitCode;
    final unitLocked = draft.isBase;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (draft.isBase)
              Padding(
                padding:
                    const EdgeInsetsDirectional.only(bottom: 8, start: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxWidth: 100),
                  child: Text(
                    l.shopItemEditorBaseBadge,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: unitCodeForRow,
                    decoration: InputDecoration(
                      labelText: l.addPackagingUnitLabel,
                    ),
                    items: [
                      for (final u in units)
                        DropdownMenuItem(
                          value: u.code,
                          child: Text(u.label),
                        ),
                    ],
                    onChanged: unitLocked
                        ? null
                        : (value) {
                            if (value == null) return;
                            draft.unitCode = value;
                            onChanged();
                          },
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: l.removePackagingTooltip,
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: draft.conversionController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              // Base packaging conversion is always 1.
              enabled: !draft.isBase,
              decoration: InputDecoration(
                labelText: _conversionLabel(context),
              ),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: draft.salePriceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: _priceLabel(context),
                prefixText: '${shop.currencySymbol} ',
              ),
              onChanged: (_) => onChanged(),
            ),
          ],
        ),
      ),
    );
  }

  String _conversionLabel(BuildContext context) {
    final l = tr(context);
    final baseLabel = _resolveUnitLabel(baseUnitCode);
    final unitLabel = _resolveUnitLabel(draft.unitCode) ?? '—';
    return l.addPackagingConversionLabel(baseLabel ?? '—', unitLabel);
  }

  String _priceLabel(BuildContext context) {
    final l = tr(context);
    final unitLabel = _resolveUnitLabel(draft.unitCode) ?? '—';
    return l.addPackagingPriceLabel(unitLabel);
  }

  String? _resolveUnitLabel(String? code) {
    if (code == null) return null;
    for (final u in units) {
      if (u.code == code) return u.label;
    }
    return code;
  }
}
