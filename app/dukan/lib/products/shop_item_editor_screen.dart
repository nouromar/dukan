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

  // ----- Section 4 (Opening stock) state -------------------------------------

  DateTime _openingDate = DateTime.now();

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

  // --- Section 4: opening date ----------------------------------------------

  Future<void> _onPickOpeningDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _openingDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _openingDate = picked);
  }

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
      // single adjustment call with reason='opening'.
      var openingBase = 0.0;
      for (final entry in perUnitIds.entries) {
        final p = entry.key;
        final qty = p.parsedOpeningQty;
        if (qty == null || qty <= 0) continue;
        final conversion =
            p.isBase ? 1.0 : (p.parsedConversion?.toDouble() ?? 1.0);
        openingBase += qty.toDouble() * conversion;
      }
      if (openingBase > 0) {
        try {
          await api.postOpeningStockAdjustment(
            shopId: widget.shop.id,
            shopItemId: shopItemId,
            baseQuantity: openingBase,
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
      _openingDate = DateTime.now();
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
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        if (_prefillBanner != null)
          _PrefillBanner(
            text: _prefillBanner!,
            onDismiss: _dismissPrefillBanner,
          ),
        if (_prefillBanner != null) const SizedBox(height: 12),
        _PhotoTile(
          photo: _photo,
          onPick: _onPickPhoto,
          onClear: _onClearPhoto,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _onSection1Scan,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(l.shopItemEditorScanIdentifyButton),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          focusNode: _nameFocusNode,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l.shopItemEditorNameLabel,
            errorText: _nameMissing ? l.addNewItemMissingNameMessage : null,
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
          style: theme.textTheme.titleMedium,
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
        const SizedBox(height: 16),
        _SupplierSection(
          shop: widget.shop,
          packagings: _packagings,
          supplier: _supplier,
          initiallyExpanded: false,
          onPick: _onPickSupplier,
          onAddInline: _onAddSupplierInline,
          onClear: _onClearSupplier,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 12),
        _OpeningStockSection(
          packagings: _packagings,
          baseUnitCode: _baseUnitCode,
          openingDate: _openingDate,
          onPickDate: _onPickOpeningDate,
          initiallyExpanded: false,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 12),
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
// Section 3 — Supplier picker + per-packaging typical cost.
// ----------------------------------------------------------------------------

class _SupplierSection extends StatelessWidget {
  const _SupplierSection({
    required this.shop,
    required this.packagings,
    required this.supplier,
    required this.initiallyExpanded,
    required this.onPick,
    required this.onAddInline,
    required this.onClear,
    required this.onChanged,
  });

  final ShopSummary shop;
  final List<_PackagingDraft> packagings;
  final PartySearchResult? supplier;
  final bool initiallyExpanded;
  final VoidCallback onPick;
  final VoidCallback onAddInline;
  final VoidCallback onClear;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(
          l.shopItemEditorBuyHeader,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _SectionSubtitle(text: l.shopItemEditorBuySubtitle),
          if (supplier == null)
            Row(
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
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.local_shipping),
              title: Text(supplier!.name),
              trailing: IconButton(
                tooltip: l.shopItemEditorRemoveSupplierTooltip,
                onPressed: onClear,
                icon: const Icon(Icons.close),
              ),
              onTap: onPick,
            ),
          if (supplier != null) const SizedBox(height: 8),
          if (supplier != null)
            Text(
              l.shopItemEditorTypicalCostHeader,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          if (supplier != null) const SizedBox(height: 4),
          if (supplier != null)
            for (final p in packagings)
              if (p.unitCode != null || p.isBase)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: p.costController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: l.shopItemEditorCostPerPackLabel(
                        _packagingDescription(p),
                      ),
                      prefixText: '${shop.currencySymbol} ',
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
        ],
      ),
    );
  }

  String _packagingDescription(_PackagingDraft p) {
    if (p.isBase) return '1 ${p.unitCode ?? '?'}';
    final conv = p.parsedConversion;
    final code = p.unitCode ?? '?';
    return conv == null ? code : '$conv per $code';
  }
}

// ----------------------------------------------------------------------------
// Section 4 — Opening stock per packaging.
// ----------------------------------------------------------------------------

class _OpeningStockSection extends StatelessWidget {
  const _OpeningStockSection({
    required this.packagings,
    required this.baseUnitCode,
    required this.openingDate,
    required this.onPickDate,
    required this.initiallyExpanded,
    required this.onChanged,
  });

  final List<_PackagingDraft> packagings;
  final String? baseUnitCode;
  final DateTime openingDate;
  final VoidCallback onPickDate;
  final bool initiallyExpanded;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final dateLabel = MaterialLocalizations.of(context)
        .formatMediumDate(openingDate);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(
          l.shopItemEditorOpeningHeader,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _SectionSubtitle(text: l.shopItemEditorOpeningSubtitle),
          if (baseUnitCode == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                l.shopItemEditorOpeningPickBaseUnitFirst,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final p in packagings)
              if (p.unitCode != null || p.isBase)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: p.openingStockController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: l.shopItemEditorOpeningQtyLabel(
                        p.unitCode ?? baseUnitCode ?? '?',
                      ),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.shopItemEditorOpeningAsOf(dateLabel),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: onPickDate,
                child: Text(l.shopItemEditorChangeDateButton),
              ),
            ],
          ),
        ],
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
// Packaging row — captures sale price + optional barcode per packaging.
// Cost + opening stock are captured in their respective sections so the
// row stays scannable for the daily use case (most rows have just price).
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
