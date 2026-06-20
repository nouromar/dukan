// New-product (shop_item) form screen — CREATE-only. Used from the
// Products FAB and the setup-onboarding "Add my own items" entry.
//
// Form fields per the comprehensive onboarding form plan at
// /Users/nouromar/.claude/plans/linear-fluttering-hartmanis.md:
//
//   Section 1 — Identify (always visible, required):
//     * Photo (optional capture — uploaded to shop-item-images bucket)
//     * Scan barcode (optional — in-shop hit routes to that item's
//       editor; global hit prefills the form; miss leaves the code
//       bound to the base packaging)
//     * Name (required, language-tagged via current locale; debounced
//       search_items inline suggestions: shop-tier ranked first)
//     * Base unit (required, picked from listUnits)
//
//   Section 2 — How you sell it (always visible, mostly required):
//     * Category (optional dropdown)
//     * Packagings: first row is the base packaging (conversion=1, unit
//       locked to the chosen base unit). The cashier can append more
//       packagings; each extra row picks any unit and types its
//       conversion-to-base plus an optional sale price + barcode.
//
//   Section 3 — How you buy it (optional, collapsible):
//     * Default supplier (party picker)
//     * Typical cost per pack — one input per packaging declared
//
//   Section 4 — What you have right now (optional, collapsible):
//     * Opening stock per packaging (converted to base units on save
//       and batched into a single post_inventory_adjustment with
//       reason='opening')
//     * As-of date (defaults to today)
//
//   Section 5 — Help find it faster (optional, collapsible):
//     * Aliases (chip multi-add — extra names a shopkeeper might say)
//     * Bono spelling (single text — how the item appears on supplier
//       bonos)
//     * Per-packaging barcodes live in the packaging rows themselves.
//
// Save dedup soft-warn fires only on the "typed and never tapped a
// suggestion" path. Tapping any inline suggestion (shop or global)
// is an explicit choice — route or prefill silently.
//
// Reorder threshold is intentionally NOT collected — matches the v1
// East-African decision applied to the web inventory list (#312).
//
// Session counter chip in the AppBar surfaces a bottom sheet of items
// added during this editor mount; rows jump to the product detail for
// quick fixes without leaving the editor.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/products/packaging_editor_sheet.dart';
import 'package:dukan/products/shop_item_detail_screen.dart';
import 'package:dukan/products/products_screen.dart';
import 'package:dukan/scanner/scanner_sheet.dart';
import 'package:dukan/shared/add_party_sheet.dart';
import 'package:dukan/shared/bono_image_picker.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/party_picker_sheet.dart';

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

  // ----- Section 1 auto-suggest state ----------------------------------------

  /// Debounce timer for name typing.
  Timer? _suggestDebounce;
  String _lastSuggestionQuery = '';
  List<ItemSearchResult> _suggestions = const [];
  bool _suggestionsLoading = false;

  /// True when the form was populated by an explicit user tap on an
  /// auto-suggestion (global catalog hit) or a barcode prefill. The
  /// save flow uses this to skip the save-time fuzzy dedup warn —
  /// per plan, that dialog only fires on the typed-and-never-tapped
  /// path.
  bool _formPrefilled = false;

  /// Optional banner copy shown above the form after a prefill so the
  /// owner knows the form was auto-populated.
  String? _prefillBanner;

  // ----- Section 3 (How you buy it) state ------------------------------------

  PartySearchResult? _supplier;

  // Opening date field was removed in #348 — it was only ever a UI
  // label ("as of [date]") and was never passed to the RPC; the
  // server's `post_opening_stock_adjustment` always stamps the
  // current timestamp. Earlier-dated opening adjustments are an edge
  // case the shopkeeper handles via the stock-adjust sheet later.

  // ----- Session counter -----------------------------------------------------

  final List<_SessionAdd> _sessionAdds = [];

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
    _suggestDebounce?.cancel();
    for (final p in _packagings) {
      p.dispose();
    }
    super.dispose();
  }

  BonoImagePicker get _imagePicker =>
      _picker ??= widget.imagePicker ??
      DefaultBonoImagePicker(quality: ImageQuality.shopItem);

  Future<_EditorBootstrap> _loadBootstrap() async {
    final api = context.read<ShopApi>();
    final locale = Localizations.localeOf(context).languageCode;
    final units = await api.listUnits();
    final categories = await api.listCategories(locale: locale);
    return _EditorBootstrap(units: units, categories: categories);
  }

  Future<void> _onAddPackaging(_EditorBootstrap bootstrap) async {
    final baseUnit = _baseUnitCode;
    if (baseUnit == null) return; // hidden in UI until base unit picked
    final baseLabel = _unitLabelFor(bootstrap.units, baseUnit) ?? baseUnit;
    final result = await showPackagingEditorSheet(
      context,
      shop: widget.shop,
      units: bootstrap.units,
      baseUnitLabel: baseLabel,
    );
    if (result == null || !mounted) return;
    setState(() {
      final draft = _PackagingDraft.empty();
      _applySubmissionToDraft(draft, result);
      _packagings.add(draft);
    });
  }

  Future<void> _onEditPackaging(
    _EditorBootstrap bootstrap,
    int index,
  ) async {
    if (index == 0) return; // base row is edited inline
    final baseUnit = _baseUnitCode;
    if (baseUnit == null) return;
    final baseLabel = _unitLabelFor(bootstrap.units, baseUnit) ?? baseUnit;
    final draft = _packagings[index];
    final result = await showPackagingEditorSheet(
      context,
      shop: widget.shop,
      units: bootstrap.units,
      baseUnitLabel: baseLabel,
      initial: _draftToSubmission(draft),
    );
    if (result == null || !mounted) return;
    setState(() => _applySubmissionToDraft(draft, result));
  }

  void _onRemovePackaging(int index) {
    if (index == 0) return; // base packaging is non-removable
    final draft = _packagings.removeAt(index);
    draft.dispose();
    setState(() {});
  }

  /// Map a `_PackagingDraft` → sheet input shape (so the sheet can
  /// pre-fill its own controllers without sharing draft state).
  PackagingDraftSubmission? _draftToSubmission(_PackagingDraft draft) {
    final unit = draft.unitCode;
    if (unit == null) return null;
    final conv = draft.parsedConversion;
    if (conv == null) return null;
    return PackagingDraftSubmission(
      unitCode: unit,
      conversion: conv,
      salePrice: draft.parsedSalePrice,
      cost: draft.parsedCost,
      openingStock: draft.parsedOpeningQty,
      barcode: draft.barcode,
    );
  }

  /// Apply a sheet result back onto the parent-owned `_PackagingDraft`.
  /// Writes through the existing controllers so identity is preserved
  /// (no controller churn).
  void _applySubmissionToDraft(
    _PackagingDraft draft,
    PackagingDraftSubmission r,
  ) {
    draft.unitCode = r.unitCode;
    draft.conversionController.text = r.conversion.toString();
    draft.salePriceController.text = r.salePrice?.toString() ?? '';
    draft.costController.text = r.cost?.toString() ?? '';
    draft.openingStockController.text = r.openingStock?.toString() ?? '';
    draft.barcode = r.barcode;
  }

  String? _unitLabelFor(List<UnitOption> units, String code) {
    for (final u in units) {
      if (u.code == code) return u.label;
    }
    return null;
  }

  Future<void> _onPickPhoto() async {
    final l = tr(context);
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

  // --- Section 1: identify (scan + name search + prefill) -------------------

  Future<void> _onSection1Scan() async {
    final l = tr(context);
    final event = await Scanner.open(context);
    if (event == null || !mounted) return;
    final api = context.read<ShopApi>();
    final locale = Localizations.localeOf(context).languageCode;
    final results = await api.searchItems(
      shopId: widget.shop.id,
      query: event.code,
      screen: 'sale',
      locale: locale,
    );
    if (!mounted) return;
    if (results.isEmpty) {
      // Bind the scanned code to the base packaging as a hint and
      // tell the owner we didn't find anything to prefill.
      setState(() => _packagings.first.barcode = event.code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.shopItemEditorBarcodeNoMatchToast(event.code),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final hit = results.first;
    if (hit.isActivated && hit.shopItemId != null) {
      // In-shop hit: it's the same physical product. Route to the
      // existing item's editor — the owner is editing, not creating.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ShopItemDetailScreen(
            shop: widget.shop,
            shopItemId: hit.shopItemId!,
            displayName: hit.displayName,
          ),
        ),
      );
      return;
    }
    // Global catalog hit (not yet in this shop). Auto-prefill — owner
    // can still override anything; SAVE will call ensureShopItem on
    // commit to link the new shop_item to the global catalog.
    _applyPrefillFromSearch(hit, barcode: event.code);
  }

  void _onNameChanged(String value) {
    if (_nameMissing) setState(() => _nameMissing = false);
    // Typing manually invalidates any prior prefill — the owner is
    // typing a NEW name, so we shouldn't claim it was prefilled.
    if (_formPrefilled && _nameController.text != _lastSuggestionQuery) {
      _formPrefilled = false;
      _prefillBanner = null;
    }
    _suggestDebounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _suggestions = const [];
        _suggestionsLoading = false;
      });
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 250), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    setState(() {
      _suggestionsLoading = true;
      _lastSuggestionQuery = query;
    });
    final api = context.read<ShopApi>();
    final locale = Localizations.localeOf(context).languageCode;
    try {
      final results = await api.searchItems(
        shopId: widget.shop.id,
        query: query,
        screen: 'sale',
        locale: locale,
      );
      if (!mounted) return;
      // Drop results if the query has moved on while we were waiting.
      if (query != _nameController.text.trim()) return;
      setState(() {
        _suggestions = results.take(5).toList(growable: false);
        _suggestionsLoading = false;
      });
    } catch (error, stackTrace) {
      _reportNonFatal(error, stackTrace, 'fetching name suggestions');
      if (!mounted) return;
      setState(() {
        _suggestions = const [];
        _suggestionsLoading = false;
      });
    }
  }

  void _onTapSuggestion(ItemSearchResult hit) {
    if (hit.isActivated && hit.shopItemId != null) {
      // Shop hit: route to that item. Editor stays mounted; if owner
      // backs out, the form is still here.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ShopItemDetailScreen(
            shop: widget.shop,
            shopItemId: hit.shopItemId!,
            displayName: hit.displayName,
          ),
        ),
      );
      return;
    }
    // Global catalog hit — apply prefill.
    _applyPrefillFromSearch(hit);
  }

  void _applyPrefillFromSearch(ItemSearchResult hit, {String? barcode}) {
    final l = tr(context);
    setState(() {
      _nameController.text = hit.displayName;
      _baseUnitCode = hit.baseUnitCode;
      _baseUnitMissing = false;
      _nameMissing = false;
      _formPrefilled = true;
      _lastSuggestionQuery = hit.displayName.toLowerCase();
      _suggestions = const [];
      _prefillBanner = l.shopItemEditorPrefillBanner(hit.displayName);
      if (barcode != null) {
        _packagings.first.barcode = barcode;
      }
    });
  }

  void _dismissPrefillBanner() {
    setState(() {
      _prefillBanner = null;
      // Banner dismissal alone doesn't invalidate prefill — owner
      // might just want the chrome out of the way.
    });
  }

  // --- Section 3: supplier picker -------------------------------------------

  Future<void> _onPickSupplier() async {
    final picked = await showPartyPicker(
      context,
      shop: widget.shop,
      typeCode: 'supplier',
    );
    if (picked == null || !mounted) return;
    setState(() => _supplier = picked);
  }

  Future<void> _onAddSupplierInline() async {
    final created = await showAddPartySheet(
      context,
      shopId: widget.shop.id,
      typeCode: 'supplier',
    );
    if (created == null || !mounted) return;
    setState(() => _supplier = created);
  }

  void _onClearSupplier() => setState(() => _supplier = null);

  // --- Session counter sheet ------------------------------------------------

  void _onTapSessionCounter() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SessionAddsSheet(
        shop: widget.shop,
        adds: List.of(_sessionAdds.reversed),
      ),
    );
  }

  // --- Save -----------------------------------------------------------------

  Future<void> _onSave({bool keepGoing = false}) async {
    final l = tr(context);
    final name = _nameController.text.trim();
    final baseUnit = _baseUnitCode;
    setState(() {
      _nameMissing = name.isEmpty;
      _baseUnitMissing = baseUnit == null;
    });
    if (name.isEmpty || baseUnit == null) return;

    // Save-time dedup soft-warn — only fires when the form WAS NOT
    // populated by tapping a suggestion (per the agreed UX). Suggestion-
    // driven saves already had the owner's explicit ack, so we skip
    // the check.
    if (!_formPrefilled) {
      final api = context.read<ShopApi>();
      try {
        final similar = await api.findSimilarShopItems(
          shopId: widget.shop.id,
          query: name,
          baseUnitCode: baseUnit,
        );
        if (similar.isNotEmpty && mounted) {
          final outcome = await _showSoftWarnDialog(similar);
          if (!mounted) return;
          if (outcome == _SoftWarnOutcome.openExisting) {
            // Route to the first match; nothing else to do here.
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => ShopItemDetailScreen(
                  shop: widget.shop,
                  shopItemId: similar.first.shopItemId,
                  displayName: similar.first.displayName,
                ),
              ),
            );
            return;
          }
          if (outcome == _SoftWarnOutcome.cancelled) {
            // User dismissed the dialog without choosing — abort save.
            return;
          }
          // _SoftWarnOutcome.keepGoing falls through to save.
        }
      } catch (error, stackTrace) {
        _reportNonFatal(error, stackTrace, 'find_similar_shop_items');
        // Soft-fail: never block save on a check that itself failed.
      }
    }

    if (!mounted) return;
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
      final baseUnitId = created.defaultShopItemUnitId;

      // Base packaging — if a barcode was scanned, bind it.
      if (basePackaging.barcode != null && basePackaging.barcode!.isNotEmpty) {
        try {
          await api.addShopItemBarcode(
            shopId: widget.shop.id,
            shopItemUnitId: baseUnitId,
            barcode: basePackaging.barcode!,
          );
        } catch (error, stackTrace) {
          _reportNonFatal(error, stackTrace, 'adding base barcode');
        }
      }

      // Supplier cost on the base packaging if the owner entered one.
      final supplier = _supplier;
      final baseCost = basePackaging.parsedCost;
      if (supplier != null && baseCost != null) {
        try {
          await api.setSupplierItemUnitCost(
            shopId: widget.shop.id,
            partyId: supplier.id,
            shopItemUnitId: baseUnitId,
            unitCost: baseCost,
          );
        } catch (error, stackTrace) {
          _reportNonFatal(error, stackTrace, 'set supplier cost (base)');
        }
      }

      // Additional packagings (rows 1..n) — each requires unit + conversion.
      final perUnitIds = <_PackagingDraft, String>{};
      perUnitIds[basePackaging] = baseUnitId;
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
        perUnitIds[p] = unitId;
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
        // Per-packaging supplier cost.
        final cost = p.parsedCost;
        if (supplier != null && cost != null) {
          try {
            await api.setSupplierItemUnitCost(
              shopId: widget.shop.id,
              partyId: supplier.id,
              shopItemUnitId: unitId,
              unitCost: cost,
            );
          } catch (error, stackTrace) {
            _reportNonFatal(
              error,
              stackTrace,
              'set supplier cost (extra)',
            );
          }
        }
      }

      // Opening stock — sum per-packaging base-unit quantities into a
      // single adjustment call with reason='opening'. Compute a
      // weighted-average per-base-unit cost from packagings that have
      // both qty + cost; fall back to 0 when no packaging carried
      // cost data. post_inventory_adjustment requires unit_cost on
      // ANY stock increase regardless of reason (migration
      // 0010_posting_rpcs.sql:1370-1376) — #351 fix: before this we
      // posted without unit_cost and the server silently rejected
      // every onboarding item's opening stock.
      var openingBase = 0.0;
      var openingCostTotal = 0.0;
      for (final entry in perUnitIds.entries) {
        final p = entry.key;
        final qty = p.parsedOpeningQty;
        if (qty == null || qty <= 0) continue;
        final conversion =
            p.isBase ? 1.0 : (p.parsedConversion?.toDouble() ?? 1.0);
        final baseQty = qty.toDouble() * conversion;
        openingBase += baseQty;
        final cost = p.parsedCost;
        if (cost != null && cost > 0) {
          openingCostTotal += qty.toDouble() * cost.toDouble();
        }
      }
      if (openingBase > 0) {
        final avgUnitCost = openingCostTotal / openingBase;
        try {
          await api.postOpeningStockAdjustment(
            shopId: widget.shop.id,
            shopItemId: shopItemId,
            baseQuantity: openingBase,
            unitCost: avgUnitCost,
            notes: l.shopItemEditorOpeningStockNote,
          );
        } catch (error, stackTrace) {
          _reportNonFatal(error, stackTrace, 'opening stock adjustment');
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

      // Bono spelling — stored as a plain alias.
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

      // Record in the session list so the counter chip + sheet reflect
      // it without any re-fetch.
      _sessionAdds.add(
        _SessionAdd(
          shopItemId: shopItemId,
          displayName: name,
          baseUnitCode: baseUnit,
        ),
      );

      if (!mounted) return;
      if (keepGoing) {
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

  Future<_SoftWarnOutcome> _showSoftWarnDialog(
    List<SimilarShopItem> matches,
  ) async {
    final l = tr(context);
    final result = await showDialog<_SoftWarnOutcome>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(l.shopItemEditorDedupTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.shopItemEditorDedupBody),
              const SizedBox(height: 8),
              for (final m in matches.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• ${m.displayName}',
                    style: Theme.of(dialogCtx).textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogCtx).pop(_SoftWarnOutcome.keepGoing),
              child: Text(l.shopItemEditorDedupKeepGoing),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogCtx).pop(_SoftWarnOutcome.openExisting),
              child: Text(l.shopItemEditorDedupOpenExisting),
            ),
          ],
        );
      },
    );
    return result ?? _SoftWarnOutcome.cancelled;
  }

  void _reportNonFatal(Object error, StackTrace stackTrace, String where) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'dukan products onboarding',
      context: ErrorDescription(where),
    ));
  }

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
      _formPrefilled = false;
      _prefillBanner = null;
      _suggestions = const [];
      _lastSuggestionQuery = '';
      // Supplier sticks across resets — typical stocking session.
    });
    _nameFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(
        context,
        l.shopItemEditorTitleCreate,
        actions: [
          if (_sessionAdds.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _SessionCounterChip(
                count: _sessionAdds.length,
                onTap: _onTapSessionCounter,
              ),
            ),
        ],
      ),
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
    final baseUnitLabel = _baseUnitCode == null
        ? null
        : _unitLabelFor(units, _baseUnitCode!);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        if (_prefillBanner != null)
          _PrefillBanner(
            text: _prefillBanner!,
            onDismiss: _dismissPrefillBanner,
          ),
        if (_prefillBanner != null) const SizedBox(height: 12),
        // ---- Card 1: Identify (no header — most-visible content is
        // self-explanatory). Carries Photo, Name, Base unit, Category.
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Photo + Scan layout:
              //   * Both empty (the common opening state): one compact
              //     row of two equal-width 56 px buttons — saves
              //     ~80 px of vertical chrome before the Name field.
              //   * Either set: fall back to a two-row layout where
              //     the captured side renders as a full-width preview
              //     strip (thumbnail / barcode + Retake + ✕).
              // The empty side keeps the full-width compact button so
              // the row heights stay aligned.
              () {
                final hasPhoto = _photo != null;
                final hasBarcode = _packagings.first.barcode != null &&
                    _packagings.first.barcode!.isNotEmpty;
                if (!hasPhoto && !hasBarcode) {
                  return Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _onPickPhoto,
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: Text(l.shopItemEditorAddPhotoButton),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _onSection1Scan,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(l.shopItemEditorScanIdentifyButton),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasPhoto)
                      _PhotoTile(
                        photo: _photo,
                        onPick: _onPickPhoto,
                        onClear: _onClearPhoto,
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _onPickPhoto,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: Text(l.shopItemEditorAddPhotoButton),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (hasBarcode)
                      _BarcodeTile(
                        barcode: _packagings.first.barcode!,
                        onScan: _onSection1Scan,
                        onClear: () => setState(
                          () => _packagings.first.barcode = null,
                        ),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _onSection1Scan,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: Text(l.shopItemEditorScanIdentifyButton),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                      ),
                  ],
                );
              }(),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                focusNode: _nameFocusNode,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l.shopItemEditorNameLabel,
                  errorText:
                      _nameMissing ? l.addNewItemMissingNameMessage : null,
                  suffixIcon: _suggestionsLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                onChanged: _onNameChanged,
              ),
              if (_suggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _SuggestionList(
                    suggestions: _suggestions,
                    onTap: _onTapSuggestion,
                  ),
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
              // Category lives in the first card directly after Base
              // unit — they're both item-level descriptors. Supplier /
              // packagings (sales + purchasing concerns) stay in the
              // Packaging card below.
              DropdownButtonFormField<String?>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l.shopItemEditorCategoryLabel,
                ),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(l.other)),
                  for (final c in bootstrap.categories)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.name),
                    ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ---- Card 2: Packaging ----------------------------------------
        _SectionCard(
          title: l.shopItemEditorPackagingHeader,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InlineSupplierPicker(
                supplier: _supplier,
                onPick: _onPickSupplier,
                onAddInline: _onAddSupplierInline,
                onClear: _onClearSupplier,
              ),
              const SizedBox(height: 16),
              // BASE packaging — inline compact strip. Other packagings
              // are summary rows below; both fold supplier-cost +
              // opening-stock into the per-packaging editing surface
              // (the old Section 3 / Section 4 are gone).
              _BasePackagingStrip(
                draft: _packagings.first,
                baseUnitLabel: baseUnitLabel,
                shop: widget.shop,
                onChanged: () => setState(() {}),
                onScanBarcode: () =>
                    _onScanPackagingBarcode(_packagings.first),
                onClearBarcode: () => setState(
                  () => _packagings.first.barcode = null,
                ),
              ),
              for (var i = 1; i < _packagings.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _PackagingSummaryRow(
                    draft: _packagings[i],
                    units: units,
                    shop: widget.shop,
                    onEdit: () => _onEditPackaging(bootstrap, i),
                    onRemove: () => _onRemovePackaging(i),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _baseUnitCode == null
                    ? null
                    : () => _onAddPackaging(bootstrap),
                icon: const Icon(Icons.add),
                label: Text(l.shopItemEditorAddPackagingButton),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ---- Card 3: Aliases (collapsible) -----------------------------
        _DiscoverySection(
          aliasController: _aliasController,
          bonoSpellingController: _bonoSpellingController,
          aliases: _aliases,
          onAddAlias: _onAddAlias,
          onRemoveAlias: _onRemoveAlias,
          initiallyExpanded: false,
        ),
        const SizedBox(height: 32),
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

// ----------------------------------------------------------------------------
// Data shapes
// ----------------------------------------------------------------------------

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
            TextEditingController(text: salePriceInitial),
        costController = TextEditingController(),
        openingStockController = TextEditingController();

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
  final TextEditingController costController;
  final TextEditingController openingStockController;

  num? get parsedConversion {
    final raw = conversionController.text.trim();
    return raw.isEmpty ? null : num.tryParse(raw);
  }

  num? get parsedSalePrice {
    final raw = salePriceController.text.trim();
    return raw.isEmpty ? null : num.tryParse(raw);
  }

  num? get parsedCost {
    final raw = costController.text.trim();
    return raw.isEmpty ? null : num.tryParse(raw);
  }

  num? get parsedOpeningQty {
    final raw = openingStockController.text.trim();
    return raw.isEmpty ? null : num.tryParse(raw);
  }

  void dispose() {
    conversionController.dispose();
    salePriceController.dispose();
    costController.dispose();
    openingStockController.dispose();
  }
}

class _SessionAdd {
  const _SessionAdd({
    required this.shopItemId,
    required this.displayName,
    required this.baseUnitCode,
  });

  final String shopItemId;
  final String displayName;
  final String baseUnitCode;
}

enum _SoftWarnOutcome { openExisting, keepGoing, cancelled }

// ----------------------------------------------------------------------------
// AppBar session-counter chip
// ----------------------------------------------------------------------------

class _SessionCounterChip extends StatelessWidget {
  const _SessionCounterChip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.list_alt,
              size: 18,
              color: theme.colorScheme.onPrimary,
            ),
            const SizedBox(width: 6),
            Text(
              l.shopItemEditorSessionCounter(count),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Prefill banner — shown after a global-catalog match populates the form.
// ----------------------------------------------------------------------------

class _PrefillBanner extends StatelessWidget {
  const _PrefillBanner({required this.text, required this.onDismiss});

  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4, top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome,
            color: theme.colorScheme.onPrimaryContainer,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: Icon(
              Icons.close,
              size: 18,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Section 1 — Name suggestion list
// ----------------------------------------------------------------------------

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.suggestions, required this.onTap});

  final List<ItemSearchResult> suggestions;
  final void Function(ItemSearchResult) onTap;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    // Shop matches rise to the top so familiarity wins.
    final ordered = [...suggestions]..sort((a, b) {
        if (a.isActivated == b.isActivated) return 0;
        return a.isActivated ? -1 : 1;
      });
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(8),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final hit in ordered)
            InkWell(
              onTap: () => onTap(hit),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      hit.isActivated
                          ? Icons.store
                          : Icons.public,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hit.displayName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            hit.isActivated
                                ? l.shopItemEditorSuggestionInShop
                                : l.shopItemEditorSuggestionInCatalog,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      hit.isActivated
                          ? Icons.arrow_forward
                          : Icons.auto_awesome,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
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
              width: 56,
              height: 56,
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
// Barcode tile — Section 1 scan affordance mirroring _PhotoTile so the
// captured state surfaces the scanned code with a Retake + ✕ row
// (instead of the older silent "code captured" toast).
// ----------------------------------------------------------------------------

class _BarcodeTile extends StatelessWidget {
  const _BarcodeTile({
    required this.barcode,
    required this.onScan,
    required this.onClear,
  });

  final String barcode;
  final VoidCallback onScan;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.qr_code_scanner,
              color: theme.colorScheme.onPrimaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              barcode,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
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
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Card shell — wraps Identify + Packaging in Cards that match the
// always-expanded "section" styling. Aliases keeps its own
// ExpansionTile-in-Card (collapsible) widget below.
// ----------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({this.title, required this.child});

  /// When null, the Card renders just the child (no header). Used by
  /// the first card (was "Identify") which carries the most-visible
  /// content — Photo, Name, Base unit, Category — and reads cleaner
  /// without a redundant title above it.
  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: title == null
            ? const EdgeInsets.fromLTRB(16, 16, 16, 16)
            : const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Supplier picker — extracted from the old _SupplierSection. Sits
// inside the Packaging card now; per-packaging cost moved into each
// packaging row's editor sheet (and the BASE strip's inline fields).
// ----------------------------------------------------------------------------

class _InlineSupplierPicker extends StatelessWidget {
  const _InlineSupplierPicker({
    required this.supplier,
    required this.onPick,
    required this.onAddInline,
    required this.onClear,
  });

  final PartySearchResult? supplier;
  final VoidCallback onPick;
  final VoidCallback onAddInline;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    if (supplier == null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.search),
              label: Text(l.shopItemEditorPickSupplierButton),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: onAddInline,
            icon: const Icon(Icons.add),
            label: Text(l.shopItemEditorNewSupplierButton),
          ),
        ],
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.local_shipping),
      title: Text(supplier!.name),
      trailing: IconButton(
        tooltip: l.shopItemEditorRemoveSupplierTooltip,
        onPressed: onClear,
        icon: const Icon(Icons.close),
      ),
      onTap: onPick,
    );
  }
}

