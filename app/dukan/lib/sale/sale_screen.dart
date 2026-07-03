// Sale screen — v2 picker on top of `search_items`, cart bottom strip,
// optimistic SAVE → post_sale.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';
import 'package:dukan/sale/add_new_item_sheet.dart';
import 'package:dukan/sale/cart_controller.dart';
import 'package:dukan/receive/unit_picker_sheet.dart';
import 'package:dukan/sale/line_editor_sheet.dart';
import 'package:dukan/sale/sale_detail_screen.dart';
import 'package:dukan/sale/sale_history_screen.dart';
import 'package:dukan/observability/timing.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/shared/client_op_id.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/queue/queue_status_pill.dart';
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
import 'package:dukan/shared/dismiss_keyboard.dart';
import 'package:dukan/shared/expandable_line_list.dart';
import 'package:dukan/shared/item_grid.dart';
import 'package:dukan/shared/working_date.dart';
import 'package:dukan/shared/typography.dart';
import 'package:dukan/shared/stock_format.dart';

class SaleScreen extends StatefulWidget {
  const SaleScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  late Future<List<ItemSearchResult>> _resultsFuture;
  String _activeQuery = '';
  Timer? _debounce;
  bool _saving = false;
  bool _activating = false;
  bool _cartExpanded = false;
  // Full/review mode: when open, grow the cart drawer to fill the screen so a
  // long cart can be reviewed. Reset whenever the drawer collapses.
  bool _cartFull = false;
  String? _locale;
  String? _unknownScan;
  late final HidScanListener _hidListener;

  @override
  void initState() {
    super.initState();
    // Auto-expand the drawer when reopening the Sale screen with a
    // non-empty cart: the cashier needs to see at a glance whether the
    // existing items are theirs to continue or a stale cart to clear.
    final cart = context.read<CartController>();
    _cartExpanded = cart.isNotEmpty;
    // Backdating (#5) is sticky within a screen session but resets to today on
    // each fresh entry — non-notifying since we're in initState (build phase).
    cart.initWorkingDate();
    _searchFocus.addListener(_onSearchFocusChanged);
    // Detect Bluetooth-HID scanners typing burst-style. isActive gates
    // dispatch to the route currently visible — handles the case where
    // Sale is pushed under another screen.
    final scanner = ScannerSettings.current;
    _hidListener = HidScanListener(
      onScan: _onHidScan,
      isActive: () => mounted && (ModalRoute.of(context)?.isCurrent ?? false),
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
    _searchFocus.dispose();
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

  Future<List<ItemSearchResult>> _fetch(String query) async {
    // #374: when offline_mode = full, read from the local mirror.
    // Light mode keeps the existing live RPC path (search_items
    // with server-side ranking).
    if (useLocalDb(context)) {
      final repo = context.read<LocalRepository>();
      // Sale ranks the items you sell most/most-recently first.
      final items = await repo.searchItems(
        query,
        shopId: widget.shop.id,
        rankBy: 'recency',
      );
      final results = <ItemSearchResult>[];
      for (final item in items) {
        results.add(await repo.toItemSearchResult(item, screen: 'sale'));
      }
      return results;
    }
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
    // Don't fight the cashier while they're searching — an auto-expand would
    // re-cover the item results behind the cart + keyboard.
    if (!mounted || _cartExpanded || _searchFocus.hasFocus) return;
    setState(() => _cartExpanded = true);
  }

  /// Focusing the search field collapses the cart so the item results aren't
  /// hidden behind the expanded cart strip and the keyboard.
  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus && _cartExpanded && mounted) {
      setState(() {
        _cartExpanded = false;
        _cartFull = false;
      });
    }
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
      learnedQty: item.learnedQty,
    );
    if (result == null || !mounted) return;
    final cart = context.read<CartController>();
    if (result.shopItemUnitId != shopItemUnitId && existing != null) {
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
        baseUnitCode: item.baseUnitCode,
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
      // Pass the line's base unit so the picker offers "+ Add packaging" too —
      // identical to the item-tile editor.
      onPickPackaging: (ctx, siId, currentSiuId) => showUnitPicker(
        ctx,
        shopId: widget.shop.id,
        shopItemId: siId,
        screen: 'sale',
        baseUnitCode: line.baseUnitCode,
        baseUnitLabel: line.baseUnitLabel,
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
      baseUnitCode: result.baseUnitCode,
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
    setState(() {
      _cartExpanded = !_cartExpanded;
      if (!_cartExpanded) _cartFull = false; // collapsing exits full
    });
  }

  void _toggleCartFull() {
    setState(() => _cartFull = !_cartFull);
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

    final api = context.read<ShopApi>();
    final snapshot = cart.snapshot();
    final cashSale = !snapshot.debt;
    final partyId = snapshot.debt ? snapshot.customer!.id : null;
    final total = snapshot.lines.values.fold<double>(
      0,
      (sum, line) => sum + line.subtotal.toDouble(),
    );
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
        priceWriteBacks.add((
          shopItemUnitId: line.shopItemUnitId,
          salePrice: line.unitPrice,
        ));
      }
    }
    final clientOpId = generateClientOpId('sale');

