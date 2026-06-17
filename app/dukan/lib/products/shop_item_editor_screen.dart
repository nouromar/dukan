// New-product (shop_item) form screen — CREATE-only. Used from the
// Products FAB and the setup-onboarding "Add my own items" entry.
//
// Form fields per the comprehensive onboarding form plan at
// /Users/nouromar/.claude/plans/linear-fluttering-hartmanis.md:
//
//   Section 1 — Identify (always visible, required):
//     * Photo (optional capture — uploaded to shop-item-images bucket)
//     * Name (required, language-tagged via current locale)
//     * Base unit (required, picked from listUnits)
//
//   Section 2 — How you sell it (always visible, mostly required):
//     * Category (optional dropdown)
//     * Packagings: first row is the base packaging (conversion=1, unit
//       locked to the chosen base unit). The cashier can append more
//       packagings; each extra row picks any unit and types its
//       conversion-to-base plus an optional sale price + barcode.
//
//   Section 5 — Help find it faster (collapsible, optional):
//     * Aliases (chip multi-add — extra names a shopkeeper might say)
//     * Bono spelling (single text — how the item appears on supplier bonos)
//     * Per-packaging barcodes live in the packaging rows themselves.
//
//   Reorder threshold is intentionally NOT collected — matches the v1
//   East-African decision applied to the web inventory list (#312).
//
// Section 3 (default supplier + typical cost) and Section 4 (opening
// stock per packaging) are in the plan but land in the next slice;
// they need the bigger backend wrappers (set_supplier_item_unit_cost,
// postOpeningStockAdjustment) wired through with conversion math.
//
// Save calls createShopItem + createShopItemUnit per packaging, then
// the optional addShopItemAlias / addShopItemBarcode and the photo
// upload + setShopItemImagePath. Photo upload errors do NOT block the
// item save — they surface as a separate toast and the row is created
// without an image_path.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/scanner/scanner_sheet.dart';
import 'package:dukan/shared/bono_image_picker.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

class ShopItemEditorScreen extends StatefulWidget {
  const ShopItemEditorScreen({
    required this.shop,
    this.imagePicker,
    super.key,
  });

  final ShopSummary shop;

  /// Inject for tests. Production lazy-instantiates DefaultBonoImagePicker
  /// (same pattern receive_screen.dart uses for bono uploads).
  final BonoImagePicker? imagePicker;

  @override
  State<ShopItemEditorScreen> createState() => _ShopItemEditorScreenState();
}

class _ShopItemEditorScreenState extends State<ShopItemEditorScreen> {
  final _nameController = TextEditingController();
  final _aliasController = TextEditingController();
  final _bonoSpellingController = TextEditingController();
  final _nameFocusNode = FocusNode();
  String? _categoryId;

  /// Index 0 is always the base packaging (conversion=1, unit locked
  /// to the chosen base unit). Subsequent rows are user-added.
  final List<_PackagingDraft> _packagings = [_PackagingDraft.base()];

  /// Chip-style multi-add. Extras the shopkeeper types in Section 5.
  final List<String> _aliases = [];

