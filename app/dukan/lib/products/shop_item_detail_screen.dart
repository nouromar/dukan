// Product (shop-item) detail screen — the single place to view AND edit
// a product. Replaces the legacy detail+editor split; everything that
// used to require the pencil icon (rename, category, threshold, delete
// packaging) is now a tap-to-edit Settings tile on this screen.
//
// Sections, top → bottom:
//   1. ITEM    — Name, Category, Warn below (tappable tiles); Base unit
//                (read-only); stock summary card below.
//   2. PACKAGINGS — per-row tile with price (tap to edit), default-sale
//                   and default-receive FilterChips (tap to toggle),
//                   trash icon (delete; refused server-side on base).
//                   "+ Add packaging" opens the canonical sheet.
//   3. Aliases + barcodes — compact reference sections.
//
// All mutations commit immediately to the server (per-tile save). CREATE
// for new products still lives in ShopItemEditorScreen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/products/stock_adjust_sheet.dart';
import 'package:dukan/receive/add_packaging_sheet.dart';
import 'package:dukan/scanner/scanner_sheet.dart';
import 'package:dukan/shared/display_name.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/low_stock.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/realtime.dart';
import 'package:dukan/shared/stock_format.dart';

class ShopItemDetailScreen extends StatefulWidget {
  const ShopItemDetailScreen({
    required this.shop,
    required this.shopItemId,
    this.displayName,
    super.key,
  });

  final ShopSummary shop;
  final String shopItemId;

  /// Optional pre-fill so the AppBar shows the item name immediately
  /// while the detail fetch is in flight. Once the fetch lands we use
  /// `detail.header.displayName` (which has the alias-chain resolution
  /// applied).
  final String? displayName;

  @override
  State<ShopItemDetailScreen> createState() => _ShopItemDetailScreenState();
}

class _ShopItemDetailScreenState extends State<ShopItemDetailScreen> {
  late Future<_ProductBootstrap> _bootstrapFuture;
  String? _locale;
  String? _liveDisplayName;
  RealtimeWatcher? _watcher;

  @override
  void initState() {
    super.initState();
    // One channel per open detail screen; filters on shop_item.id +
    // child tables filtered by shop_item_id so the cashier's view
    // refetches when an owner edits this exact product on web (or
    // another device).
    _watcher = RealtimeWatcher.tryCreate(
      channelName: 'shop_item_detail:${widget.shopItemId}',
      subscriptions: [
        RealtimeSubscription(
          table: 'shop_item',
          filter: realtimeEq('id', widget.shopItemId),
        ),
        RealtimeSubscription(
          table: 'shop_item_unit',
          filter: realtimeEq('shop_item_id', widget.shopItemId),
        ),
        RealtimeSubscription(
          table: 'shop_item_alias',
          filter: realtimeEq('shop_item_id', widget.shopItemId),
        ),
        RealtimeSubscription(
          table: 'shop_item_barcode',
          filter: realtimeEq('shop_item_id', widget.shopItemId),
        ),
      ],
      onChange: () {
        if (!mounted) return;
        _reload();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = Localizations.localeOf(context).languageCode;
    if (_locale != current) {
      _locale = current;
      _bootstrapFuture = _fetch();
    }
  }

  @override
  void dispose() {
    _watcher?.dispose();
    super.dispose();
  }

  Future<_ProductBootstrap> _fetch() async {
    final api = context.read<ShopApi>();
    // Detail + categories in parallel so the category picker is ready
    // the moment the user taps the tile.
    final detailF = api.getShopItem(
      shopId: widget.shop.id,
      shopItemId: widget.shopItemId,
      locale: _locale,
    );
    final categoriesF = api.listCategories(locale: _locale);
    final results = await Future.wait([detailF, categoriesF]);
    final detail = results[0] as ShopItemDetail;
    _liveDisplayName = detail.header.displayName;
    return _ProductBootstrap(
      detail: detail,
      categories: results[1] as List<CategoryOption>,
    );
  }

  void _reload() {
    setState(() {
      _bootstrapFuture = _fetch();
    });
  }

  Future<void> _onEditPrice(ShopItemUnitDetail unit) async {
    final newPrice = await showDialog<num?>(
      context: context,
      builder: (dialogCtx) => _EditPriceDialog(
        unit: unit,
        shop: widget.shop,
      ),
    );
    if (newPrice == null || !mounted) return;
    final l = tr(context);
    try {
      await context.read<ShopApi>().setShopItemUnitSalePrice(
        shopId: widget.shop.id,
        shopItemUnitId: unit.shopItemUnitId,
        salePrice: newPrice < 0 ? null : newPrice,
      );
      if (!mounted) return;
      _reload();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan products',
          context: ErrorDescription('editing sale price'),
        ),
      );
      if (mounted) showError(context, l.addPackagingFailedMessage);
    }
  }