// ----------------------------------------------------------------------------
// BASE packaging — inline compact strip. Unit + conversion are
// derived from the Identify card's Base unit choice and locked at 1,
// so they're not rendered here. Only sale price + cost + stock +
// barcode are editable. Mirrors the post-refactor "fold Stock +
// Suppliers into Packaging" decision: every packaging row carries
// its own pricing, sourcing, and inventory data — no separate
// sections.
// ----------------------------------------------------------------------------

class _BasePackagingStrip extends StatelessWidget {
  const _BasePackagingStrip({
    required this.draft,
    required this.baseUnitLabel,
    required this.shop,
    required this.onChanged,
    required this.onScanBarcode,
    required this.onClearBarcode,
  });

  final _PackagingDraft draft;
  final String? baseUnitLabel;
  final ShopSummary shop;
  final VoidCallback onChanged;
  final VoidCallback onScanBarcode;
  final VoidCallback onClearBarcode;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final label = baseUnitLabel ?? '—';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l.shopItemEditorBaseBadge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '1 $label',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: draft.salePriceController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: l.shopItemEditorBaseSaleLabel(label),
              prefixText: '${shop.currencySymbol} ',
              isDense: true,
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: draft.costController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: l.shopItemEditorBaseCostLabel(label),
              prefixText: '${shop.currencySymbol} ',
              isDense: true,
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: draft.openingStockController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: l.shopItemEditorBaseStockLabel(label),
              isDense: true,
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          _BarcodeRow(
            barcode: draft.barcode,
            onScan: onScanBarcode,
            onClear: onClearBarcode,
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Summary row for a non-base packaging. Read-only display of the
// editor sheet's payload; tap → reopens the sheet pre-filled.
// ----------------------------------------------------------------------------

class _PackagingSummaryRow extends StatelessWidget {
  const _PackagingSummaryRow({
    required this.draft,
    required this.units,
    required this.shop,
    required this.onEdit,
    required this.onRemove,
  });

  final _PackagingDraft draft;
  final List<UnitOption> units;
  final ShopSummary shop;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  String _unitLabel() {
    final code = draft.unitCode;
    if (code == null) return '—';
    for (final u in units) {
      if (u.code == code) return u.label;
    }
    return code;
  }

  String _moneyOrEmpty(num? value, ShopSummary shop, AppLocalizations l) {
    if (value == null) return l.shopItemEditorPackagingSummaryEmpty;
    return '${shop.currencySymbol}${value.toStringAsFixed(2)}';
  }

  String _stockOrEmpty(num? value, AppLocalizations l) {
    if (value == null) return l.shopItemEditorPackagingSummaryEmpty;
    final asInt = value.toInt();
    return value == asInt ? '$asInt' : value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final summary = l.shopItemEditorPackagingSummary(
      _moneyOrEmpty(draft.parsedSalePrice, shop, l),
      _moneyOrEmpty(draft.parsedCost, shop, l),
      _stockOrEmpty(draft.parsedOpeningQty, l),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onEdit,
        title: Text(
          _unitLabel(),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary),
            if (draft.barcode != null && draft.barcode!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  draft.barcode!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: l.shopItemEditorEditPackagingTooltip,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: l.shopItemEditorRemovePackagingTooltip,
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Section 5 — Discovery (aliases + bono spelling).
// ----------------------------------------------------------------------------

class _DiscoverySection extends StatelessWidget {
  const _DiscoverySection({
    required this.aliasController,
    required this.bonoSpellingController,
    required this.aliases,
    required this.onAddAlias,
    required this.onRemoveAlias,
    required this.initiallyExpanded,
  });

  final TextEditingController aliasController;
  final TextEditingController bonoSpellingController;
  final List<String> aliases;
  final VoidCallback onAddAlias;
  final ValueChanged<int> onRemoveAlias;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(
          l.shopItemEditorDiscoveryHeader,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _SectionSubtitle(text: l.shopItemEditorDiscoverySubtitle),
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
// Barcode row — small affordance shared by the BASE strip inline.
// Other packagings edit barcode via the packaging editor sheet instead.
// ----------------------------------------------------------------------------

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

// ----------------------------------------------------------------------------
// Session adds — bottom sheet.
// ----------------------------------------------------------------------------

class _SessionAddsSheet extends StatelessWidget {
  const _SessionAddsSheet({required this.shop, required this.adds});

  final ShopSummary shop;
  final List<_SessionAdd> adds;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l.shopItemEditorSessionSheetTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: adds.length,
                itemBuilder: (_, i) {
                  final add = adds[i];
                  return ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(add.displayName),
                    subtitle: Text(add.baseUnitCode),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ShopItemDetailScreen(
                            shop: shop,
                            shopItemId: add.shopItemId,
                            displayName: add.displayName,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => ProductsScreen(shop: shop),
                  ),
                );
              },
              child: Text(l.shopItemEditorSessionSheetViewAll),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiny helper rendered as the FIRST child inside each optional
/// section's ExpansionTile. ExpansionTile.subtitle would always
/// render (even when collapsed) — placing the same copy inside
/// `children` makes it visible only when expanded, which keeps the
/// collapsed header tight.
class _SectionSubtitle extends StatelessWidget {
  const _SectionSubtitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