  PickedBono? _photo;
  BonoImagePicker? _picker;

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
    _aliasController.dispose();
    _bonoSpellingController.dispose();
    _nameFocusNode.dispose();
    for (final p in _packagings) {
      p.dispose();
    }
    super.dispose();
  }

  BonoImagePicker get _imagePicker =>
      _picker ??= widget.imagePicker ?? DefaultBonoImagePicker();

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

  Future<void> _onPickPhoto() async {
    final l = tr(context);
    // Camera first; users can switch to gallery via the picker UI if
    // the platform exposes it. Errors are best-effort — fail open.
    PickedBono? picked;
    try {
      picked = await _imagePicker.pickFromCamera();
    } catch (_) {
      picked = null;
    }
    if (!mounted) return;
    if (picked == null) return;
    setState(() => _photo = picked);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.shopItemEditorPhotoCapturedToast),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onClearPhoto() => setState(() => _photo = null);

  void _onAddAlias() {
    final raw = _aliasController.text.trim();
    if (raw.isEmpty) return;
    // Same-form dedup. The server enforces unique
    // (shop, item, language, alias_text_norm) too.
    final norm = raw.toLowerCase();
    if (_aliases.any((a) => a.toLowerCase() == norm)) {
      _aliasController.clear();
      return;
    }
    setState(() {
      _aliases.add(raw);
      _aliasController.clear();
    });
  }

  void _onRemoveAlias(int index) {
    setState(() => _aliases.removeAt(index));
  }

  Future<void> _onScanPackagingBarcode(_PackagingDraft draft) async {
    final l = tr(context);
    final event = await Scanner.open(context);
    if (event == null || !mounted) return;
    setState(() => draft.barcode = event.code);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.shopItemEditorBarcodeCapturedToast(event.code)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Commits the form. `keepGoing` true keeps the screen mounted and
  /// resets the per-item fields (name, photo, packagings, aliases,
  /// bono spelling) so the shopkeeper can immediately type the next
  /// product without bouncing back to the list. The chosen base unit
  /// + category persist across resets — they're typically the same
  /// for a stocking session ("I'm adding 8 more rice items to my shop").
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

      // Base packaging — if a barcode was scanned, bind it.
      if (basePackaging.barcode != null &&
          basePackaging.barcode!.isNotEmpty) {
        try {
          await api.addShopItemBarcode(
            shopId: widget.shop.id,
            shopItemUnitId: created.defaultShopItemUnitId,
            barcode: basePackaging.barcode!,
          );
        } catch (error, stackTrace) {
          _reportNonFatal(error, stackTrace, 'adding base barcode');
        }
      }

      // Additional packagings (rows 1..n) — each requires unit + conversion.
      for (var i = 1; i < _packagings.length; i++) {
        final p = _packagings[i];
        final unitCode = p.unitCode;
        final conversion = p.parsedConversion;
        if (unitCode == null || conversion == null || conversion <= 0) continue;
        final unitId = await api.createShopItemUnit(
          shopId: widget.shop.id,
          shopItemId: shopItemId,
          unitCode: unitCode,
          conversionToBase: conversion,
          salePrice: p.parsedSalePrice,
        );
        if (p.barcode != null && p.barcode!.isNotEmpty) {
          try {
            await api.addShopItemBarcode(
              shopId: widget.shop.id,
              shopItemUnitId: unitId,
              barcode: p.barcode!,
            );
          } catch (error, stackTrace) {
            _reportNonFatal(error, stackTrace, 'adding extra barcode');
          }
        }
      }

      // Aliases — soft failures; the item save is the headline.
      for (final alias in _aliases) {
        try {
          await api.addShopItemAlias(
            shopId: widget.shop.id,
            shopItemId: shopItemId,
            aliasText: alias,
            languageCode: languageCode,
            isDisplay: false,
            source: 'manual',
          );
        } catch (error, stackTrace) {
          _reportNonFatal(error, stackTrace, 'adding alias');
        }
      }

      // Bono spelling — stored as a plain alias; back-office curation
      // can later distinguish via `source` / weighting heuristics. Tag
      // with `[bono]` prefix so admins can quickly spot the difference
      // until the dedicated field lands.
      final bonoSpelling = _bonoSpellingController.text.trim();
      if (bonoSpelling.isNotEmpty) {
        try {
          await api.addShopItemAlias(
            shopId: widget.shop.id,
            shopItemId: shopItemId,
            aliasText: bonoSpelling,
            languageCode: null,
            isDisplay: false,
            source: 'manual',
          );
        } catch (error, stackTrace) {
          _reportNonFatal(error, stackTrace, 'adding bono spelling alias');
        }
      }

      // Photo upload — best-effort; never blocks the item save.
      final photo = _photo;
      if (photo != null) {
        try {
          final path = await api.uploadShopItemImage(
            shopId: widget.shop.id,
            shopItemId: shopItemId,
            bytes: photo.bytes,
            mimeType: photo.mimeType,
            fileExtension: photo.fileExtension,
          );
          await api.setShopItemImagePath(
            shopId: widget.shop.id,
            shopItemId: shopItemId,
            imagePath: path,
          );
        } catch (error, stackTrace) {
          _reportNonFatal(error, stackTrace, 'uploading item photo');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l.shopItemEditorPhotoUploadFailedToast),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
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

  void _reportNonFatal(Object error, StackTrace stackTrace, String where) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'dukan products onboarding',
      context: ErrorDescription(where),
    ));
  }

  /// Clears per-item form state after a successful "Save & add another".
  /// Keeps base unit + category sticky (typical stocking session pattern);
  /// resets name, photo, packagings, aliases, bono spelling.
  void _resetForNextItem() {
    _nameController.clear();
    _aliasController.clear();
    _bonoSpellingController.clear();
    for (final p in _packagings) {
      p.dispose();
    }
    setState(() {
      _photo = null;
      _aliases.clear();
      _packagings
        ..clear()
        ..add(_PackagingDraft.base());
      _nameMissing = false;
      _baseUnitMissing = false;
    });
    _nameFocusNode.requestFocus();
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
        _PhotoTile(
          photo: _photo,
          onPick: _onPickPhoto,
          onClear: _onClearPhoto,
        ),
        const SizedBox(height: 16),
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
              onScanBarcode: () => _onScanPackagingBarcode(_packagings[i]),
              onClearBarcode: () =>
                  setState(() => _packagings[i].barcode = null),
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
        const SizedBox(height: 24),
        _DiscoverySection(
          aliasController: _aliasController,
          bonoSpellingController: _bonoSpellingController,
          aliases: _aliases,
          onAddAlias: _onAddAlias,
          onRemoveAlias: _onRemoveAlias,
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
  String? barcode;
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

// ----------------------------------------------------------------------------
// Photo tile — Section 1 photo capture affordance.
// ----------------------------------------------------------------------------

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.onPick,
    required this.onClear,
  });

  final PickedBono? photo;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    if (photo == null) {
      return OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.camera_alt_outlined),
        label: Text(l.shopItemEditorAddPhotoButton),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(72),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              photo!.bytes,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.shopItemEditorPhotoCapturedLabel,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: onPick,
            child: Text(l.shopItemEditorRetakePhotoButton),
          ),
          IconButton(
            tooltip: l.shopItemEditorRemovePhotoTooltip,
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Discovery section — collapsible aliases + bono spelling
// ----------------------------------------------------------------------------

class _DiscoverySection extends StatelessWidget {
  const _DiscoverySection({
    required this.aliasController,
    required this.bonoSpellingController,
    required this.aliases,
    required this.onAddAlias,
    required this.onRemoveAlias,
  });

  final TextEditingController aliasController;
  final TextEditingController bonoSpellingController;
  final List<String> aliases;
  final VoidCallback onAddAlias;
  final ValueChanged<int> onRemoveAlias;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // Default collapsed — Section 5 is opt-in. Power users open it
        // for the first item of a stocking session; subsequent items
        // get the same starting state per the plan.
        initiallyExpanded: false,
        title: Text(l.shopItemEditorDiscoveryHeader),
        subtitle: Text(
          l.shopItemEditorDiscoverySubtitle,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              l.shopItemEditorAliasesLabel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(height: 8),
          if (aliases.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var i = 0; i < aliases.length; i++)
                  InputChip(
                    label: Text(aliases[i]),
                    onDeleted: () => onRemoveAlias(i),
                  ),
              ],
            ),
          if (aliases.isNotEmpty) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: aliasController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: l.shopItemEditorAliasHint,
                  ),
                  onSubmitted: (_) => onAddAlias(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: onAddAlias,
                child: Text(l.shopItemEditorAddAliasButton),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l.shopItemEditorAliasHelper,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: bonoSpellingController,
            decoration: InputDecoration(
              labelText: l.shopItemEditorBonoSpellingLabel,
              helperText: l.shopItemEditorBonoSpellingHelper,
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Packaging row — now also captures a per-packaging barcode (optional).
// ----------------------------------------------------------------------------

class _PackagingRow extends StatelessWidget {
  const _PackagingRow({
    required this.draft,
    required this.units,
    required this.baseUnitCode,
    required this.shop,
    required this.onChanged,
    required this.onRemove,
    required this.onScanBarcode,
    required this.onClearBarcode,
  });

  final _PackagingDraft draft;
  final List<UnitOption> units;
  final String? baseUnitCode;
  final ShopSummary shop;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  final VoidCallback onScanBarcode;
  final VoidCallback onClearBarcode;

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
            const SizedBox(height: 12),
            _BarcodeRow(
              barcode: draft.barcode,
              onScan: onScanBarcode,
              onClear: onClearBarcode,
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

class _BarcodeRow extends StatelessWidget {
  const _BarcodeRow({
    required this.barcode,
    required this.onScan,
    required this.onClear,
  });

  final String? barcode;
  final VoidCallback onScan;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    if (barcode == null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: onScan,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(l.shopItemEditorScanBarcodeButton),
        ),
      );
    }
    return Row(
      children: [
        Icon(
          Icons.check_circle,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            l.shopItemEditorBarcodeBoundLabel(barcode!),
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: onScan,
          child: Text(l.shopItemEditorRescanBarcodeButton),
        ),
        IconButton(
          tooltip: l.shopItemEditorRemoveBarcodeTooltip,
          onPressed: onClear,
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    );
  }
}