  /// Toggle either default flag from the detail screen. Persists via
  /// `setShopItemUnitDefaultFlags` (same RPC the editor uses), then
  /// reloads so sibling rows lose their previous-default badge.
  Future<void> _onToggleDefault(
    ShopItemUnitDetail unit, {
    required bool isDefaultSale,
    required bool isDefaultReceive,
  }) async {
    final l = tr(context);
    try {
      await context.read<ShopApi>().setShopItemUnitDefaultFlags(
            shopId: widget.shop.id,
            shopItemUnitId: unit.shopItemUnitId,
            isDefaultSale: isDefaultSale,
            isDefaultReceive: isDefaultReceive,
          );
      if (!mounted) return;
      _reload();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan products',
          context: ErrorDescription('toggling default flag'),
        ),
      );
      if (mounted) showError(context, l.addPackagingFailedMessage);
    }
  }

  Future<void> _onAddPackaging() async {
    final bootstrap = await _bootstrapFuture;
    if (!mounted) return;
    final created = await AddPackagingSheet.show(
      context,
      widget.shop.id,
      widget.shopItemId,
      bootstrap.detail.header.baseUnitCode,
      bootstrap.detail.header.baseUnitLabel,
    );
    if (created == null || !mounted) return;
    _reload();
  }

  /// Tap the big stock readout → opens the adjust sheet (opening /
  /// add / subtract / set exact). Reloads on success.
  Future<void> _onAdjustStock(ShopItemDetail detail) async {
    final ok = await showStockAdjustSheet(
      context,
      shop: widget.shop,
      shopItemId: widget.shopItemId,
      productName: displayName(detail.header.displayName),
      currentStock: detail.header.currentStock,
      baseUnitLabel: detail.header.baseUnitLabel,
    );
    if (ok == true && mounted) _reload();
  }

  /// Add another search alias (not the display alias — rename uses a
  /// different RPC). Opens a small dialog asking for text + language.
  Future<void> _onAddAlias() async {
    final picked = await showDialog<({String text, String? language})>(
      context: context,
      builder: (ctx) => const _AddAliasDialog(),
    );
    if (picked == null || !mounted) return;
    try {
      await context.read<ShopApi>().addShopItemAlias(
            shopId: widget.shop.id,
            shopItemId: widget.shopItemId,
            aliasText: picked.text,
            languageCode: picked.language,
            isDisplay: false,
          );
      if (!mounted) return;
      _reload();
      _showSaved();
    } catch (error, stackTrace) {
      _reportAndShow(error, stackTrace, 'adding alias');
    }
  }

  Future<void> _onRemoveAlias(ShopItemAliasRow alias) async {
    if (alias.isDisplay) return; // server refuses anyway; UI hides the X
    try {
      await context.read<ShopApi>().removeShopItemAlias(
            shopId: widget.shop.id,
            aliasId: alias.aliasId,
          );
      if (!mounted) return;
      _reload();
      _showSaved();
    } catch (error, stackTrace) {
      _reportAndShow(error, stackTrace, 'removing alias');
    }
  }

  Future<void> _onAddBarcode(ShopItemUnitDetail unit) async {
    final picked = await showDialog<({String code, bool primary})>(
      context: context,
      builder: (ctx) => const _AddBarcodeDialog(),
    );
    if (picked == null || !mounted) return;
    try {
      await context.read<ShopApi>().addShopItemBarcode(
            shopId: widget.shop.id,
            shopItemUnitId: unit.shopItemUnitId,
            barcode: picked.code,
            isPrimary: picked.primary,
          );
      if (!mounted) return;
      _reload();
      _showSaved();
    } catch (error, stackTrace) {
      _reportAndShow(error, stackTrace, 'adding barcode');
    }
  }

  /// Scan-to-bind: opens the single-scan viewfinder; on a decode the
  /// resulting code is bound to this packaging via the same
  /// addShopItemBarcode RPC the manual-entry path uses. is_primary
  /// stays false — the cashier can promote later via the existing
  /// chip-action menu.
  Future<void> _onScanBindBarcode(ShopItemUnitDetail unit) async {
    final event = await Scanner.open(context);
    if (event == null || !mounted) return;
    try {
      await context.read<ShopApi>().addShopItemBarcode(
            shopId: widget.shop.id,
            shopItemUnitId: unit.shopItemUnitId,
            barcode: event.code,
            isPrimary: false,
          );
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context).barcodeBoundToPackagingMessage),
        ),
      );
    } catch (error, stackTrace) {
      _reportAndShow(error, stackTrace, 'scan-binding barcode');
    }
  }

  Future<void> _onBarcodeChipTap(ShopItemBarcodeRow row) async {
    final l = tr(context);
    final action = await showModalBottomSheet<_BarcodeAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!row.isPrimary)
              ListTile(
                leading: const Icon(Icons.star_border),
                title: Text(l.barcodeChipMakePrimary),
                onTap: () =>
                    Navigator.of(ctx).pop(_BarcodeAction.makePrimary),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l.barcodeChipRemove),
              onTap: () => Navigator.of(ctx).pop(_BarcodeAction.remove),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      final api = context.read<ShopApi>();
      switch (action) {
        case _BarcodeAction.makePrimary:
          await api.setPrimaryShopItemBarcode(
            shopId: widget.shop.id,
            barcodeId: row.barcodeId,
          );
        case _BarcodeAction.remove:
          await api.removeShopItemBarcode(
            shopId: widget.shop.id,
            barcodeId: row.barcodeId,
          );
      }
      if (!mounted) return;
      _reload();
      _showSaved();
    } catch (error, stackTrace) {
      _reportAndShow(error, stackTrace, 'editing barcode');
    }
  }

  /// Rename — small dialog → addShopItemAlias(isDisplay: true). Updates
  /// the live display name so the AppBar reflects it immediately.
  Future<void> _onRename(String currentName) async {
    final l = tr(context);
    final newName = await _showSingleFieldDialog(
      title: l.shopItemEditorNameLabel,
      initial: currentName,
      keyboardType: TextInputType.text,
    );
    if (newName == null || !mounted) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == currentName) return;
    try {
      await context.read<ShopApi>().addShopItemAlias(
            shopId: widget.shop.id,
            shopItemId: widget.shopItemId,
            aliasText: trimmed,
            languageCode: Localizations.localeOf(context).languageCode,
            isDisplay: true,
          );
      if (!mounted) return;
      setState(() => _liveDisplayName = trimmed);
      _reload();
      _showSaved();
    } catch (error, stackTrace) {
      _reportAndShow(error, stackTrace, 'renaming shop item');
    }
  }

  /// Category change — picker sheet → setShopItemCategory.
  Future<void> _onChangeCategory(
    List<CategoryOption> categories,
    String? currentId,
  ) async {
    final l = tr(context);
    final picked = await showModalBottomSheet<_CategoryPick?>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                l.filterCategoryAny,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
              onTap: () =>
                  Navigator.of(sheetCtx).pop(const _CategoryPick(null)),
            ),
            const Divider(height: 1),
            for (final c in categories)
              ListTile(
                title: Text(c.name),
                trailing: c.id == currentId
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(sheetCtx).pop(_CategoryPick(c)),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final newId = picked.option?.id;
    if (newId == currentId) return;
    try {
      await context.read<ShopApi>().setShopItemCategory(
            shopId: widget.shop.id,
            shopItemId: widget.shopItemId,
            categoryId: newId,
          );
      if (!mounted) return;
      _reload();
      _showSaved();
    } catch (error, stackTrace) {
      _reportAndShow(error, stackTrace, 'changing shop item category');
    }
  }

  /// Reorder threshold — numeric dialog → setShopItemReorderThreshold.
  /// Empty input clears.
  Future<void> _onSetThreshold(num? current) async {
    final l = tr(context);
    final newValue = await _showSingleFieldDialog(
      title: l.shopItemEditorReorderThresholdLabel,
      initial: current == null ? '' : _trimNumber(current),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      digitsOnlyPlusDot: true,
      allowEmpty: true,
    );
    if (newValue == null || !mounted) return;
    final trimmed = newValue.trim();
    final parsed = trimmed.isEmpty ? null : num.tryParse(trimmed);
    if (trimmed.isNotEmpty && (parsed == null || parsed < 0)) return;
    if (parsed == current) return;
    try {
      await context.read<ShopApi>().setShopItemReorderThreshold(
            shopId: widget.shop.id,
            shopItemId: widget.shopItemId,
            reorderThreshold: parsed,
          );
      if (!mounted) return;
      _reload();
      _showSaved();
    } catch (error, stackTrace) {
      _reportAndShow(error, stackTrace, 'setting reorder threshold');
    }
  }

  /// Delete a packaging — confirm dialog → deactivateShopItemUnit.
  Future<void> _onDeletePackaging(ShopItemUnitDetail unit) async {
    final l = tr(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.removePackagingTooltip),
        content: Text(l.removePackagingConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.removePackagingConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<ShopApi>().deactivateShopItemUnit(
            shopId: widget.shop.id,
            shopItemUnitId: unit.shopItemUnitId,
          );
      if (!mounted) return;
      _reload();
      _showSaved();
    } catch (error, stackTrace) {
      _reportAndShow(error, stackTrace, 'deactivating packaging');
    }
  }

  void _showSaved() {
    final l = tr(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.settingsSavedToast)),
    );
  }

  void _reportAndShow(
    Object error,
    StackTrace stackTrace,
    String description,
  ) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'dukan products',
      context: ErrorDescription(description),
    ));
    if (mounted) showError(context, tr(context).addPackagingFailedMessage);
  }

  Future<String?> _showSingleFieldDialog({
    required String title,
    required String initial,
    required TextInputType keyboardType,
    bool digitsOnlyPlusDot = false,
    bool allowEmpty = false,
  }) {
    final controller = TextEditingController(text: initial);
    final l = tr(context);
    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboardType,
          inputFormatters: digitsOnlyPlusDot
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
              : null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text;
              if (!allowEmpty && v.trim().isEmpty) return;
              Navigator.of(dialogCtx).pop(v);
            },
            child: Text(l.shopItemEditorSaveButton),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: dukanAppBar(
        context,
        _liveDisplayName ?? widget.displayName ?? '',
      ),
      body: SafeArea(
        child: FutureBuilder<_ProductBootstrap>(
          future: _bootstrapFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return _ErrorView(onRetry: _reload);
            }
            return _DetailBody(
              bootstrap: snapshot.data!,
              shop: widget.shop,
              onEditPrice: _onEditPrice,
              onAddPackaging: _onAddPackaging,
              onToggleDefault: _onToggleDefault,
              onRename: _onRename,
              onChangeCategory: _onChangeCategory,
              onSetThreshold: _onSetThreshold,
              onDeletePackaging: _onDeletePackaging,
              onAdjustStock: () => _onAdjustStock(snapshot.data!.detail),
              onAddAlias: _onAddAlias,
              onRemoveAlias: _onRemoveAlias,
              onAddBarcode: _onAddBarcode,
              onScanBindBarcode: _onScanBindBarcode,
              onBarcodeChipTap: _onBarcodeChipTap,
            );
          },
        ),
      ),
    );
  }
}