    // #383: useLocalDb=false → direct-await path. No optimistic
    // cart clear, no queue, no projection. Cart stays on screen
    // until server confirms success (or shows error on failure
    // so the cashier can retry).
    if (!useLocalDb(context)) {
      await _saveDirect(
        api: api,
        cart: cart,
        l: l,
        snapshot: snapshot,
        cashSale: cashSale,
        total: total,
        partyId: partyId,
        lines: lines,
        priceWriteBacks: priceWriteBacks,
        clientOpId: clientOpId,
      );
      return;
    }

    // #385: optimistic write to local_transaction BEFORE we
    // clear the cart so Sales History reflects the sale
    // instantly (no waiting for delta sync or realtime). The
    // server-authoritative row replaces this one (dedup by
    // client_op_id) when delta sync brings it back, whether
    // the post goes through the direct path or the queue.
    final localRepoForOptimistic = useLocalDb(context)
        ? context.read<LocalRepository>()
        : null;
    if (localRepoForOptimistic != null) {
      try {
        await localRepoForOptimistic.writeOptimisticTransaction(
          clientOpId: clientOpId,
          shopId: widget.shop.id,
          typeCode: 'sale',
          occurredAtMs:
              (snapshot.occurredAt ?? DateTime.now()).millisecondsSinceEpoch,
          total: total,
          partyId: partyId,
          payload: <String, dynamic>{
            'party_name': snapshot.customer?.name,
            'payment_method_code': cashSale ? 'cash' : null,
            'paid_amount': cashSale ? total : 0,
            'lines_summary': buildLinesSummaryJson(snapshot),
          },
        );
      } catch (e, st) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: st,
            library: 'dukan sale',
            context: ErrorDescription('write optimistic sale transaction'),
          ),
        );
      }
      // Float the just-sold items to the top of the Sale list immediately;
      // the next items-sync reconciles to the server's combined count.
      try {
        await localRepoForOptimistic.applyOptimisticSaleRecency(
          shopItemIds: snapshot.lines.values
              .map((line) => line.shopItemId)
              .toList(growable: false),
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );
      } catch (e, st) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: st,
            library: 'dukan sale',
            context: ErrorDescription('optimistic sale recency bump'),
          ),
        );
      }
      // Optimistic stock decrement + (debt sale) customer receivable so
      // Products and the customers LIST reflect the sale instantly — they read
      // current_stock / local_party.receivable directly. The next items/parties
      // sync replaces these; the reject path reverts them.
      try {
        await localRepoForOptimistic.applyOptimisticStockForLines(
          lines: [
            for (final line in lines)
              ProjectionLine(
                shopItemUnitId: line.shopItemUnitId,
                quantity: line.quantity,
                direction: -1,
              ),
          ],
        );
        if (partyId != null) {
          await localRepoForOptimistic.applyOptimisticPartyCharge(
            partyId: partyId,
            direction: 'I',
            amount: total,
          );
        }
      } catch (e, st) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: st,
            library: 'dukan sale',
            context: ErrorDescription('optimistic sale stock/receivable'),
          ),
        );
      }
    }

    // Optimistic SAVE (useLocalDb=true) — per CLAUDE.md's speed
    // contract. Snapshot the cart, clear it synchronously so the
    // cashier sees a fresh screen within the 100ms tap-response
    // budget, then fire the post in the background. Capture
    // Timing's context before the awaits to avoid the async-gap
    // lint (`use_build_context_synchronously`).
    cart.clearAll();
    setState(() {
      _cartExpanded = false;
      _saving = false;
    });
    Timing.mark('cart.cleared');
    if (mounted) Timing.endFlow(context);
    // Instant, noticeable confirmation — covers the offline/queued case
    // (no receipt sheet) and reassures before any network round-trip.
    if (mounted) showHappyToast(context, l.saleSavedToast);

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

  /// #383: direct-post path for useLocalDb=false. Awaits the post
  /// inline; clears cart + opens receipt on success; shows error
  /// and keeps cart on failure so cashier can retry.
  Future<void> _saveDirect({
    required ShopApi api,
    required CartController cart,
    required L10n l,
    required CartSnapshot snapshot,
    required bool cashSale,
    required double total,
    required String? partyId,
    required List<SaleLine> lines,
    required List<({String shopItemUnitId, num salePrice})> priceWriteBacks,
    required String clientOpId,
  }) async {
    setState(() => _saving = true);
    String txnId;
    try {
      txnId = await api.postSale(
        shopId: widget.shop.id,
        lines: lines,
        paidAmount: cashSale ? total : 0,
        partyId: partyId,
        paymentMethodCode: cashSale ? 'cash' : null,
        clientOpId: clientOpId,
        occurredAt: snapshot.occurredAt,
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan sale',
          context: ErrorDescription('post_sale (useLocalDb=false)'),
        ),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, '${l.salePostFailedMessage}\n$error');
      return;
    }

    if (!mounted) return;
    cart.clearAll();
    setState(() {
      _cartExpanded = false;
      _saving = false;
    });

    // Price write-backs run in the background — never block the
    // receipt or surface a blocking error.
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

    if (!mounted) return;
    try {
      await showSaleReceiptSheet(
        context,
        shop: widget.shop,
        txnId: txnId,
        fallback: SaleReceiptFallback.fromCart(snapshot),
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan sale',
          context: ErrorDescription('show sale receipt sheet'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Receipt sheet failed: $error'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
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
    // Captured before the post so the reject/queue paths can touch the mirror
    // even if the context unmounts.
    final localRepo = useLocalDb(context)
        ? context.read<LocalRepository>()
        : null;

    // Open the receipt sheet (DONE + Share). Shared by the online-success
    // path (server txn id) and the offline path (the optimistic row's id ==
    // clientOpId). The cart-snapshot fallback renders the receipt even when
    // the txn isn't in the mirror yet, so it works offline.
    Future<void> openReceipt(String receiptTxnId) async {
      if (!mounted) return;
      try {
        await showSaleReceiptSheet(
          context,
          shop: widget.shop,
          txnId: receiptTxnId,
          fallback: SaleReceiptFallback.fromCart(snapshot),
        );
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'dukan sale',
            context: ErrorDescription('show sale receipt sheet'),
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Receipt sheet failed: $error'),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    }

    String txnId;
    try {
      txnId = await api.postSale(
        shopId: widget.shop.id,
        lines: lines,
        paidAmount: cashSale ? total : 0,
        partyId: partyId,
        paymentMethodCode: cashSale ? 'cash' : null,
        clientOpId: clientOpId,
        occurredAt: snapshot.occurredAt,
      );
    } on PostgrestException catch (error, stackTrace) {
      // 4xx-style server reject — won't succeed on retry. Revert the optimistic
      // stock + receivable bumps (the cart is restored for a retry, so a
      // lingering bump would double-count), then restore the snapshot.
      if (localRepo != null) {
        try {
          await localRepo.applyOptimisticStockForLines(
            lines: [
              for (final line in lines)
                ProjectionLine(
                  shopItemUnitId: line.shopItemUnitId,
                  quantity: line.quantity,
                  direction: 1, // undo the sale decrement
                ),
            ],
          );
          if (partyId != null) {
            await localRepo.applyOptimisticPartyPayment(
              partyId: partyId,
              direction: 'I',
              amount: total,
            );
          }
        } catch (_) {
          /* best-effort revert; sync reconciles regardless */
        }
      }
      _handleOptimisticSaveFailure(
        snapshot,
        error,
        stackTrace,
        l.salePostFailedMessage,
      );
      return;
    } catch (error, stackTrace) {
      // Network/transient — enqueue for the offline write queue to
      // retry on backoff. Cart stays cleared; the pill in the app
      // bar gives the cashier feedback that work is pending. No
      // receipt sheet for queued sales (cashier checks history if
      // they need the receipt).
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan sale',
          context: ErrorDescription('post_sale (queuing for retry)'),
        ),
      );
      if (!mounted) return;
      // Stamp the cashier's user id so a future audit-stamping pass
      // (Phase 5) can attribute the sale to whoever rang it up even
      // if a different user is signed in when the queue drains.
      // currentUser is non-null in production (screen is gated
      // behind sign-in); '' is a defensive fallback for tests where
      // Supabase isn't initialised.
      String actorId = '';
      try {
        actorId = Supabase.instance.client.auth.currentUser?.id ?? '';
      } catch (_) {
        actorId = '';
      }
      final post = PendingPost(
        id: generateClientOpId('sale'),
        clientOpId: clientOpId,
        shopId: widget.shop.id,
        originalActorUserId: actorId,
        rpc: 'post_sale',
        params: buildPostSaleParams(
          lines: lines,
          paidAmount: cashSale ? total : 0,
          partyId: partyId,
          paymentMethodCode: cashSale ? 'cash' : null,
          occurredAt: snapshot.occurredAt,
        ),
        queuedAt: DateTime.now(),
      );
      // Stock + receivable were already bumped optimistically up-front in _save
      // (current_stock / local_party.receivable), so the in-flight queued sale
      // shows in Products + the customers list until the post drains and the
      // items/parties sync replaces them. No stock projection needed (the bump
      // lives directly in current_stock).
      final queue = context.read<OfflineQueueController>();
      await queue.enqueue(post);
      // Open the receipt just like an online sale — the optimistic
      // local_transaction shares the sale's clientOpId as its id, and the
      // cart fallback renders it regardless. DONE + Share work offline.
      await openReceipt(clientOpId);
      return;
    }

    if (!mounted) return;

    // Per-packaging price write-backs run in the background — they are
    // never allowed to roll back the receipt or surface a blocking error.
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

    // Open the receipt sheet directly. The earlier cart-clear
    // setState (synchronous, before the network await) plus the
    // round-trip latency mean the cart-clear frame has already
    // landed. A previous `addPostFrameCallback` wrapper deferred
    // the open to "the next frame," but on iOS in release mode the
    // engine had no reason to schedule a frame once the UI was
    // stable — the sheet only appeared when the user touched
    // somewhere and forced one.
    //
    // #371 + #372 (extended): re-check `mounted` immediately
    // before opening — the network round-trip above can outlive
    // the widget if the cashier navigated away.
    await openReceipt(txnId);
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

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final cart = context.watch<CartController>();
    final lines = cart.lines.entries
        .map((e) => _CartLineEntry(key: e.key, line: e.value))
        .toList(growable: false);
    final interactionsLocked = _saving || _activating;
    // Full/review drawer: grow the cart strip to fill the screen (grid hidden)
    // so a long cart can be reviewed. Only meaningful when open with lines.
    final cartFull = _cartFull && _cartExpanded && cart.isNotEmpty;
    final cartStrip = _SaleCartStrip(
      shop: widget.shop,
      lines: lines,
      total: cart.total,
      itemCount: cart.itemCount,
      debt: cart.debt,
      customer: cart.customer,
      saving: _saving,
      expanded: _cartExpanded,
      full: cartFull,
      onToggleExpand: _toggleCartExpanded,
      onToggleFull: _toggleCartFull,
      onRemoveLine: _removeLine,
      onLongPressLine: _onLongPressCartLine,
      onClearAll: _confirmClearAll,
      onModeChanged: _toggleDebt,
      onPickCustomer: _pickCustomer,
      onSave: _save,
    );
    return Scaffold(
      appBar: dukanAppBar(
        context,
        l.saleTitle,
        actions: [
          WorkingDateChip(
            workingDate: cart.workingDate,
            onChanged: cart.setWorkingDate,
          ),
          const QueueStatusPill(),
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
                // Backdating is signalled by the highlighted date chip in the
                // app bar; a separate banner just eats vertical space.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onTapOutside: dismissKeyboardOnTapOutside,
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
                if (_unknownScan != null)
                  _UnknownScanPill(
                    code: _unknownScan!,
                    onCreate: _onCreateFromUnknown,
                    onDismiss: () => setState(() => _unknownScan = null),
                  ),
                // Full/review mode: the cart strip takes the Expanded slot and
                // the results grid is hidden (search field stays to return to
                // picking). Otherwise the grid is Expanded and the strip is a
                // min-size child below it.
                if (!cartFull)
                  Expanded(
                    child: FutureBuilder<List<ItemSearchResult>>(
                      future: _resultsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
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
                if (cartFull) Expanded(child: cartStrip) else cartStrip,
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
            // Dragging the results dismisses the keyboard (the natural
            // one-handed gesture) so it reclaims the space the numpad ate.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            // Responsive density: ~110dp tiles that grow with the font
            // scale, column count adapting to width (2 → 3+ on wider
            // phones). Shared with Receive so both grids stay identical.
            gridDelegate: itemGridDelegate(context),
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
    // Bare packaging noun ("Carton", not "12 Bottle Carton") so the tile's
    // unit line stays short and the price beside it isn't truncated.
    final conv = item.defaultUnitConversionToBase;
    final unitLabel =
        (item.defaultUnitLabel != null && conv != null && conv > 1)
            ? packagingCountNoun(
                packagingLabel: item.defaultUnitLabel!,
                conversion: conv,
                baseLabel: item.baseUnitLabel,
              )
            : (item.packagingLabel ?? item.baseUnitLabel);
    final level = stockLevel(
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
            compact: true,
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
                  fontSize: 15 * kFontScale,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$unitLabel · $priceText',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13 * kFontScale,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
              if (stockText != null) ...[
                const SizedBox(height: 2),
                Text(
                  stockText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13 * kFontScale,
                    fontWeight: level == StockLevel.healthy
                        ? FontWeight.w400
                        : FontWeight.w700,
                    color: stockLevelColor(context, level),
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
    required this.full,
    required this.onToggleExpand,
    required this.onToggleFull,
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
  final bool full;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleFull;
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
    final maxListHeight = MediaQuery.of(context).size.height * 0.20;
    // Peek (collapsed) = summary + SAVE only, so the item grid keeps the screen
    // while searching. The line list + Lacag/Deyn + customer live in the
    // expanded section. Force-expand when a debt sale still needs a customer.
    final showExpanded = (expanded && canExpand) || (debt && customer == null);
    // Full/review mode only applies once open with lines.
    final full = this.full && canExpand;

    FilledButton saveButton() => FilledButton(
      onPressed: canSave ? onSave : null,
      child: saving
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Text(l.saleSaveButton),
    );

    // Shared line list — capped at 25% in normal, Expanded in full; overflow
    // cue taps grow to full.
    Widget lineList() => ExpandableLineList(
      fill: full,
      maxHeight: maxListHeight,
      itemCount: lines.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _CartLineTile(
        shop: shop,
        entry: lines[i],
        enabled: !saving,
        onRemove: () => onRemoveLine(lines[i].key),
        onLongPress: () => onLongPressLine(lines[i]),
      ),
      onExpandRequested: full ? null : onToggleFull,
    );

    // Lacag/Deyn toggle + customer + full-width SAVE, below the list.
    Widget trailingControls() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
        SizedBox(width: double.infinity, child: saveButton()),
      ],
    );

    // Summary header: tap the row to expand/collapse; a distinct expand/shrink
    // icon toggles normal ↔ full; Clear-all + compact peek SAVE ride here too.
    final summaryRow = Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: canExpand ? onToggleExpand : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    canExpand
                        ? (showExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up)
                        : Icons.shopping_cart_outlined,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.saleCartSummary(itemCount, formatMoney(total, shop)),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showExpanded && canExpand)
          TextButton(
            onPressed: saving ? null : onClearAll,
            child: Text(l.cartClearAllButton),
          ),
        if (showExpanded && canExpand)
          IconButton(
            tooltip: full ? l.drawerShrinkTooltip : l.drawerExpandTooltip,
            icon: Icon(full ? Icons.unfold_less : Icons.unfold_more),
            onPressed: onToggleFull,
          ),
        if (!showExpanded) ...[const SizedBox(width: 8), saveButton()],
      ],
    );

    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
        // Full mode fills the parent's Expanded (list is Expanded inside a
        // max Column); normal/peek is a min Column with an AnimatedSize.
        child: full
            ? Column(
                mainAxisSize: MainAxisSize.max,
                children: [summaryRow, lineList(), trailingControls()],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  summaryRow,
                  AnimatedSize(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: showExpanded
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (canExpand) lineList(),
                              trailingControls(),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
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
    // Packaging sits BESIDE the name (not on its own row) so a cart line is
    // two lines, not three. Always shown — hiding it when packaging == base
    // unit was ambiguous for multi-pack items (bariis as Kg vs 25 Kg Bag).
    // Arg order follows the generated (alphabetical) signature
    // cartLineSubtotal(quantity, subtotal, unitPrice) — NOT the template's
    // visual order — so pass subtotal before unitPrice.
    final subtitle = l.cartLineSubtotal(
      formatQty(line.quantity),
      formatMoney(line.subtotal, shop),
      formatMoney(line.unitPrice, shop),
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
      title: Row(
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              line.packagingLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11 * kFontScale,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(subtitle),
      // ≥48dp hit target (Material floor) so removing a line — a
      // destructive action sitting right next to the tap-to-edit body —
      // isn't a fat-finger gamble one-handed.
      trailing: IconButton(
        tooltip: l.cartRemoveLineTooltip(name),
        icon: const Icon(Icons.close, size: 20),
        onPressed: enabled ? onRemove : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
