// Sale screen — v2 picker on top of `search_items`, cart bottom strip,
// optimistic SAVE → post_sale.
//
// Negative-stock toast (T#149): post_sale raises a Postgres NOTICE when
// a line drives a shop_item.current_stock below zero. The Supabase Dart
// client does not surface those notices, so we sample the post-decrement
// stock client-side instead. After a successful post we call the
// existing `getShopItem` RPC once per unique shop_item in the just-posted
// cart, filter to rows with `current_stock < 0`, and queue an orange
// SnackBar per negative row (capped at 3 with a "+ N more" tail).
//
// We deliberately chose the existing-RPC route over adding a new
// `get_shop_item_stocks` SQL function: zero migration touch, zero
// new ShopApi surface, and v1 carts are small (typical sale is 1–5
// unique items). Once carts get larger or we start chasing extra
// round-trips for telemetry, a dedicated stocks RPC is the obvious
// next step — see data-model-v2 §8.5.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/sale/add_new_item_sheet.dart';
import 'package:dukan/sale/cart_controller.dart';
import 'package:dukan/receive/unit_picker_sheet.dart';
import 'package:dukan/sale/line_editor_sheet.dart';
import 'package:dukan/sale/sale_detail_screen.dart';
import 'package:dukan/sale/sale_history_screen.dart';
import 'package:dukan/observability/timing.dart';
import 'package:dukan/scanner/hid_listener.dart';
import 'package:dukan/scanner/scan_event.dart';
import 'package:dukan/scanner/scanner_settings.dart';
import 'package:dukan/scanner/scanner_sheet.dart';
import 'package:dukan/shared/party_picker_sheet.dart';
import 'package:dukan/shared/display_name.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/favorites_cache.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/low_stock.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/quantity_format.dart';
import 'package:dukan/shared/stock_format.dart';

class SaleScreen extends StatefulWidget {
  const SaleScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  final _searchController = TextEditingController();
  late Future<List<ItemSearchResult>> _resultsFuture;
  String _activeQuery = '';
  Timer? _debounce;
  bool _saving = false;
  bool _activating = false;
  bool _cartExpanded = false;
  final _random = math.Random();
  String? _locale;
  String? _unknownScan;
  late final HidScanListener _hidListener;

  @override
  void initState() {
    super.initState();
    // Auto-expand the drawer when reopening the Sale screen with a
    // non-empty cart: the cashier needs to see at a glance whether the
    // existing items are theirs to continue or a stale cart to clear.
    _cartExpanded = context.read<CartController>().isNotEmpty;
    // Detect Bluetooth-HID scanners typing burst-style. isActive gates
    // dispatch to the route currently visible — handles the case where
    // Sale is pushed under another screen.
    final scanner = ScannerSettings.current;
    _hidListener = HidScanListener(
      onScan: _onHidScan,
      isActive: () =>
          mounted && (ModalRoute.of(context)?.isCurrent ?? false),
      maxInterKeyGap: scanner.hidMaxInterKeyGap,
      maxBurstWindow: scanner.hidMaxBurstWindow,
      minBurstLength: scanner.hidMinBurstLength,
    )..attach();
  }

  void _onHidScan(ScanEvent event) {
    // HID bursts populate the focused text field as they type, so the
    // search bar now holds the code. Clear it before dispatching so the
    // search-result strip doesn't briefly render against the burst.
    _searchController.clear();
    _debounce?.cancel();
    setState(() {
      _activeQuery = '';
      _resultsFuture = _fetchWithCache('');
    });
    _handleScan(event);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = Localizations.localeOf(context).languageCode;
    if (_locale != current) {
      _locale = current;
      _resultsFuture = _fetchWithCache(_activeQuery);
    }
  }

