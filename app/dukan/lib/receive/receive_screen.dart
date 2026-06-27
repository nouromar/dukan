// The bono-entry workhorse: pick an item, set qty + total, ADD LINE,
// repeat. The supplier is already in ReceiveController from the picker.
//
// Layout, top to bottom:
//   * AppBar — "Receive from {supplier}" + a "change supplier" icon
//   * Search field
//   * Favorites grid — search_items(screen='receive', p_party_id) so
//     items this supplier has provided in past bonos rank to the top
//     and the inline form can pre-fill cost from each tile's last_cost
//     (supplier-scoped when the partyId is passed).
//   * Selected-item form — two-way bound (Per <packaging>, Total) money
//     fields. Cashier types whichever matches the bono; the other
//     auto-fills. Qty changes recompute whichever field was NOT the
//     last one typed. The packaging chip is tappable: opens the unit
//     picker so the cashier can swap from the default (e.g., 25 kg
//     bag) to another packaging (e.g., 50 kg bag) for the line.
//   * Lines strip — expandable summary, like the Sale cart
//   * SAVE — always creates a fully-credit receive (cash payment is a
//     separate Payment-screen step; see decisions.md TODO)
//
// v2 model: lines key on `shopItemUnitId` — the packaging the supplier
// delivered. Same item received as a 25 kg bag and a 10 kg bag in the
// same bono are two distinct lines (correct: distinct per-packaging
// last_cost values, distinct stock movements).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';
import 'package:dukan/receive/add_new_item_sheet.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/receive/receive_history_screen.dart';
import 'package:dukan/receive/supplier_picker_screen.dart';
import 'package:dukan/receive/unit_picker_sheet.dart';
import 'package:dukan/observability/timing.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/scanner/hid_listener.dart';
import 'package:dukan/scanner/multi_scan_sheet.dart';
import 'package:dukan/scanner/scan_event.dart';
import 'package:dukan/scanner/scanner_settings.dart';
import 'package:dukan/scanner/scanner_sheet.dart';
import 'package:dukan/shared/bono_image_picker.dart';
import 'package:dukan/shared/client_op_id.dart';
import 'package:dukan/shared/display_name.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/favorites_cache.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/low_stock.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/quantity_chips.dart';
import 'package:dukan/shared/quantity_format.dart';
import 'package:dukan/shared/stock_format.dart';
import 'package:dukan/shared/typography.dart';