class _ProductBootstrap {
  const _ProductBootstrap({required this.detail, required this.categories});
  final ShopItemDetail detail;
  final List<CategoryOption> categories;
}

class _CategoryPick {
  const _CategoryPick(this.option);
  final CategoryOption? option;
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.bootstrap,
    required this.shop,
    required this.onEditPrice,
    required this.onAddPackaging,
    required this.onToggleDefault,
    required this.onRename,
    required this.onChangeCategory,
    required this.onSetThreshold,
    required this.onDeletePackaging,
    required this.onAdjustStock,
    required this.onAddAlias,
    required this.onRemoveAlias,
    required this.onAddBarcode,
    required this.onScanBindBarcode,
    required this.onBarcodeChipTap,
  });

  final _ProductBootstrap bootstrap;
  final ShopSummary shop;
  final Future<void> Function(ShopItemUnitDetail) onEditPrice;
  final VoidCallback onAddPackaging;
  final Future<void> Function(
    ShopItemUnitDetail unit, {
    required bool isDefaultSale,
    required bool isDefaultReceive,
  }) onToggleDefault;
  final Future<void> Function(String currentName) onRename;
  final Future<void> Function(
      List<CategoryOption> categories, String? currentId) onChangeCategory;
  final Future<void> Function(num? current) onSetThreshold;
  final Future<void> Function(ShopItemUnitDetail unit) onDeletePackaging;
  final VoidCallback onAdjustStock;
  final VoidCallback onAddAlias;
  final Future<void> Function(ShopItemAliasRow alias) onRemoveAlias;
  final Future<void> Function(ShopItemUnitDetail unit) onAddBarcode;
  final Future<void> Function(ShopItemUnitDetail unit) onScanBindBarcode;
  final Future<void> Function(ShopItemBarcodeRow row) onBarcodeChipTap;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final detail = bootstrap.detail;
    final header = detail.header;
    // Sort packagings: base first, then by ascending conversion so the
    // shopkeeper reads them small → large (kg, 25 kg bag, 50 kg sack).
    final units = [...detail.units]..sort((a, b) {
        if (a.isBaseUnit && !b.isBaseUnit) return -1;
        if (!a.isBaseUnit && b.isBaseUnit) return 1;
        return a.conversionToBase.compareTo(b.conversionToBase);
      });
    final aliases = detail.aliases;
    final defaultSale = units.firstWhere(
      (u) => u.isDefaultSale,
      orElse: () => units.firstWhere(
        (u) => u.isBaseUnit,
        orElse: () => units.first,
      ),
    );
    final low = isLowStock(
      currentStock: header.currentStock,
      reorderThreshold: header.reorderThreshold,
    );
    final stockText = formatCompoundStock(
      stock: header.currentStock,
      baseLabel: header.baseUnitLabel,
      packagingLabel:
          defaultSale.isBaseUnit ? null : defaultSale.packagingLabel,
      conversion:
          defaultSale.isBaseUnit ? null : defaultSale.conversionToBase,
    );
    // Capability gates. Cashier role lacks all three — the screen
    // renders as informational: prices and stock visible, every
    // edit affordance is either tap-disabled or hidden.
    final caps = context.watch<AuthController>().capabilities;
    final canEdit = caps.canEditProducts;
    final canAdjustStock = caps.canAdjustStock;
    final canBindBarcode = caps.canBindBarcode;

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
      children: [
        _SectionLabel(text: l.shopItemEditorItemSectionHeader),
        _SettingsTile(
          label: l.shopItemEditorNameLabel,
          value: displayName(header.displayName),
          onTap: canEdit ? () => onRename(header.displayName) : null,
        ),
        _SettingsTile(
          label: l.shopItemEditorCategoryLabel,
          value: header.categoryName?.trim().isNotEmpty == true
              ? header.categoryName!
              : l.other,
          onTap: canEdit
              ? () => onChangeCategory(
                  bootstrap.categories, _categoryIdFor(detail))
              : null,
        ),
        _SettingsTile(
          label: l.shopItemEditorReorderThresholdLabel,
          value: header.reorderThreshold == null
              ? '—'
              : l.shopItemDetailReorderBelowLabel(
                  _trimNumber(header.reorderThreshold!),
                  header.baseUnitLabel,
                ),
          onTap: canEdit ? () => onSetThreshold(header.reorderThreshold) : null,
        ),
        _SettingsTile(
          label: l.shopItemEditorBaseUnitLabel,
          value: header.baseUnitLabel,
          onTap: null,
        ),
        // Big stock readout — tappable opens the adjust sheet; cashier
        // sees the readout without the tap affordance.
        InkWell(
          onTap: canAdjustStock ? onAdjustStock : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    stockText,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: low ? theme.colorScheme.error : null,
                    ),
                  ),
                ),
                if (canAdjustStock)
                  Icon(
                    Icons.tune,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SectionLabel(text: l.shopItemEditorPackagingsHeader),
        for (final u in units) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: _PackagingTile(
              unit: u,
              shop: shop,
              barcodes: detail.barcodes
                  .where((b) => b.shopItemUnitId == u.shopItemUnitId)
                  .toList(growable: false),
              onEditPrice: canEdit ? () => onEditPrice(u) : null,
              onToggleDefault: canEdit
                  ? ({
                      required bool isDefaultSale,
                      required bool isDefaultReceive,
                    }) =>
                      onToggleDefault(
                        u,
                        isDefaultSale: isDefaultSale,
                        isDefaultReceive: isDefaultReceive,
                      )
                  : null,
              onDelete: (canEdit && !u.isBaseUnit)
                  ? () => onDeletePackaging(u)
                  : null,
              onAddBarcode: canBindBarcode ? () => onAddBarcode(u) : null,
              onScanBindBarcode:
                  canBindBarcode ? () => onScanBindBarcode(u) : null,
              onBarcodeChipTap: canBindBarcode ? onBarcodeChipTap : null,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (canEdit)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: onAddPackaging,
              icon: const Icon(Icons.add),
              label: Text(l.shopItemEditorAddPackagingButton),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
          ),
        // Aliases — product-level (not per packaging). Chips with X to
        // remove; star marks the display name (not removable here —
        // change via the Name tile above).
        const SizedBox(height: 16),
        _SectionLabel(text: l.shopItemDetailAliasesHeader),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final a in aliases)
                InputChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (a.isDisplay) ...[
                        Icon(
                          Icons.star,
                          size: 12,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(a.aliasText),
                      if (a.languageCode != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(${a.languageCode})',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Display alias can't be removed inline (the server
                  // refuses; rename via the Name tile updates it).
                  // Cashier loses the × on all chips.
                  onDeleted: (canEdit && !a.isDisplay)
                      ? () => onRemoveAlias(a)
                      : null,
                ),
              if (canEdit)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(l.aliasAddTooltip),
                  onPressed: onAddAlias,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// `ShopItemSummary` doesn't carry the raw category_id — the picker
  /// just needs to highlight the current row, which we approximate by
  /// matching name. Returns null when unknown / "Other".
  String? _categoryIdFor(ShopItemDetail detail) {
    final name = detail.header.categoryName;
    if (name == null || name.trim().isEmpty) return null;
    for (final c in bootstrap.categories) {
      if (c.name == name) return c.id;
    }
    return null;
  }
}

class _PackagingTile extends StatelessWidget {
  const _PackagingTile({
    required this.unit,
    required this.shop,
    required this.barcodes,
    required this.onEditPrice,
    required this.onToggleDefault,
    required this.onDelete,
    required this.onAddBarcode,
    required this.onScanBindBarcode,
    required this.onBarcodeChipTap,
  });

  final ShopItemUnitDetail unit;
  final ShopSummary shop;
  final List<ShopItemBarcodeRow> barcodes;
  /// Null when the caller lacks edit capability — price renders as
  /// a static value with no tap affordance.
  final VoidCallback? onEditPrice;
  /// Null when the caller lacks edit capability — FilterChips render
  /// as static (`onSelected: null` puts them in a disabled state).
  final void Function({
    required bool isDefaultSale,
    required bool isDefaultReceive,
  })? onToggleDefault;

  /// Null for the base packaging OR when the caller lacks edit
  /// capability — the trash icon doesn't render either way.
  final VoidCallback? onDelete;

  /// Both barcode-adding affordances are null when the caller lacks
  /// `inventory.barcode.bind` — the + Add code and Scan code chips
  /// are hidden.
  final VoidCallback? onAddBarcode;
  final VoidCallback? onScanBindBarcode;
  /// Null when bind capability is missing — existing barcode chips
  /// render as static (the action sheet for promote/remove won't
  /// open).
  final Future<void> Function(ShopItemBarcodeRow row)? onBarcodeChipTap;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final price = unit.salePrice;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    unit.packagingLabel,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                InkWell(
                  onTap: onEditPrice,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (price == null)
                          Text(
                            l.shopItemDetailNoPriceLabel,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        else
                          Text(
                            formatMoney(price, shop),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        if (onEditPrice != null) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    tooltip: l.removePackagingTooltip,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: Text(l.shopItemDetailDefaultSaleBadge),
                  selected: unit.isDefaultSale,
                  visualDensity: VisualDensity.compact,
                  onSelected: onToggleDefault == null
                      ? null
                      : (v) => onToggleDefault!(
                            isDefaultSale: v,
                            isDefaultReceive: unit.isDefaultReceive,
                          ),
                ),
                FilterChip(
                  label: Text(l.shopItemDetailDefaultReceiveBadge),
                  selected: unit.isDefaultReceive,
                  visualDensity: VisualDensity.compact,
                  onSelected: onToggleDefault == null
                      ? null
                      : (v) => onToggleDefault!(
                            isDefaultSale: unit.isDefaultSale,
                            isDefaultReceive: v,
                          ),
                ),
              ],
            ),
            // Barcodes inline — the chip IS the SKU. Base packaging
            // (loose / by weight) doesn't show + Add since there's
            // rarely an EAN on bulk; we surface a soft hint instead.
            const SizedBox(height: 6),
            if (unit.isBaseUnit && barcodes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  l.barcodeNoneForBase,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final b in barcodes)
                    ActionChip(
                      avatar: b.isPrimary
                          ? Icon(
                              Icons.star,
                              size: 14,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      label: Text(
                        b.barcode,
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      // Null pressed = disabled chip; cashier sees the
                      // code but can't open the promote/remove menu.
                      onPressed: onBarcodeChipTap == null
                          ? null
                          : () => onBarcodeChipTap!(b),
                    ),
                  if (onAddBarcode != null)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 14),
                      label: Text(l.barcodeAddTooltip),
                      onPressed: onAddBarcode,
                    ),
                  if (onScanBindBarcode != null)
                    ActionChip(
                      avatar: const Icon(Icons.qr_code_scanner, size: 14),
                      label: Text(l.barcodeScanAndBindAction),
                      onPressed: onScanBindBarcode,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EditPriceDialog extends StatefulWidget {
  const _EditPriceDialog({required this.unit, required this.shop});

  final ShopItemUnitDetail unit;
  final ShopSummary shop;

  @override
  State<_EditPriceDialog> createState() => _EditPriceDialogState();
}

class _EditPriceDialogState extends State<_EditPriceDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final initial = widget.unit.salePrice;
    _controller = TextEditingController(
      text: initial == null ? '' : _formatPrice(initial),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatPrice(num value) {
    if (value == value.toInt()) return value.toInt().toString();
    return value.toString();
  }

  void _confirm() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      Navigator.of(context).pop<num?>(-1);
      return;
    }
    final parsed = num.tryParse(raw);
    if (parsed == null || parsed < 0) return;
    Navigator.of(context).pop<num?>(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return AlertDialog(
      title: Text(l.shopItemDetailEditPrice),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.unit.packagingLabel,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              prefixText: '${widget.shop.currencySymbol} ',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop<num?>(null),
          child: Text(l.cartClearConfirmNo),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(l.shopItemEditorSaveButton),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.productsLoadFailedMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(l.tryAgain)),
          ],
        ),
      ),
    );
  }
}