  @override
  void dispose() {
    _hidListener.detach();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// For the blank query (favorites strip), consult FavoritesCache —
  /// the Today card on Home prefetches into it, so Sale entry feels
  /// instant. Stale entries still serve immediately; a background
  /// refresh updates the cache for the next visit. Any non-blank
  /// query bypasses the cache and fetches normally.
  Future<List<ItemSearchResult>> _fetchWithCache(String query) {
    if (query.isNotEmpty) return _fetch(query);
    final cached = FavoritesCache.get(widget.shop.id, 'sale');
    if (cached != null) {
      if (FavoritesCache.isStale(widget.shop.id, 'sale')) {
        unawaited(_refreshFavoritesInBackground());
      }
      return Future.value(cached);
    }
    return _fetch('').then((rows) {
      FavoritesCache.put(widget.shop.id, 'sale', rows);
      return rows;
    });
  }

  Future<void> _refreshFavoritesInBackground() async {
    try {
      final fresh = await _fetch('');
      if (!mounted) return;
      FavoritesCache.put(widget.shop.id, 'sale', fresh);
      // Update the visible list if the cashier is still on the blank
      // query — they'll see a quiet swap from cached to fresh.
      if (_activeQuery.isEmpty) {
        setState(() {
          _resultsFuture = Future.value(fresh);
        });
      }
    } catch (_) {
      // Refresh is best-effort.
    }
  }

  Future<List<ItemSearchResult>> _fetch(String query) {
    return context.read<ShopApi>().searchItems(
      shopId: widget.shop.id,
      query: query,
      screen: 'sale',
      locale: Localizations.localeOf(context).languageCode,
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _activeQuery = value.trim();
        _resultsFuture = _fetchWithCache(_activeQuery);
      });
    });
  }

  // Tap routes for a search-result tile:
  //   * activated + priced  → fast-path add (the v1 speed contract).
  //   * activated + no price → editor in price-required mode.
  //   * unactivated catalog  → ensureShopItem first, refresh the row,
  //                            then re-route by the now-resolved row.
  //
  // Treating sale price == 0 the same as null is intentional; the cashier
  // can still confirm a free sale by typing 0 explicitly inside the
  // editor.
  Future<void> _onTapTile(ItemSearchResult item) async {
    if (_isActivated(item)) {
      if (_isNoPrice(item)) {
        await _openEditorForTile(item, priceRequired: true);
      } else {
        context.read<CartController>().addItem(item);
        _expandCart();
      }
      return;
    }
    // Unactivated catalog item — activate, then re-route.
    final activated = await _activateAndRefresh(item);
    if (activated == null || !mounted) return;
    if (_isNoPrice(activated)) {
      await _openEditorForTile(activated, priceRequired: true);
    } else {
      context.read<CartController>().addItem(activated);
      _expandCart();
    }
  }

  /// Auto-expand the cart strip whenever a line is added so the cashier
  /// always sees the running total + last line — eliminates the
  /// "did the tap register?" anxiety with the drawer collapsed.
  void _expandCart() {
    if (!mounted || _cartExpanded) return;
    setState(() => _cartExpanded = true);
  }

  /// Camera-icon entry point. Opens the single-scan viewfinder; on a
  /// decoded ScanEvent, runs the same search_items lookup the typed
  /// search bar uses, then routes by match count. See docs/scanner.md §7.
  Future<void> _onScanTap() async {
    final event = await Scanner.open(context);
    if (event == null || !mounted) return;
    await _handleScan(event);
  }

  Future<void> _handleScan(ScanEvent event) async {
    try {
      // Reuse the search_items pipeline so an alias-matched barcode,
      // a global-catalog match, and a shop_item_barcode hit all land
      // in the same dispatch logic.
      final results = await context.read<ShopApi>().searchItems(
        shopId: widget.shop.id,
        query: event.code,
        screen: 'sale',
        locale: Localizations.localeOf(context).languageCode,
      );
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() => _unknownScan = event.code);
        return;
      }
      // Matched: dismiss any stale unknown pill, then route as if the
      // first result were tapped. Multi-match is rare (barcodes are
      // unique per shop) — picking the first preserves the speed
      // contract; a v2 disambiguation sheet covers the edge case.
      setState(() => _unknownScan = null);
      await _onTapTile(results.first);
    } catch (error, stackTrace) {
      if (!mounted) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan scanner',
          context: ErrorDescription('scan lookup for ${event.code}'),
        ),
      );
      showError(context, tr(context).scanLookupFailed);
    }
  }

  /// "Create new" action on the unknown-barcode pill. Opens the
  /// add-new-item sheet so the owner can create a product; the
  /// scanned code is NOT auto-bound in Phase 1 (binding flow ships
  /// with Product-detail scan in a later phase). The owner binds the
  /// code from Product detail after creating the item.
  Future<void> _onCreateFromUnknown() async {
    // Reuse the same path as the search-bar "+ Add new" entry. Empty
    // initial name so the owner sees a clean form (the scanned code
    // would be unreadable as a product name).
    await _onAddNewItem('');
    if (!mounted) return;
    setState(() => _unknownScan = null);
  }

  Future<void> _onLongPressTile(ItemSearchResult item) async {
    if (!_isActivated(item)) {
      final activated = await _activateAndRefresh(item);
      if (activated == null || !mounted) return;
      await _openEditorForTile(activated, priceRequired: _isNoPrice(activated));
      return;
    }
    await _openEditorForTile(item, priceRequired: _isNoPrice(item));
  }

  /// Returns true when the row already has a shop_item + default
  /// packaging — i.e., addItem is safe to call without ensureShopItem.
  bool _isActivated(ItemSearchResult item) =>
      item.shopItemId != null && item.defaultShopItemUnitId != null;

  /// Activates a catalog item for this shop and re-fetches the search
  /// row so its `shopItemId` / `defaultShopItemUnitId` are populated.
  /// Returns null on failure (toast already shown). The "Activating..."
  /// spinner is gated by `_activating` so the same row can't be
  /// double-tapped.
  Future<ItemSearchResult?> _activateAndRefresh(ItemSearchResult item) async {
    if (_activating) return null;
    final itemId = item.itemId;
    if (itemId == null) return null;
    setState(() => _activating = true);
    final api = context.read<ShopApi>();
    final l = tr(context);
    try {
      final shopItemId = await api.ensureShopItem(
        shopId: widget.shop.id,
        itemId: itemId,
      );
      // Pull the default sale packaging for this newly activated item.
      // listShopItemUnits with screen='sale' marks the default we need.
      final units = await api.listShopItemUnits(
        shopId: widget.shop.id,
        shopItemId: shopItemId,
        screen: 'sale',
      );
      if (units.isEmpty) {
        if (mounted) showError(context, l.saleLoadFailedMessage);
        return null;
      }
      final defaultUnit = units.firstWhere(
        (u) => u.isDefault,
        orElse: () => units.first,
      );
      return ItemSearchResult(
        shopItemId: shopItemId,
        itemId: itemId,
        displayName: item.displayName,
        baseUnitCode: item.baseUnitCode,
        baseUnitLabel: item.baseUnitLabel,
        defaultShopItemUnitId: defaultUnit.shopItemUnitId,
        defaultUnitCode: defaultUnit.unitCode,
        defaultUnitLabel: defaultUnit.unitLabel,
        defaultUnitConversionToBase: defaultUnit.conversionToBase,
        defaultUnitSalePrice: defaultUnit.salePrice,
        defaultUnitLastCost: defaultUnit.lastCost,
        currentStock: item.currentStock,
        packagingLabel: defaultUnit.packagingLabel,
        isActivated: true,
        rankReason: item.rankReason,
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan sale',
          context: ErrorDescription('ensure_shop_item'),
        ),
      );
      if (mounted) showError(context, l.saleLoadFailedMessage);
      return null;
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Future<void> _openEditorForTile(
    ItemSearchResult item, {
    required bool priceRequired,
  }) async {
    // _onTapTile / _onLongPressTile guarantee the row is activated by
    // the time we reach here. Pull existing line state if the cashier
    // already added this packaging — long-press should behave as "edit"
    // not "replace with 1".
    final shopItemUnitId = item.defaultShopItemUnitId!;
    final shopItemId = item.shopItemId!;
    final existing = context.read<CartController>().lines[shopItemUnitId];
    // Derive a neutral pricing nudge for priceRequired mode (per
    // docs/add-item-flows.md §1.5). For v1 we only surface the cost
    // hint; sibling-priced hint requires a full getShopItem trip and
    // is deferred until the editor opens often enough to justify it.
    String? priceHint;
    if (priceRequired && item.defaultUnitLastCost != null) {
      final l = tr(context);
      priceHint = l.lineEditorCostHintLabel(
        formatMoney(item.defaultUnitLastCost!, widget.shop),
      );
    }
    final result = await showLineEditor(
      context,
      shopItemUnitId: shopItemUnitId,
      displayName: item.displayName,
      packagingLabel: item.packagingLabel ?? item.baseUnitLabel,
      baseUnitLabel: item.baseUnitLabel,
      currencySymbol: widget.shop.currencySymbol,
      initialQuantity: existing?.quantity ?? 1,
      initialUnitPrice: priceRequired
          ? existing?.unitPrice
          : (existing?.unitPrice ?? item.defaultUnitSalePrice),
      priceRequired: priceRequired,
      shopItemId: shopItemId,
      // Closure captures the search row's base unit info so the picker
      // can offer "+ Add packaging" inline (needs both code + label to
      // open the AddPackagingSheet).
      onPickPackaging: (ctx, siId, currentSiuId) => showUnitPicker(
        ctx,
        shopId: widget.shop.id,
        shopItemId: siId,
        screen: 'sale',
        baseUnitCode: item.baseUnitCode,
        baseUnitLabel: item.baseUnitLabel,
      ),
      priceHint: priceHint,
    );
    if (result == null || !mounted) return;
    final cart = context.read<CartController>();
    if (result.shopItemUnitId != shopItemUnitId &&
        existing != null) {
      // Cashier switched the packaging on a row that was already in the
      // cart — move the line under the new key.
      cart.switchLinePackaging(
        oldShopItemUnitId: shopItemUnitId,
        newShopItemUnitId: result.shopItemUnitId,
        shopItemId: shopItemId,
        itemId: item.itemId,
        displayName: item.displayName,
        packagingLabel: result.packagingLabel,
        baseUnitLabel: item.baseUnitLabel,
        quantity: result.quantity,
        unitPrice: result.unitPrice,
      );
    } else {
      cart.addOrReplaceFromEditor(
        shopItemUnitId: result.shopItemUnitId,
        shopItemId: shopItemId,
        itemId: item.itemId,
        displayName: item.displayName,
        packagingLabel: result.packagingLabel,
        baseUnitLabel: item.baseUnitLabel,
        quantity: result.quantity,
        unitPrice: result.unitPrice,
      );
    }
    setState(() => _cartExpanded = true);
  }

  Future<void> _onLongPressCartLine(_CartLineEntry entry) async {
    final line = entry.line;
    final result = await showLineEditor(
      context,
      shopItemUnitId: line.shopItemUnitId,
      displayName: line.displayName,
      packagingLabel: line.packagingLabel,
      baseUnitLabel: line.baseUnitLabel,
      currencySymbol: widget.shop.currencySymbol,
      initialQuantity: line.quantity,
      initialUnitPrice: line.unitPrice,
      shopItemId: line.shopItemId,
      // CartLine doesn't carry baseUnitCode — pass null so the picker
      // hides the "+ Add packaging" entry. Swapping among existing
      // packagings still works (that's the common case from the cart).
      onPickPackaging: (ctx, siId, currentSiuId) => showUnitPicker(
        ctx,
        shopId: widget.shop.id,
        shopItemId: siId,
        screen: 'sale',
      ),
    );
    if (result == null || !mounted) return;
    final cart = context.read<CartController>();
    if (result.shopItemUnitId != line.shopItemUnitId) {
      cart.switchLinePackaging(
        oldShopItemUnitId: line.shopItemUnitId,
        newShopItemUnitId: result.shopItemUnitId,
        shopItemId: line.shopItemId,
        itemId: line.itemId,
        displayName: line.displayName,
        packagingLabel: result.packagingLabel,
        baseUnitLabel: line.baseUnitLabel,
        quantity: result.quantity,
        unitPrice: result.unitPrice,
      );
    } else {
      cart.updateLineFromEditor(
        entry.key,
        quantity: result.quantity,
        unitPrice: result.unitPrice,
      );
    }
  }


  /// Opens the "+ Add new item" bottom sheet pre-filled with the search
  /// query. On save the new packaging is dropped straight into the cart
  /// at quantity 1 + the price the cashier just typed — no extra
  /// navigation, no second tap.
  Future<void> _onAddNewItem(String query) async {
    final result = await AddNewItemSheet.show(
      context,
      widget.shop,
      initialName: query,
    );
    if (result == null || !mounted) return;
    context.read<CartController>().addOrReplaceFromEditor(
      shopItemUnitId: result.shopItemUnitId,
      shopItemId: result.shopItemId,
      itemId: null,
      displayName: result.displayName,
      packagingLabel: result.packagingLabel,
      baseUnitLabel: result.baseUnitLabel,
      quantity: 1,
      unitPrice: result.salePrice ?? 0,
    );
    // Clear the search bar after a successful add so the cashier sees
    // the cart, not the stale "+ Add new" tile for the now-existing
    // item. Mirrors the receive flow.
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _activeQuery = '';
      _resultsFuture = _fetchWithCache('');
      _cartExpanded = true;
    });
  }

  bool _isNoPrice(ItemSearchResult item) {
    final p = item.defaultUnitSalePrice;
    return p == null || p == 0;
  }

  void _removeLine(String key) {
    final cart = context.read<CartController>();
    cart.removeLine(key);
    if (cart.isEmpty) {
      setState(() => _cartExpanded = false);
    }
  }

  void _toggleCartExpanded() {
    final cart = context.read<CartController>();
    if (cart.isEmpty) return;
    setState(() => _cartExpanded = !_cartExpanded);
  }

  Future<void> _confirmClearAll() async {
    final l = tr(context);
    final cart = context.read<CartController>();
    final count = cart.itemCount;
    final cleared = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l.cartClearConfirmTitle(count)),
        content: Text(l.cartClearConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l.cartClearConfirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l.cartClearConfirmYes),
          ),
        ],
      ),
    );
    if (cleared == true && mounted) {
      cart.clearAll();
      setState(() => _cartExpanded = false);
    }
  }

  void _toggleDebt(bool debt) {
    final cart = context.read<CartController>();
    cart.setDebt(debt);
    if (debt && cart.customer == null) {
      _pickCustomer();
    }
  }

  Future<void> _pickCustomer() async {
    final picked = await showPartyPicker(
      context,
      shop: widget.shop,
      typeCode: 'customer',
    );
    if (picked != null && mounted) {
      context.read<CartController>().setCustomer(picked);
    }
  }

  Future<void> _save() async {
    final l = tr(context);
    final cart = context.read<CartController>();
    if (cart.isEmpty) {
      showError(context, l.saleNeedItemsMessage);
      return;
    }
    if (cart.debt && cart.customer == null) {
      showError(context, l.saleNeedCustomerMessage);
      _pickCustomer();
      return;
    }
    Timing.mark('save.tapped');

    // Optimistic SAVE — per CLAUDE.md's speed contract. Snapshot the
    // cart, clear it synchronously so the cashier sees a fresh screen
    // within the 100ms tap-response budget, then fire the post in the
    // background. On rare failure restore the snapshot and toast the
    // error. The CartController is already designed for this dance
    // (snapshot/restore on cart_controller.dart line 67).
    final api = context.read<ShopApi>();
    final snapshot = cart.snapshot();
    final cashSale = !snapshot.debt;
    final partyId = snapshot.debt ? snapshot.customer!.id : null;
    final total = snapshot.lines.values
        .fold<double>(0, (sum, line) => sum + line.subtotal.toDouble());
    // Track which packagings need their stored sale_price refreshed
    // after a successful post. The cart line carries `priceWasEntered`
    // for editor-sourced prices; persist those so the next tap on the
    // same packaging fast-adds at the new price.
    final priceWriteBacks = <({String shopItemUnitId, num salePrice})>[];
    final lines = <SaleLine>[];
    for (final line in snapshot.lines.values) {
      lines.add(
        SaleLine(
          shopItemUnitId: line.shopItemUnitId,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
        ),
      );
      if (line.priceWasEntered) {
        priceWriteBacks.add(
          (shopItemUnitId: line.shopItemUnitId, salePrice: line.unitPrice),
        );
      }
    }
    final clientOpId = _generateClientOpId();

    cart.clearAll();
    setState(() {
      _cartExpanded = false;
      _saving = false;
    });
    Timing.mark('cart.cleared');
    Timing.endFlow(context);

    await _postSaleAndAfter(
      api: api,
      l: l,
      snapshot: snapshot,
      cashSale: cashSale,
      total: total,
      partyId: partyId,
      lines: lines,
      priceWriteBacks: priceWriteBacks,
      clientOpId: clientOpId,
    );
  }

  /// Fires the post in the background, then on success runs the
  /// receipt-sheet / low-stock / price-writeback follow-ups. On
  /// failure restores the snapshot and surfaces an error toast. The
  /// cashier's UI cleared before this method ran — they're not
  /// blocked on the network.
  Future<void> _postSaleAndAfter({
    required ShopApi api,
    required L10n l,
    required CartSnapshot snapshot,
    required bool cashSale,
    required double total,
    required String? partyId,
    required List<SaleLine> lines,
    required List<({String shopItemUnitId, num salePrice})> priceWriteBacks,
    required String clientOpId,
  }) async {
    String txnId;
    try {
      txnId = await api.postSale(
        shopId: widget.shop.id,
        lines: lines,
        paidAmount: cashSale ? total : 0,
        partyId: partyId,
        paymentMethodCode: cashSale ? 'cash' : null,
        clientOpId: clientOpId,
      );
    } on PostgrestException catch (error, stackTrace) {
      _handleOptimisticSaveFailure(
        snapshot, error, stackTrace, l.salePostFailedMessage);
      return;
    } catch (error, stackTrace) {
      _handleOptimisticSaveFailure(
        snapshot, error, stackTrace, l.salePostFailedMessage);
      return;
    }

    if (!mounted) return;

    // Low-stock probe (gated by the shop toggle) and per-packaging
    // price write-backs run in the background — neither is allowed to
    // roll back the receipt or surface a blocking error.
    if (widget.shop.lowStockWarningEnabled) {
      unawaited(_checkLowStock(api, snapshot));
    }
    for (final write in priceWriteBacks) {
      unawaited(
        api
            .setShopItemUnitSalePrice(
              shopId: widget.shop.id,
              shopItemUnitId: write.shopItemUnitId,
              salePrice: write.salePrice,
            )
            .catchError((Object error, StackTrace stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'dukan sale',
              context: ErrorDescription('set_shop_item_unit_sale_price'),
            ),
          );
        }),
      );
    }

    // Open the receipt sheet on the next frame so the cart-clear
    // rebuild lands first. Fire-and-forget — the cashier dismisses the
    // sheet at their pace; this method returns immediately so callers
    // (and tests) aren't blocked on manual dismissal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(showSaleReceiptSheet(
        context,
        shop: widget.shop,
        txnId: txnId,
      ));
    });
  }

  void _handleOptimisticSaveFailure(
    CartSnapshot snapshot,
    Object error,
    StackTrace stackTrace,
    String message,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan sale',
        context: ErrorDescription('post_sale'),
      ),
    );
    if (!mounted) return;
    // Restore the snapshot so the cashier can retry. If they've already
    // started a new sale, restore replaces — this is a deliberate v1
    // trade-off; a v1.x merge-on-restore lands with the offline write
    // queue (#232) where conflict UX gets proper attention.
    context.read<CartController>().restore(snapshot);
    setState(() => _cartExpanded = true);
    showError(context, message);
  }

  /// Sample post-decrement stock for every unique shop_item in the
  /// just-posted cart and toast every one that came in at or below its
  /// per-item reorder threshold (or below 1 if no threshold set). Best
  /// effort: any failure is logged and swallowed so it can never roll
  /// back a sale that the server already accepted. Caller already
  /// gated on `widget.shop.lowStockWarningEnabled`.
  Future<void> _checkLowStock(
    ShopApi api,
    CartSnapshot snapshot,
  ) async {
    // Build (shopItemId → displayName) from the snapshot so the toast
    // can name each item. Snapshot keys are shopItemUnitIds; we dedupe
    // on shopItemId because two cart lines on the same item with
    // different packagings share a single stock row.
    final shopItemIds = <String>{};
    final displayNames = <String, String>{};
    for (final line in snapshot.lines.values) {
      shopItemIds.add(line.shopItemId);
      displayNames.putIfAbsent(line.shopItemId, () => line.displayName);
    }
    if (shopItemIds.isEmpty) return;

    final locale = Localizations.localeOf(context).languageCode;
    final lows = <({String displayName, num stock, String baseUnit})>[];
    try {
      final stocks = await api.fetchShopItemStocks(
        shopId: widget.shop.id,
        shopItemIds: shopItemIds.toList(growable: false),
        locale: locale,
      );
      for (final s in stocks) {
        if (!isLowStock(
          currentStock: s.currentStock,
          reorderThreshold: s.reorderThreshold,
        )) {
          continue;
        }
        lows.add((
          displayName: displayNames[s.shopItemId] ?? s.displayName,
          stock: s.currentStock,
          baseUnit: s.baseUnitLabel,
        ));
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan sale',
          context: ErrorDescription('low-stock probe'),
        ),
      );
      return;
    }

    if (!mounted || lows.isEmpty) return;
    _showLowStockToasts(lows);
  }

  void _showLowStockToasts(
    List<({String displayName, num stock, String baseUnit})> lows,
  ) {
    final l = tr(context);
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    const maxToasts = 3;
    final visible = lows.length <= maxToasts
        ? lows
        : lows.sublist(0, maxToasts);
    for (final n in visible) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            // ICU placeholders are alphabetical → (amount, item, unit).
            l.lowStockToast(
              _trimStock(n.stock),
              n.displayName,
              n.baseUnit,
            ),
          ),
          backgroundColor: theme.colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
    if (lows.length > maxToasts) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l.lowStockMoreItems(lows.length - maxToasts),
          ),
          backgroundColor: theme.colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Trim trailing zeros on the stock value so a value of -3.000 reads
  /// "-3" in the toast, while -3.500 stays "-3.5".
  String _trimStock(num value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _generateClientOpId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = _random.nextInt(1 << 32);
    return 'sale-$ts-$r';
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final cart = context.watch<CartController>();
    final lines = cart.lines.entries
        .map((e) => _CartLineEntry(key: e.key, line: e.value))
        .toList(growable: false);
    final interactionsLocked = _saving || _activating;
    return Scaffold(
      appBar: dukanAppBar(
        context,
        l.saleTitle,
        actions: [
          IconButton(
            tooltip: l.saleHistoryTooltip,
            icon: const Icon(Icons.history),
            onPressed: interactionsLocked
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SaleHistoryScreen(shop: widget.shop),
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    // Somali item names (caano, hilib, bariis, …) get
                    // mangled by OS autocorrect into English near-matches.
                    // The search index already handles partial matches +
                    // aliases, so the suggestion strip is pure friction.
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: l.saleSearchHint,
                      suffixIcon: IconButton(
                        tooltip: l.scanCameraTooltip,
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: _onScanTap,
                      ),
                    ),
                  ),
                ),
                if (_unknownScan != null) _UnknownScanPill(
                  code: _unknownScan!,
                  onCreate: _onCreateFromUnknown,
                  onDismiss: () => setState(() => _unknownScan = null),
                ),
                Expanded(
                  child: FutureBuilder<List<ItemSearchResult>>(
                    future: _resultsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              l.saleLoadFailedMessage,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                        );
                      }
                      final results =
                          snapshot.data ?? const <ItemSearchResult>[];
                      return _buildResultsArea(context, results);
                    },
                  ),
                ),
                _SaleCartStrip(
                  shop: widget.shop,
                  lines: lines,
                  total: cart.total,
                  itemCount: cart.itemCount,
                  debt: cart.debt,
                  customer: cart.customer,
                  saving: _saving,
                  expanded: _cartExpanded,
                  onToggleExpand: _toggleCartExpanded,
                  onRemoveLine: _removeLine,
                  onLongPressLine: _onLongPressCartLine,
                  onClearAll: _confirmClearAll,
                  onModeChanged: _toggleDebt,
                  onPickCustomer: _pickCustomer,
                  onSave: _save,
                ),
              ],
            ),
            if (_activating)
              const Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Renders the search/favorites area. When zero rows come back and the
  /// query is at least 3 characters long, we show a single tappable "+
  /// Add new item: '{query}'" affordance so the cashier can keep moving
  /// without leaving the Sale screen.
  Widget _buildResultsArea(
    BuildContext context,
    List<ItemSearchResult> results,
  ) {
    final l = tr(context);
    final canAddNew = _activeQuery.length >= 3;
    if (results.isEmpty) {
      if (canAddNew) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          children: [
            const SizedBox(height: 24),
            Center(
              child: Text(
                l.saleSearchEmptyMessage(_activeQuery),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: 16),
            _AddNewItemTile(
              query: _activeQuery,
              enabled: !_saving && !_activating,
              onTap: () => _onAddNewItem(_activeQuery),
            ),
          ],
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _activeQuery.isEmpty
                ? l.saleEmptyFavoritesMessage
                : l.saleSearchEmptyMessage(_activeQuery),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }
    // Results present. Promote the +Add new item row to the TOP when
    // the cashier has typed ≥3 chars — partial matches shouldn't push
    // the "this isn't here, add it" escape hatch out of view.
    final showAddNew = canAddNew;
    return Column(
      children: [
        if (showAddNew)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: _AddNewItemTile(
              query: _activeQuery,
              enabled: !_saving && !_activating,
              onTap: () => _onAddNewItem(_activeQuery),
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            // Two columns × ~110dp — denser than the prior 140dp tile so
            // text + price aren't lost in a sea of whitespace; still
            // well above the 56dp tap-target floor.
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              mainAxisExtent: 110,
            ),
            itemCount: results.length,
            itemBuilder: (context, i) {
              final item = results[i];
              return _SaleItemTile(
                shop: widget.shop,
                item: item,
                onTap: (_saving || _activating) ? null : () => _onTapTile(item),
                onLongPress: (_saving || _activating)
                    ? null
                    : () => _onLongPressTile(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SaleItemTile extends StatelessWidget {
  const _SaleItemTile({
    required this.shop,
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  final ShopSummary shop;
  final ItemSearchResult item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = item.defaultUnitSalePrice;
    final noPrice = price == null || price == 0;
    final priceText = noPrice
        ? tr(context).lineEditorTilePriceMissing
        : formatMoney(price, shop);
    // Prefer the packaging label when it isn't just the base unit (a
    // "25 kg bag" packaging tells the cashier exactly what they're
    // tapping); fall back to the base unit otherwise so single-pack
    // items still show "kg · $20".
    final unitLabel = item.packagingLabel ?? item.baseUnitLabel;
    final low = isLowStock(
      currentStock: item.currentStock,
      reorderThreshold: item.reorderThreshold,
    );
    final stockText = item.currentStock == null
        ? null
        : formatCompoundStock(
            stock: item.currentStock!,
            baseLabel: item.baseUnitLabel,
            packagingLabel: item.defaultUnitLabel,
            conversion: item.defaultUnitConversionToBase,
          );
    return Card(
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                displayName(item.displayName),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$unitLabel · $priceText',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
              if (stockText != null) ...[
                const SizedBox(height: 2),
                Text(
                  stockText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        low ? FontWeight.w700 : FontWeight.w400,
                    color: low
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AddNewItemTile extends StatelessWidget {
  const _AddNewItemTile({
    required this.query,
    required this.enabled,
    required this.onTap,
  });

  final String query;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.add_circle_outline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.addNewItemSearchResult(query),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartLineEntry {
  const _CartLineEntry({required this.key, required this.line});
  final String key;
  final CartLine line;
}

class _SaleCartStrip extends StatelessWidget {
  const _SaleCartStrip({
    required this.shop,
    required this.lines,
    required this.total,
    required this.itemCount,
    required this.debt,
    required this.customer,
    required this.saving,
    required this.expanded,
    required this.onToggleExpand,
    required this.onRemoveLine,
    required this.onLongPressLine,
    required this.onClearAll,
    required this.onModeChanged,
    required this.onPickCustomer,
    required this.onSave,
  });

  final ShopSummary shop;
  final List<_CartLineEntry> lines;
  final double total;
  final int itemCount;
  final bool debt;
  final PartySearchResult? customer;
  final bool saving;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final void Function(String key) onRemoveLine;
  final void Function(_CartLineEntry entry) onLongPressLine;
  final VoidCallback onClearAll;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onPickCustomer;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final canSave = itemCount > 0 && (!debt || customer != null) && !saving;
    final canExpand = lines.isNotEmpty;
    final maxListHeight = MediaQuery.of(context).size.height * 0.25;

    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Summary header: tap to expand, plus the Clear-all button
            // when the cart has items AND the drawer is open (so the
            // shopkeeper sees the items before being offered the wipe).
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: canExpand ? onToggleExpand : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            canExpand
                                ? (expanded
                                      ? Icons.keyboard_arrow_down
                                      : Icons.keyboard_arrow_up)
                                : Icons.shopping_cart_outlined,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.saleCartSummary(
                                itemCount,
                                formatMoney(total, shop),
                              ),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (expanded && canExpand)
                  TextButton(
                    onPressed: saving ? null : onClearAll,
                    child: Text(l.cartClearAllButton),
                  ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: expanded && canExpand
                  ? ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxListHeight),
                      child: _CartLineList(
                        shop: shop,
                        lines: lines,
                        saving: saving,
                        onRemoveLine: onRemoveLine,
                        onLongPressLine: onLongPressLine,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(l.saleCash),
                    icon: const Icon(Icons.payments),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(l.saleDebt),
                    icon: const Icon(Icons.person),
                  ),
                ],
                selected: {debt},
                onSelectionChanged: saving
                    ? null
                    : (set) => onModeChanged(set.first),
              ),
            ),
            if (debt) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: customer == null
                    ? OutlinedButton.icon(
                        onPressed: saving ? null : onPickCustomer,
                        icon: const Icon(Icons.person_search),
                        label: Text(l.salePickCustomerButton),
                      )
                    : InputChip(
                        avatar: const Icon(Icons.person),
                        label: Text(
                          l.saleCustomerChip(
                            customer!.name,
                            formatMoney(customer!.receivable, shop),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: saving ? null : onPickCustomer,
                      ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canSave ? onSave : null,
                child: saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(l.saleSaveButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Owns its own ScrollController so the Scrollbar doesn't pick up the
// PrimaryScrollController already in use by the favorites grid above
// (Scrollbar asserts on multiple ScrollPositions per controller).
class _CartLineList extends StatefulWidget {
  const _CartLineList({
    required this.shop,
    required this.lines,
    required this.saving,
    required this.onRemoveLine,
    required this.onLongPressLine,
  });

  final ShopSummary shop;
  final List<_CartLineEntry> lines;
  final bool saving;
  final void Function(String key) onRemoveLine;
  final void Function(_CartLineEntry entry) onLongPressLine;

  @override
  State<_CartLineList> createState() => _CartLineListState();
}

class _CartLineListState extends State<_CartLineList> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      child: ListView.separated(
        controller: _scrollController,
        primary: false,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: widget.lines.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => _CartLineTile(
          shop: widget.shop,
          entry: widget.lines[i],
          enabled: !widget.saving,
          onRemove: () => widget.onRemoveLine(widget.lines[i].key),
          onLongPress: () => widget.onLongPressLine(widget.lines[i]),
        ),
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.shop,
    required this.entry,
    required this.enabled,
    required this.onRemove,
    required this.onLongPress,
  });

  final ShopSummary shop;
  final _CartLineEntry entry;
  final bool enabled;
  final VoidCallback onRemove;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final line = entry.line;
    // Always render the packaging label below the name. Hiding it when
    // packaging == base unit was ambiguous for multi-pack items (bariis
    // sold as Kg looked identical to bariis sold as 25 Kg Bag). The
    // extra row is cheap; the unambiguity is the point.
    final subtitle = l.cartLineSubtotal(
      formatQty(line.quantity),
      formatMoney(line.unitPrice, shop),
      formatMoney(line.subtotal, shop),
    );
    final name = displayName(line.displayName);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      visualDensity: VisualDensity.compact,
      // Tap-to-edit (qty / price / packaging swap) — long-press is too
      // fiddly one-handed on a mid-range phone. The ✕ on the right still
      // removes; the editor is the path for everything else.
      onTap: enabled ? onLongPress : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            line.packagingLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
      subtitle: Text(subtitle),
      trailing: IconButton(
        tooltip: l.cartRemoveLineTooltip(name),
        icon: const Icon(Icons.close, size: 20),
        onPressed: enabled ? onRemove : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }
}

/// Top-of-screen pill shown after a scan that matches no shop_item.
/// Phase 1 surfaces a "Create new" + "Dismiss" pair; the "Bind to
/// existing" action ships with the Product-detail scanner phase per
/// docs/scanner.md §16. Not capability-gated yet — the capability
/// refactor (#229) will hide the actions for cashier role.
class _UnknownScanPill extends StatelessWidget {
  const _UnknownScanPill({
    required this.code,
    required this.onCreate,
    required this.onDismiss,
  });

  final String code;
  final VoidCallback onCreate;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.help_outline, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.scanUnknownPillLabel(code),
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onCreate,
            child: Text(l.scanUnknownCreateAction),
          ),
          IconButton(
            tooltip: l.scanUnknownDismissAction,
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