enum _BonoSource { camera, gallery }

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({
    required this.shop,
    this.bonoPicker,
    super.key,
  });

  final ShopSummary shop;

  /// Injected so tests can substitute a fake. Production wires the
  /// real `DefaultBonoImagePicker()` lazily on first attach so we
  /// don't construct a platform-channel-backed picker when it isn't
  /// used.
  final BonoImagePicker? bonoPicker;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final _searchController = TextEditingController();
  late Future<List<ItemSearchResult>> _resultsFuture;
  String _activeQuery = '';
  Timer? _debounce;
  bool _saving = false;
  bool _attachingBono = false;
  String? _bonoDocumentId;
  BonoImagePicker? _picker;
  bool _linesExpanded = false;
  // The activated item the cashier is composing a line for. `shopItemId`
  // is guaranteed non-null (we run ensureShopItem before flipping the
  // form on, even for unactivated catalog rows). Carries the default
  // packaging + cost the form pre-fills from.
  _SelectedItem? _selectedItem;
  // True while we're running ensureShopItem for an unactivated catalog
  // row. Used to render an inline "Activating..." indicator on the tile
  // so the cashier sees the screen is doing something.
  String? _activatingItemId;
  String? _locale;
  String? _unknownScan;
  late final HidScanListener _hidListener;

  @override
  void initState() {
    super.initState();
    _linesExpanded = context.read<ReceiveController>().isNotEmpty;
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
    _searchController.clear();
    _debounce?.cancel();
    setState(() {
      _activeQuery = '';
      _resultsFuture = _fetchWithCache('');
    });
    _handleScan(event);
  }

  Future<void> _onScanTap() async {
    final event = await Scanner.open(context);
    if (event == null || !mounted) return;
    await _handleScan(event);
  }

  Future<void> _onMultiScanTap() async {
    // Capture state we'll need across the async gap before any await.
    final shopId = widget.shop.id;
    final api = context.read<ShopApi>();
    final receiveCtrl = context.read<ReceiveController>();
    final locale = Localizations.localeOf(context).languageCode;
    final supplierId = receiveCtrl.supplier?.id;
    final l = tr(context);

    final result = await MultiScan.open(
      context,
      resolver: (code) async {
        final rows = await api.searchItems(
          shopId: shopId,
          query: code,
          screen: 'receive',
          locale: locale,
          partyId: supplierId,
        );
        if (rows.isEmpty) return null;
        return rows.first;
      },
    );
    if (result == null || !mounted) return;

    for (final line in result.stagedLines) {
      receiveCtrl.addOrReplaceLine(
        shopItemUnitId: line.shopItemUnitId,
        shopItemId: line.shopItemId,
        itemId: line.itemId,
        displayName: line.displayName,
        packagingLabel: line.packagingLabel,
        baseUnitLabel: line.baseUnitLabel,
        quantity: line.quantity,
        lineTotal: line.lineTotal,
      );
    }
    setState(() {
      _linesExpanded = receiveCtrl.isNotEmpty;
      // Surface the first unknown code in the existing pill; subsequent
      // unknowns are reachable after the cashier dismisses it. Cheap
      // and consistent with the single-scan unknown UX.
      if (result.unknownCodes.isNotEmpty) {
        _unknownScan = result.unknownCodes.first;
      }
    });
    if (result.stagedLines.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.multiScanAppliedSummary(result.stagedLines.length)),
        ),
      );
    }
  }

  Future<void> _handleScan(ScanEvent event) async {
    try {
      final results = await context.read<ShopApi>().searchItems(
        shopId: widget.shop.id,
        query: event.code,
        screen: 'receive',
        locale: Localizations.localeOf(context).languageCode,
        partyId: context.read<ReceiveController>().supplier?.id,
      );
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() => _unknownScan = event.code);
        return;
      }
      setState(() => _unknownScan = null);
      // Reuse the normal tile-tap path so the form pre-fills from the
      // matched packaging's defaults, exactly like a manual tap would.
      await _onTapTile(results.first);
    } catch (error, stackTrace) {
      if (!mounted) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan scanner',
          context: ErrorDescription('receive scan lookup for ${event.code}'),
        ),
      );
      showError(context, tr(context).scanLookupFailed);
    }
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

  /// Mirrors Sale: the blank-query (favorites) path is cache-backed
  /// so Receive entry feels instant. Bypassed when a supplier has
  /// been picked — supplier-scoped recents shouldn't blend with the
  /// global-favorites cache. The cache key uses 'receive' only when
  /// no supplier is selected; with a supplier we go direct to the
  /// network for the per-supplier ranking.
  Future<List<ItemSearchResult>> _fetchWithCache(String query) {
    if (query.isNotEmpty) return _fetch(query);
    final supplier = context.read<ReceiveController>().supplier;
    if (supplier != null) return _fetch(query); // no cache when scoped
    final cached = FavoritesCache.get(widget.shop.id, 'receive');
    if (cached != null) {
      if (FavoritesCache.isStale(widget.shop.id, 'receive')) {
        unawaited(_refreshFavoritesInBackground());
      }
      return Future.value(cached);
    }
    return _fetch('').then((rows) {
      FavoritesCache.put(widget.shop.id, 'receive', rows);
      return rows;
    });
  }

  Future<void> _refreshFavoritesInBackground() async {
    try {
      final fresh = await _fetch('');
      if (!mounted) return;
      FavoritesCache.put(widget.shop.id, 'receive', fresh);
      if (_activeQuery.isEmpty &&
          context.read<ReceiveController>().supplier == null) {
        setState(() {
          _resultsFuture = Future.value(fresh);
        });
      }
    } catch (_) {
      // Best-effort.
    }
  }

  Future<List<ItemSearchResult>> _fetch(String query) async {
    final supplier = context.read<ReceiveController>().supplier;
    // #374: local mirror when offline_mode = full. Shop-wide last_cost from the
    // cached unit row is good enough for v1.
    if (useLocalDb(context)) {
      final repo = context.read<LocalRepository>();
      // Slice 3: empty query + a chosen supplier → their usual items first
      // (the supplier basket), ranked by how recently received. A supplier with
      // no history (empty basket), or any typed query, falls back to the normal
      // alphabetical item search — never a blank grid.
      if (query.trim().isEmpty && supplier != null) {
        final basket =
            await repo.supplierBasket(supplier.id, shopId: widget.shop.id);
        if (basket.isNotEmpty) return basket;
      }
      final items = await repo.searchItems(query, shopId: widget.shop.id);
      final results = <ItemSearchResult>[];
      for (final item in items) {
        results.add(await repo.toItemSearchResult(item, screen: 'receive'));
      }
      return results;
    }
    return context.read<ShopApi>().searchItems(
      shopId: widget.shop.id,
      query: query,
      screen: 'receive',
      locale: Localizations.localeOf(context).languageCode,
      partyId: supplier?.id,
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

  // Tap routing on a result tile:
  //   * Activated item with a default packaging → pre-fill the form.
  //   * Unactivated catalog row → run ensureShopItem first, then list
  //     the new shop_item's packagings (server creates a default base
  //     packaging when activating) and pre-fill the form from that.
  Future<void> _onTapTile(ItemSearchResult item) async {
    final l = tr(context);
    if (item.shopItemId != null && item.defaultShopItemUnitId != null) {
      setState(() {
        _selectedItem = _SelectedItem(
          shopItemUnitId: item.defaultShopItemUnitId!,
          shopItemId: item.shopItemId!,
          itemId: item.itemId,
          displayName: item.displayName,
          packagingLabel:
              item.packagingLabel ?? item.defaultUnitLabel ?? item.baseUnitLabel,
          baseUnitCode: item.baseUnitCode,
          baseUnitLabel: item.baseUnitLabel,
          perUnitCost: item.defaultUnitLastCost,
          learnedQty: item.learnedQty,
        );
      });
      return;
    }
    // Unactivated catalog row — itemId is set, shopItemId is null.
    final itemId = item.itemId;
    if (itemId == null) {
      // Defensive: search rows should always have one or the other.
      return;
    }
    setState(() => _activatingItemId = itemId);
    try {
      final api = context.read<ShopApi>();
      final newShopItemId = await api.ensureShopItem(
        shopId: widget.shop.id,
        itemId: itemId,
      );
      final units = await api.listShopItemUnits(
        shopId: widget.shop.id,
        shopItemId: newShopItemId,
        screen: 'receive',
      );
      if (!mounted) return;
      // Prefer the receive default; fall back to base unit, then first
      // entry. listShopItemUnits returns at least the base packaging
      // for every activated shop_item.
      final unit = _pickInitialUnit(units);
      if (unit == null) {
        showError(context, l.receiveLoadFailedMessage);
        return;
      }
      setState(() {
        _selectedItem = _SelectedItem(
          shopItemUnitId: unit.shopItemUnitId,
          shopItemId: newShopItemId,
          itemId: itemId,
          displayName: item.displayName,
          packagingLabel: unit.packagingLabel,
          baseUnitCode: item.baseUnitCode,
          baseUnitLabel: item.baseUnitLabel,
          perUnitCost: unit.lastCost,
        );
      });
    } on PostgrestException catch (error, stackTrace) {
      _reportError(error, stackTrace, 'ensure_shop_item');
      if (mounted) showError(context, l.receiveLoadFailedMessage);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace, 'ensure_shop_item');
      if (mounted) showError(context, l.receiveLoadFailedMessage);
    } finally {
      if (mounted) setState(() => _activatingItemId = null);
    }
  }

  ReceiveUnitOption? _pickInitialUnit(List<ReceiveUnitOption> units) {
    if (units.isEmpty) return null;
    for (final u in units) {
      if (u.isDefault) return u;
    }
    for (final u in units) {
      if (u.isBaseUnit) return u;
    }
    return units.first;
  }

  Future<void> _onAddNewItem(String query) async {
    // Opens the receive variant of the +Add new item sheet — same shape
    // as Sale, but the price field is optional (Receive only cares about
    // cost; sale price can be set later from Products). On save the new
    // packaging takes over as the currently-selected item so the inline
    // line composer pre-fills against it. No cart-style append: receive
    // composes one line at a time.
    final result = await AddNewItemSheet.show(
      context,
      widget.shop,
      initialName: query,
    );
    if (result == null || !mounted) return;
    // Clear the search bar — the cashier's intent ("find or add this
    // item") is fulfilled; the line composer below now owns focus.
    // Leaving the old query in place would keep the "+ Add new" tile
    // visible above an already-bound line, which looks like nothing
    // happened.
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _activeQuery = '';
      _resultsFuture = _fetchWithCache('');
      _selectedItem = _SelectedItem(
        shopItemUnitId: result.shopItemUnitId,
        shopItemId: result.shopItemId,
        itemId: null,
        displayName: result.displayName,
        packagingLabel: result.packagingLabel,
        baseUnitCode: result.baseUnitCode,
        baseUnitLabel: result.baseUnitLabel,
        // Newly-created item has no per-supplier last_cost yet — the
        // cashier types it from the bono.
        perUnitCost: null,
      );
    });
    // Move focus to the qty field so the cashier can start filling the
    // line immediately. Falls back gracefully if the qty field isn't
    // mounted yet (the post-frame callback waits for the rebuild).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusScope.of(context).unfocus();
    });
  }

  Future<void> _onAttachBono() async {
    if (_attachingBono) return;
    final l = tr(context);
    final source = await showModalBottomSheet<_BonoSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l.bonoAttachCamera),
              onTap: () => Navigator.of(context).pop(_BonoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l.bonoAttachGallery),
              onTap: () => Navigator.of(context).pop(_BonoSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    setState(() => _attachingBono = true);
    final picker = _picker ??=
        widget.bonoPicker ?? DefaultBonoImagePicker();
    try {
      final picked = source == _BonoSource.camera
          ? await picker.pickFromCamera()
          : await picker.pickFromGallery();
      if (picked == null || !mounted) return;
      final api = context.read<ShopApi>();
      final docId = await api.uploadBonoImage(
        shopId: widget.shop.id,
        bytes: picked.bytes,
        mimeType: picked.mimeType,
        fileExtension: picked.fileExtension,
      );
      if (!mounted) return;
      setState(() => _bonoDocumentId = docId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.bonoAttachedToast)),
      );
    } catch (error, stackTrace) {
      _reportError(error, stackTrace, 'upload bono');
      if (mounted) showError(context, l.bonoAttachFailedMessage);
    } finally {
      if (mounted) setState(() => _attachingBono = false);
    }
  }

  void _onChangeSupplier() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SupplierPickerScreen(shop: widget.shop),
      ),
    );
  }

  void _onAddLine({
    required String shopItemUnitId,
    required String shopItemId,
    required String? itemId,
    required String displayName,
    required String packagingLabel,
    required String baseUnitLabel,
    required num quantity,
    required num lineTotal,
    required String? originalShopItemUnitId,
  }) {
    final controller = context.read<ReceiveController>();
    if (originalShopItemUnitId != null &&
        originalShopItemUnitId != shopItemUnitId &&
        controller.lines.containsKey(originalShopItemUnitId)) {
      controller.switchLinePackaging(
        oldShopItemUnitId: originalShopItemUnitId,
        newShopItemUnitId: shopItemUnitId,
        shopItemId: shopItemId,
        itemId: itemId,
        displayName: displayName,
        packagingLabel: packagingLabel,
        baseUnitLabel: baseUnitLabel,
        quantity: quantity,
        lineTotal: lineTotal,
      );
    } else {
      controller.addOrReplaceLine(
        shopItemUnitId: shopItemUnitId,
        shopItemId: shopItemId,
        itemId: itemId,
        displayName: displayName,
        packagingLabel: packagingLabel,
        baseUnitLabel: baseUnitLabel,
        quantity: quantity,
        lineTotal: lineTotal,
      );
    }
    setState(() {
      _selectedItem = null;
      _linesExpanded = true;
    });
  }

  void _onRemoveLine(String key) {
    final controller = context.read<ReceiveController>();
    controller.removeLine(key);
    if (controller.isEmpty) {
      setState(() => _linesExpanded = false);
    }
  }

  Future<void> _onConfirmClearLines() async {
    final l = tr(context);
    final controller = context.read<ReceiveController>();
    final count = controller.lineCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l.receiveLinesClearConfirmTitle(count)),
        content: Text(l.receiveLinesClearConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l.receiveLinesClearConfirmNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l.receiveLinesClearConfirmYes),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      controller.clearLines();
      setState(() => _linesExpanded = false);
    }
  }

  void _onToggleLinesExpand() {
    final controller = context.read<ReceiveController>();
    if (controller.isEmpty) return;
    setState(() => _linesExpanded = !_linesExpanded);
  }

  Future<void> _save() async {
    final l = tr(context);
    final controller = context.read<ReceiveController>();
    final supplier = controller.supplier;
    if (supplier == null) {
      showError(context, l.receiveNeedSupplierMessage);
      return;
    }
    if (controller.isEmpty) {
      showError(context, l.receiveNeedLinesMessage);
      return;
    }

    Timing.mark('save.tapped');
    setState(() => _saving = true);
    final api = context.read<ShopApi>();
    final snapshot = controller.snapshot();
    final clientOpId = generateClientOpId('receive');
    final lines = <ReceiveLinePayload>[
      for (final line in snapshot.lines.values)
        ReceiveLinePayload(
          shopItemUnitId: line.shopItemUnitId,
          quantity: line.quantity,
          lineTotal: line.lineTotal,
        ),
    ];
    final total = lines.fold<num>(0, (sum, l) => sum + l.lineTotal);
    // Projection lines for the optimistic stock bump (+1 = stock in).
    final stockLines = [
      for (final line in lines)
        ProjectionLine(
          shopItemUnitId: line.shopItemUnitId,
          quantity: line.quantity,
          direction: 1,
        ),
    ];

    // #383: useLocalDb=false → direct-await path. No optimistic
    // clear, no queue, no projection. Lines stay on screen until
    // server confirms success (or shows error on failure so
    // cashier can retry).
    if (!useLocalDb(context)) {
      await _saveDirect(
        api: api,
        controller: controller,
        l: l,
        supplierId: supplier.id,
        snapshot: snapshot,
        lines: lines,
        clientOpId: clientOpId,
      );
      return;
    }

    // #385: optimistic write to local_transaction BEFORE we
    // clear the lines so Receive History reflects this bono
    // instantly (no waiting for delta sync or realtime). The
    // server-authoritative row replaces this one (dedup by
    // client_op_id) when delta sync brings it back, whether
    // the post goes through the direct path or the queue.
    final localRepoForOptimistic = context.read<LocalRepository>();
    try {
      var lineNo = 1;
      final linesSummary = snapshot.lines.values
          .map((l) => <String, dynamic>{
                'line_no': lineNo++,
                'item_id': l.itemId,
                'shop_item_unit_id': l.shopItemUnitId,
                'item_name': l.displayName,
                'unit_code': l.baseUnitLabel,
                'unit_label': l.baseUnitLabel,
                'packaging_label': l.packagingLabel,
                'quantity': l.quantity.toDouble(),
                'unit_amount': l.unitCost.toDouble(),
                'line_total': l.lineTotal.toDouble(),
              })
          .toList();
      await localRepoForOptimistic.writeOptimisticTransaction(
        clientOpId: clientOpId,
        shopId: widget.shop.id,
        typeCode: 'receive',
        occurredAtMs: DateTime.now().millisecondsSinceEpoch,
        total: total,
        partyId: supplier.id,
        payload: <String, dynamic>{
          'party_name': supplier.name,
          'payment_method_code': null,
          'paid_amount': 0,
          'lines_summary': linesSummary,
        },
      );
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'dukan receive',
        context: ErrorDescription('write optimistic receive transaction'),
      ));
    }
    // Slice 3: float the just-received items to the top of this supplier's
    // basket immediately; next items-sync reconciles to supplier_item_unit_cost.
    try {
      await localRepoForOptimistic.applyOptimisticSupplierBasket(
        supplierId: supplier.id,
        shopId: widget.shop.id,
        shopItemUnitIds: snapshot.lines.values
            .map((l) => l.shopItemUnitId)
            .toList(growable: false),
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'dukan receive',
        context: ErrorDescription('optimistic supplier basket bump'),
      ));
    }
    // Optimistic stock + supplier balance so Products and the suppliers LIST
    // reflect the receive instantly — they read current_stock / local_party
    // .payable directly (only the dashboard saw the optimistic txn before).
    // The next items/parties sync replaces these with the server truth;
    // reverted below if the server rejects the bono.
    try {
      await localRepoForOptimistic.applyOptimisticStockForLines(
        lines: stockLines,
      );
      await localRepoForOptimistic.applyOptimisticPartyCharge(
        partyId: supplier.id,
        direction: 'O',
        amount: total,
      );
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'dukan receive',
        context: ErrorDescription('optimistic receive stock/balance'),
      ));
    }

    if (!mounted) return;
    // Optimistic clear (useLocalDb=true) so the screen returns to
    // fresh state immediately. Lines wipe; supplier stays so the
    // cashier could resume a second bono from the same supplier
    // without re-picking.
    controller.clearLines();
    setState(() => _linesExpanded = false);
    Timing.mark('lines.cleared');
    Timing.endFlow(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.receiveSavedToast)),
    );

    try {
      await api.postReceive(
        shopId: widget.shop.id,
        partyId: supplier.id,
        lines: lines,
        // Always fully credit; cash payment is a separate Payment step.
        paidAmount: 0,
        paymentMethodCode: null,
        documentId: _bonoDocumentId,
        clientOpId: clientOpId,
      );

      if (mounted) {
        controller.clearAll();
        setState(() => _bonoDocumentId = null);
        Navigator.of(context).maybePop();
      }
    } on PostgrestException catch (error, stackTrace) {
      // 4xx-style server reject — won't succeed on retry. Revert the optimistic
      // stock + balance bumps (the bono didn't post; lines are restored for a
      // retry, so a lingering bump would double-count), then restore the
      // snapshot so the cashier can correct the issue.
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
        await localRepoForOptimistic.applyOptimisticPartyPayment(
          partyId: supplier.id,
          direction: 'O',
          amount: total,
        );
      } catch (_) {/* best-effort revert; sync reconciles regardless */}
      _handleSaveFailure(snapshot, error, stackTrace, l.receivePostFailedMessage);
    } catch (error, stackTrace) {
      // Network / transient — enqueue for the offline write queue to
      // retry on backoff. Lines stay cleared (already cleared above)
      // and the bono documentId rides along in the queued params so
      // the bono Storage object isn't orphaned. The queue's
      // `client_op_id` mirrors the server-side idempotency guarantee.
      // Mirrors sale_screen.dart's pattern from #320.
      _reportError(error, stackTrace, 'post_receive (queuing for retry)');
      if (!mounted) return;
      String actorId = '';
      try {
        actorId = Supabase.instance.client.auth.currentUser?.id ?? '';
      } catch (_) {
        actorId = '';
      }
      final post = PendingPost(
        id: generateClientOpId('receive'),
        clientOpId: clientOpId,
        shopId: widget.shop.id,
        originalActorUserId: actorId,
        rpc: 'post_receive',
        params: buildPostReceiveParams(
          partyId: supplier.id,
          lines: lines,
          paidAmount: 0,
          documentId: _bonoDocumentId,
        ),
        queuedAt: DateTime.now(),
      );
      // Stock + supplier balance were already bumped optimistically up-front in
      // _save (current_stock / local_party.payable), so the in-flight receive
      // shows in Products + the suppliers list until the queued post drains and
      // the items/parties sync replaces them with the server values. No stock
      // projection needed here (the bump lives directly in current_stock).
      final queue = context.read<OfflineQueueController>();
      await queue.enqueue(post);
      if (mounted) {
        controller.clearAll();
        setState(() => _bonoDocumentId = null);
        Navigator.of(context).maybePop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _handleSaveFailure(
    ReceiveSnapshot snapshot,
    Object error,
    StackTrace stackTrace,
    String message,
  ) {
    _reportError(error, stackTrace, 'post_receive');
    if (!mounted) return;
    context.read<ReceiveController>().restore(snapshot);
    showError(context, message);
  }

  /// #383: direct-post path for useLocalDb=false. Awaits the
  /// post inline; clears form + pops on success; shows error and
  /// keeps lines on failure so cashier can retry.
  Future<void> _saveDirect({
    required ShopApi api,
    required ReceiveController controller,
    required L10n l,
    required String supplierId,
    required ReceiveSnapshot snapshot,
    required List<ReceiveLinePayload> lines,
    required String clientOpId,
  }) async {
    try {
      await api.postReceive(
        shopId: widget.shop.id,
        partyId: supplierId,
        lines: lines,
        paidAmount: 0,
        paymentMethodCode: null,
        documentId: _bonoDocumentId,
        clientOpId: clientOpId,
      );
      if (!mounted) return;
      controller.clearAll();
      setState(() {
        _bonoDocumentId = null;
        _linesExpanded = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.receiveSavedToast)),
      );
      Navigator.of(context).maybePop();
    } catch (error, stackTrace) {
      _reportError(error, stackTrace, 'post_receive (useLocalDb=false)');
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, '${l.receivePostFailedMessage}\n$error');
    }
  }

  void _reportError(Object error, StackTrace stackTrace, String op) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan receive',
        context: ErrorDescription(op),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final controller = context.watch<ReceiveController>();
    final supplier = controller.supplier;
    return Scaffold(
      appBar: dukanAppBar(
        context,
        supplier == null ? l.receiveTitle : l.receiveFrom(supplier.name),
        actions: [
          IconButton(
            tooltip: _bonoDocumentId == null
                ? l.bonoAttachTooltip
                : l.bonoAttachedTooltip,
            icon: _attachingBono
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _bonoDocumentId == null
                        ? Icons.photo_camera_outlined
                        : Icons.check_circle,
                    color: _bonoDocumentId == null
                        ? null
                        : Theme.of(context).colorScheme.primary,
                  ),
            onPressed: _saving || _attachingBono ? null : _onAttachBono,
          ),
          IconButton(
            tooltip: l.receiveHistoryTooltip,
            icon: const Icon(Icons.history),
            onPressed: _saving
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReceiveHistoryScreen(shop: widget.shop),
                    ),
                  ),
          ),
          IconButton(
            tooltip: l.supplierPickerTitle,
            icon: const Icon(Icons.swap_horiz),
            onPressed: _saving ? null : _onChangeSupplier,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                // Mirror the Sale search field — Somali item names
                // ("hilib", "ware") get mangled by OS autocorrect into
                // English near-matches. Aliases on the index already
                // handle partial matches.
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l.receiveSearchHint,
                  suffixIcon: Tooltip(
                    message:
                        '${l.scanCameraTooltip} · ${l.multiScanLongPressHint}',
                    child: InkResponse(
                      onTap: _onScanTap,
                      onLongPress: _onMultiScanTap,
                      radius: 24,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.qr_code_scanner),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_unknownScan != null)
              _ReceiveUnknownScanPill(
                code: _unknownScan!,
                onDismiss: () => setState(() => _unknownScan = null),
              ),
            Expanded(
              child: FutureBuilder<List<ItemSearchResult>>(
                future: _resultsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l.receiveLoadFailedMessage,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    );
                  }
                  final results = snapshot.data ?? const <ItemSearchResult>[];
                  // Append a synthetic "+ Add new item" row when the
                  // cashier has typed >= 3 chars — same affordance as
                  // Sale. The tile is rendered with full-width by
                  // straddling all three grid columns visually (we just
                  // render it in the grid; consistent footprint).
                  final showAddNew = _activeQuery.length >= 3;
                  if (results.isEmpty && !showAddNew) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _activeQuery.isEmpty
                              ? l.receiveEmptyMessage
                              : l.saleSearchEmptyMessage(_activeQuery),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    );
                  }
                  // Promote +Add new above the grid so partial matches
                  // never hide the "this isn't here, add it" escape hatch.
                  return Column(
                    children: [
                      if (showAddNew)
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(10, 0, 10, 8),
                          child: _AddNewItemBanner(
                            query: _activeQuery,
                            onTap: _saving
                                ? null
                                : () => _onAddNewItem(_activeQuery),
                          ),
                        ),
                      Expanded(
                        child: GridView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(10, 4, 10, 8),
                          // Two columns × ~110dp — denser tile so the
                          // name + cost don't float in whitespace.
                          // Matches Sale.
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            mainAxisExtent: 110,
                          ),
                          itemCount: results.length,
                          itemBuilder: (context, i) {
                            final item = results[i];
                            final selectedShopItemId =
                                _selectedItem?.shopItemId;
                            final isSelected = selectedShopItemId !=
                                    null &&
                                item.shopItemId == selectedShopItemId;
                            final isActivating =
                                _activatingItemId != null &&
                                    item.itemId == _activatingItemId;
                            return _ReceiveItemTile(
                              shop: widget.shop,
                              item: item,
                              selected: isSelected,
                              activating: isActivating,
                              onTap: (_saving ||
                                      _activatingItemId != null)
                                  ? null
                                  : () => _onTapTile(item),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (_selectedItem != null)
              _LineEntryForm(
                key: ValueKey(_selectedItem!.shopItemId),
                shop: widget.shop,
                selected: _selectedItem!,
                saving: _saving,
                onAddLine: _onAddLine,
                onCancel: () => setState(() => _selectedItem = null),
              ),
            _ReceiveLinesStrip(
              shop: widget.shop,
              lines: controller.lines,
              lineCount: controller.lineCount,
              bonoTotal: controller.bonoTotal,
              expanded: _linesExpanded,
              saving: _saving,
              onToggleExpand: _onToggleLinesExpand,
              onRemoveLine: _onRemoveLine,
              onClearAll: _onConfirmClearLines,
              onSave: _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// Working state for a line the cashier is composing. Decoupled from
/// `ItemSearchResult` because the form may have switched packaging
/// after the initial tap — `shopItemUnitId`, `packagingLabel`, and
/// `perUnitCost` track the *current* packaging, not the search row.
class _SelectedItem {
  const _SelectedItem({
    required this.shopItemUnitId,
    required this.shopItemId,
    required this.itemId,
    required this.displayName,
    required this.packagingLabel,
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required this.perUnitCost,
    this.learnedQty,
  });

  final String shopItemUnitId;
  final String shopItemId;
  final String? itemId;
  final String displayName;
  final String packagingLabel;

  /// Slice 4: learned usual receive quantity for this packaging; seeds a chip.
  final num? learnedQty;
  /// Drives the AddPackagingSheet's suggestion query + custom-unit
  /// filtering (the cashier can't pick the item's own base unit again).
  final String baseUnitCode;
  final String baseUnitLabel;

  /// Supplier-specific when the search was called with `partyId`;
  /// otherwise the shop-wide last cost for this packaging.
  final double? perUnitCost;
}

class _ReceiveItemTile extends StatelessWidget {
  const _ReceiveItemTile({
    required this.shop,
    required this.item,
    required this.selected,
    required this.activating,
    required this.onTap,
  });

  final ShopSummary shop;
  final ItemSearchResult item;
  final bool selected;
  final bool activating;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final costText = item.defaultUnitLastCost == null
        ? tr(context).lineEditorTilePriceMissing
        : formatMoney(item.defaultUnitLastCost!, shop);
    final packaging =
        item.packagingLabel ?? item.defaultUnitLabel ?? item.baseUnitLabel;
    final low = isLowStock(currentStock: item.currentStock);
    final stockText = item.currentStock == null
        ? null
        : formatCompoundStock(
            stock: item.currentStock!,
            baseLabel: item.baseUnitLabel,
            packagingLabel: item.defaultUnitLabel,
            conversion: item.defaultUnitConversionToBase,
          );
    return Card(
      color: selected ? theme.colorScheme.primaryContainer : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
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
                    '$packaging · $costText',
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
                        fontWeight: low ? FontWeight.w700 : FontWeight.w400,
                        color: low
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (activating)
              Positioned.fill(
                child: Container(
                  color: theme.colorScheme.surface.withValues(alpha: 0.6),
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Full-width banner shown above the partial-match grid when the cashier
/// has typed ≥3 chars. Mirrors the Sale variant so both flows feel
/// identical.
class _AddNewItemBanner extends StatelessWidget {
  const _AddNewItemBanner({required this.query, required this.onTap});

  final String query;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
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

// Qty + line total composer. Bonos consistently show line totals
// ("5 bag rice $120"), not per-unit cost — so we ask for the total
// only. Per-packaging cost is computed and shown as a small grey
// "= $24 per bag" caption so the cashier can sanity-check without
// having to fill another field.
//
// The packaging chip is tappable: opens the unit picker so the cashier
// can swap from the default (e.g., 25 kg bag) to another packaging.
// Switching packaging mid-edit is supported — ADD LINE then routes
// through `switchLinePackaging` so any stale row for the original
// packaging is removed in the same notify.
class _LineEntryForm extends StatefulWidget {
  const _LineEntryForm({
    required this.shop,
    required this.selected,
    required this.saving,
    required this.onAddLine,
    required this.onCancel,
    super.key,
  });

  final ShopSummary shop;
  final _SelectedItem selected;
  final bool saving;
  final void Function({
    required String shopItemUnitId,
    required String shopItemId,
    required String? itemId,
    required String displayName,
    required String packagingLabel,
    required String baseUnitLabel,
    required num quantity,
    required num lineTotal,
    required String? originalShopItemUnitId,
  })
  onAddLine;
  final VoidCallback onCancel;

  @override
  State<_LineEntryForm> createState() => _LineEntryFormState();
}

class _LineEntryFormState extends State<_LineEntryForm> {
  late final TextEditingController _qtyController;
  late final TextEditingController _totalController;
  // Currently selected packaging. Starts as the one the cashier tapped
  // on the search tile; the unit picker can swap it. Carries the
  // identity sent to post_receive plus the chip label rendered above.
  // The "original" packaging (the one the form opened with) is read
  // from `widget.selected.shopItemUnitId` on ADD LINE so the screen
  // can route through `switchLinePackaging` if it was swapped.
  late String _shopItemUnitId;
  late String _packagingLabel;

  @override
  void initState() {
    super.initState();
    _shopItemUnitId = widget.selected.shopItemUnitId;
    _packagingLabel = widget.selected.packagingLabel;
    _qtyController = TextEditingController(text: '1');
    // Pre-fill the line total from last cost × qty so a familiar bono
    // line lands in one tap. The cashier always corrects to whatever
    // the paper says.
    final perUnit = widget.selected.perUnitCost ?? 0;
    _totalController = TextEditingController(
      text: perUnit > 0 ? _formatField(perUnit * 1) : '',
    );
    _qtyController.addListener(_onChanged);
    _totalController.addListener(_onChanged);
  }

  Future<void> _onTapUnit() async {
    final picked = await showUnitPicker(
      context,
      shopId: widget.shop.id,
      shopItemId: widget.selected.shopItemId,
      screen: 'receive',
      baseUnitCode: widget.selected.baseUnitCode,
      baseUnitLabel: widget.selected.baseUnitLabel,
    );
    if (picked == null || !mounted) return;
    if (picked.shopItemUnitId == _shopItemUnitId) return;
    setState(() {
      _shopItemUnitId = picked.shopItemUnitId;
      _packagingLabel = picked.packagingLabel;
      // Re-pre-fill the total from the new packaging's last_cost ×
      // current qty so the cashier doesn't lose their typed qty just
      // because they corrected the packaging.
      final newCost = picked.lastCost;
      final qty = num.tryParse(_qtyController.text.trim()) ?? 0;
      if (newCost != null && newCost > 0 && qty > 0) {
        _totalController.text = _formatField(newCost * qty);
      } else {
        _totalController.text = '';
      }
    });
  }

  @override
  void dispose() {
    _qtyController.removeListener(_onChanged);
    _totalController.removeListener(_onChanged);
    _qtyController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  num? _parse(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final v = num.tryParse(t);
    if (v == null || v < 0) return null;
    return v;
  }

  String _formatField(num value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Derived per-packaging cost shown as a small caption under the
  /// total field. Null when qty or total aren't yet typed; surfacing
  /// "= /0 per bag" would be noise.
  num? get _derivedPerUnit {
    final qty = _parsedQty;
    final total = _parse(_totalController.text);
    if (qty == null || qty <= 0 || total == null || total <= 0) return null;
    return total / qty;
  }

  num? get _parsedQty {
    final raw = _qtyController.text.trim();
    if (raw.isEmpty) return null;
    final v = num.tryParse(raw);
    if (v == null || v <= 0) return null;
    return v;
  }

  bool get _canAdd {
    final qty = _parsedQty;
    final total = _parse(_totalController.text);
    return qty != null && total != null && total > 0;
  }

  void _onAdd() {
    final qty = _parsedQty!;
    final total = _parse(_totalController.text)!;
    widget.onAddLine(
      shopItemUnitId: _shopItemUnitId,
      shopItemId: widget.selected.shopItemId,
      itemId: widget.selected.itemId,
      displayName: widget.selected.displayName,
      packagingLabel: _packagingLabel,
      baseUnitLabel: widget.selected.baseUnitLabel,
      quantity: qty,
      lineTotal: total,
      originalShopItemUnitId: widget.selected.shopItemUnitId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayName(widget.selected.displayName),
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.saving ? null : widget.onCancel,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  // Wide enough to fit "Tirada" (Somali, longest of the
                  // qty labels we use) without truncation.
                  width: 110,
                  child: TextField(
                    controller: _qtyController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      // Decimal-friendly so loose weighed items (12.5 kg
                      // of meat) can land on a bono.
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: l.receiveLineQuantityLabel,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Packaging chip — the v2 key UX win. Renders the full
                // packaging label (e.g., "25 kg bag") prominently so
                // the cashier can verify they're entering against the
                // right packaging before typing numbers.
                Expanded(
                  child: InkWell(
                    onTap: widget.saving ? null : _onTapUnit,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _packagingLabel,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.arrow_drop_down, size: 22),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Slice 4: quick-tap quantity chips (learned usual + defaults).
            QuantityChips(
              learnedQty: widget.selected.learnedQty,
              onSelected: (v) {
                _qtyController.text = formatQty(v);
                _qtyController.selection = TextSelection.collapsed(
                  offset: _qtyController.text.length,
                );
              },
            ),
            const SizedBox(height: 8),
            // One money field only: the line total straight off the
            // bono. Per-packaging cost is derived and shown as a small
            // caption below so the cashier can sanity-check without
            // having to fill an extra field.
            TextField(
              controller: _totalController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText:
                    l.receiveLineTotalLabel(widget.shop.currencySymbol),
                isDense: true,
              ),
            ),
            if (_derivedPerUnit != null) ...[
              const SizedBox(height: 4),
              Text(
                l.receiveLineDerivedPerUnit(
                  formatMoney(_derivedPerUnit!, widget.shop),
                  _packagingLabel,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: widget.saving || !_canAdd ? null : _onAdd,
                child: Text(l.receiveAddLineButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiveLinesStrip extends StatelessWidget {
  const _ReceiveLinesStrip({
    required this.shop,
    required this.lines,
    required this.lineCount,
    required this.bonoTotal,
    required this.expanded,
    required this.saving,
    required this.onToggleExpand,
    required this.onRemoveLine,
    required this.onClearAll,
    required this.onSave,
  });

  final ShopSummary shop;
  final Map<String, ReceiveLine> lines;
  final int lineCount;
  final double bonoTotal;
  final bool expanded;
  final bool saving;
  final VoidCallback onToggleExpand;
  final void Function(String key) onRemoveLine;
  final VoidCallback onClearAll;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final canSave = lineCount > 0 && !saving;
    final canExpand = lineCount > 0;
    final maxListHeight = MediaQuery.of(context).size.height * 0.25;
    final entries = lines.entries.toList(growable: false);
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
                                : Icons.inventory_2_outlined,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.receiveLinesSummary(
                                lineCount,
                                formatMoney(bonoTotal, shop),
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
                    child: Text(l.receiveLinesClearAllButton),
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
                      child: _ReceiveLineList(
                        shop: shop,
                        entries: entries,
                        saving: saving,
                        onRemoveLine: onRemoveLine,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
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
                    : Text(l.receiveSaveButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiveLineList extends StatefulWidget {
  const _ReceiveLineList({
    required this.shop,
    required this.entries,
    required this.saving,
    required this.onRemoveLine,
  });

  final ShopSummary shop;
  final List<MapEntry<String, ReceiveLine>> entries;
  final bool saving;
  final void Function(String key) onRemoveLine;

  @override
  State<_ReceiveLineList> createState() => _ReceiveLineListState();
}

class _ReceiveLineListState extends State<_ReceiveLineList> {
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
        itemCount: widget.entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final entry = widget.entries[i];
          return _ReceiveLineTile(
            shop: widget.shop,
            line: entry.value,
            enabled: !widget.saving,
            onRemove: () => widget.onRemoveLine(entry.key),
          );
        },
      ),
    );
  }
}

class _ReceiveLineTile extends StatelessWidget {
  const _ReceiveLineTile({
    required this.shop,
    required this.line,
    required this.enabled,
    required this.onRemove,
  });

  final ShopSummary shop;
  final ReceiveLine line;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    // l.receiveLineSubtotal signature is (quantity, total, unit) — the
    // localization gen sorts placeholders alphabetically so the order
    // here does NOT match the template's left-to-right reading. The
    // packaging label is the v2 unit identity (e.g., "25 kg bag").
    final subtitle = l.receiveLineSubtotal(
      '${line.quantity}',
      formatMoney(line.lineTotal, shop),
      line.packagingLabel,
    );
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(
        line.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle),
      trailing: IconButton(
        tooltip: l.receiveLineRemoveTooltip(line.displayName),
        icon: const Icon(Icons.close, size: 20),
        onPressed: enabled ? onRemove : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }
}

/// Top-of-screen pill shown after a Receive-side scan that matches no
/// shop_item. Receive intentionally doesn't surface "Create new" today
/// — Receive flow assumes the product already exists in the catalog; if
/// the supplier brought something brand-new, the cashier creates it from
/// the search bar ("+ Add new") then scans again. The "Bind to existing"
/// flow ships with Product-detail scan in a later phase.
class _ReceiveUnknownScanPill extends StatelessWidget {
  const _ReceiveUnknownScanPill({
    required this.code,
    required this.onDismiss,
  });

  final String code;
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