String _trimNumber(num value) {
  final d = value.toDouble();
  if (d == d.roundToDouble()) return d.toStringAsFixed(0);
  return d
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 6),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: onTap == null
                          ? theme.colorScheme.onSurfaceVariant
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

enum _BarcodeAction { makePrimary, remove }

class _AddBarcodeDialog extends StatefulWidget {
  const _AddBarcodeDialog();

  @override
  State<_AddBarcodeDialog> createState() => _AddBarcodeDialogState();
}

class _AddBarcodeDialogState extends State<_AddBarcodeDialog> {
  final _controller = TextEditingController();
  bool _primary = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return AlertDialog(
      title: Text(l.barcodeAddDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(hintText: l.barcodeAddDialogHint),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _primary,
            onChanged: (v) => setState(() => _primary = v ?? false),
            title: Text(l.barcodeAddDialogSetPrimary),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    (code: _controller.text.trim(), primary: _primary),
                  ),
          child: Text(l.shopItemEditorSaveButton),
        ),
      ],
    );
  }
}

class _AddAliasDialog extends StatefulWidget {
  const _AddAliasDialog();

  @override
  State<_AddAliasDialog> createState() => _AddAliasDialogState();
}

class _AddAliasDialogState extends State<_AddAliasDialog> {
  final _controller = TextEditingController();
  // null = "any language" — server keeps the alias language-agnostic
  // and the search RPC will still match across all locales.
  String? _language;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return AlertDialog(
      title: Text(l.aliasAddDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(hintText: l.aliasAddDialogHint),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _language,
            decoration: InputDecoration(labelText: l.aliasAddDialogLanguage),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(l.languageNone),
              ),
              DropdownMenuItem<String?>(value: 'en', child: Text(l.languageEnglish)),
              DropdownMenuItem<String?>(value: 'so', child: Text(l.languageSomali)),
            ],
            onChanged: (v) => setState(() => _language = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    (text: _controller.text.trim(), language: _language),
                  ),
          child: Text(l.shopItemEditorSaveButton),
        ),
      ],
    );
  }
}
