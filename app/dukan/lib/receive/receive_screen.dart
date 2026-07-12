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
import 'package:dukan/receive/bono_image_cache.dart';
import 'package:dukan/receive/bono_photo_view.dart';
import 'package:dukan/receive/bono_review_screen.dart';
import 'package:dukan/receive/bono_suggestion_review_sheet.dart';
import 'package:dukan/shared/realtime.dart';
import 'package:dukan/observability/timing.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/pending_post.dart';
import 'package:dukan/queue/queue_status_pill.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/scanner/hid_listener.dart';
import 'package:dukan/scanner/multi_scan_sheet.dart';
import 'package:dukan/scanner/scan_event.dart';
import 'package:dukan/scanner/scan_lookup.dart';
import 'package:dukan/search/connectivity_status.dart';
import 'package:dukan/search/search_service.dart';
import 'package:dukan/scanner/scanner_settings.dart';
import 'package:dukan/scanner/scanner_sheet.dart';
import 'package:dukan/shared/bono_image_picker.dart';
import 'package:dukan/shared/dismiss_keyboard.dart';
import 'package:dukan/shared/expandable_line_list.dart';
import 'package:dukan/shared/item_grid.dart';
import 'package:dukan/shared/working_date.dart';
import 'package:dukan/shared/client_op_id.dart';
import 'package:dukan/shared/display_name.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/favorites_cache.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/low_stock.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/shared/stock_format.dart';
import 'package:dukan/shared/typography.dart';

enum _BonoSource { camera, gallery }

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({required this.shop, this.bonoPicker, super.key});

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
  final _searchFocus = FocusNode();
  late Future<List<ItemSearchResult>> _resultsFuture;
  String _activeQuery = '';
  Timer? _debounce;
  bool _saving = false;
  bool _attachingBono = false;
  String? _bonoDocumentId;
  BonoImagePicker? _picker;
  bool _linesExpanded = false;
  // Full/review mode: grow the bono-lines drawer to fill the screen so a long
  // bono can be reviewed. Reset whenever the drawer collapses.
  bool _linesFull = false;
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

  // Bono OCR suggestions. Armed when a bono is attached; filled once the async
  // OCR pipeline writes document.ocr_result (via realtime on the document row,
  // with a poll fallback). Server-only + inert offline — any fetch error just
  // leaves the banner absent. See docs/bono-ocr-prepopulate.md.
  List<BonoSuggestion> _bonoSuggestions = const [];
  // True from a successful (online) upload until the review is ready, the OCR
  // times out, or the cashier dismisses it — drives the "Reading the bono…"
  // banner so there's no silence between attach and the review appearing.
  bool _bonoLoading = false;
  // OCR poll finished with nothing (failed / junk photo). Shows a brief
  // dismissible "enter by hand" note so the miss is visible, not silent.
  bool _bonoOcrMissed = false;
  bool _bonoSuggestionsDismissed = false;
  // First-use teaching hint in the empty state. Session-scoped (no persistence):
  // it vanishes the moment a line is added or a bono attached, so an experienced
  // cashier barely sees it, while a new one learns the photo shortcut exists.
  bool _bonoHintDismissed = false;
  RealtimeWatcher? _bonoWatcher;
  Timer? _bonoPoll;
  int _bonoPollTicks = 0;

  @override
  void initState() {
    super.initState();
    final receiveCtrl = context.read<ReceiveController>();
    _linesExpanded = receiveCtrl.isNotEmpty;
    // Backdating (#5): reset to today on fresh entry (sticky within a session).
    receiveCtrl.initWorkingDate();
    _searchFocus.addListener(_onSearchFocusChanged);
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
    final repo = useLocalDb(context) ? context.read<LocalRepository>() : null;
    final online = context.read<ConnectivityStatus>().online;
    final receiveCtrl = context.read<ReceiveController>();
    final locale = Localizations.localeOf(context).languageCode;
    final supplierId = receiveCtrl.supplier?.id;
    final l = tr(context);

    final result = await MultiScan.open(
      context,
      // Offline-first per scan, same resolution as single-scan.
      resolver: (code) => resolveScannedCode(
        repo: repo,
        api: api,
        online: online,
        shopId: shopId,
        code: code,
        screen: 'receive',
        locale: locale,
        partyId: supplierId,
      ),
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
      // Offline-first via the local mirror when use_local_db; thin client
      // uses the network search_items barcode probe.
      final repo = useLocalDb(context) ? context.read<LocalRepository>() : null;
      final result = await resolveScannedCode(
        repo: repo,
        api: context.read<ShopApi>(),
        online: context.read<ConnectivityStatus>().online,
        shopId: widget.shop.id,
        code: event.code,
        screen: 'receive',
        locale: Localizations.localeOf(context).languageCode,
        partyId: context.read<ReceiveController>().supplier?.id,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() => _unknownScan = event.code);
        return;
      }
      setState(() => _unknownScan = null);
      // Reuse the normal tile-tap path so the form pre-fills from the
      // matched packaging's defaults, exactly like a manual tap would.
      await _onTapTile(result);
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
    _searchFocus.dispose();
    _debounce?.cancel();
    _bonoPoll?.cancel();
    _bonoWatcher?.dispose();
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
    // Slice 3: empty query + a chosen supplier → their usual items first (the
    // supplier basket, from the local mirror), ranked by how recently received.
    // A supplier with no history, or any typed query, falls through to the
    // shared local-first + online-fallback item search — never a blank grid.
    if (query.trim().isEmpty && supplier != null && useLocalDb(context)) {
      final basket = await context.read<LocalRepository>().supplierBasket(
            supplier.id,
            shopId: widget.shop.id,
          );
      if (basket.isNotEmpty) return basket;
    }
    return searchItems(
      context,
      shopId: widget.shop.id,
      query: query,
      screen: 'receive',
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
              item.packagingLabel ??
              item.defaultUnitLabel ??
              item.baseUnitLabel,
          baseUnitCode: item.baseUnitCode,
          baseUnitLabel: item.baseUnitLabel,
          perUnitCost: item.defaultUnitLastCost,
          learnedQty: item.learnedQty,
        );
      });
      // Drop the search focus so the keyboard dismisses and the
      // line-entry form gets room (it's hidden while search is focused,
      // so the results grid isn't covered). See _onSearchFocusChanged.
      _searchFocus.unfocus();
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
      // Same as the fast path: dismiss the keyboard so the line-entry
      // form has room and the results grid isn't covered.
      _searchFocus.unfocus();
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
    final picker = _picker ??= widget.bonoPicker ?? DefaultBonoImagePicker();
    final api = context.read<ShopApi>();
    final cache = context.read<BonoImageCache>();
    final queue = context.read<OfflineQueueController>();
    final shopId = widget.shop.id;
    try {
      final picked = source == _BonoSource.camera
          ? await picker.pickFromCamera()
          : await picker.pickFromGallery();
      if (picked == null || !mounted) return;

      // Client-minted id + path (works offline). Start caching the bytes
      // IMMEDIATELY, in parallel with the upload, so the record is safe from the
      // first moment (even offline / if the app is killed mid-upload) — but
      // don't block the online banner on the BLOB write. Online: upload first so
      // the document + OCR start right away; flag the cache uploaded in the
      // background. Offline: await the cache write, then defer the upload.
      final docId = generateUuidV4();
      final path = api.bonoStoragePath(shopId, docId, picked.fileExtension);
      final ext = picked.fileExtension;
      final bytes = picked.bytes;
      final mime = picked.mimeType;
      final cached = cache.put(
        documentId: docId,
        shopId: shopId,
        ext: ext,
        bytes: bytes,
      );
      // Only the online path starts OCR now; offline defers it to sync, so we
      // don't spin "Reading the bono…" when nothing is reading yet.
      var uploaded = false;
      try {
        await api.uploadBonoImageAt(
          shopId: shopId,
          documentId: docId,
          storagePath: path,
          bytes: bytes,
          mimeType: mime,
        );
        uploaded = true;
        // Uploaded — mark the cache entry uploaded (evictable) in the background.
        unawaited(cached
            .then((_) => cache.markUploaded(docId))
            .then((_) => cache.evictToLimit())
            .catchError((_) {}));
      } catch (error, stackTrace) {
        // Offline / transient — ensure the bytes are cached, then defer the
        // upload. The queue classifies permanent vs transient.
        _reportError(error, stackTrace, 'upload bono (queuing for retry)');
        try {
          await cached;
        } catch (_) {}
        String actorId = '';
        try {
          actorId = Supabase.instance.client.auth.currentUser?.id ?? '';
        } catch (_) {
          actorId = '';
        }
        await queue.enqueue(PendingPost(
          id: generateClientOpId('bono'),
          clientOpId: generateClientOpId('bono'),
          shopId: shopId,
          originalActorUserId: actorId,
          rpc: 'upload_bono_image',
          params: buildUploadBonoImageParams(
            documentId: docId,
            storagePath: path,
            mimeType: mime,
            sizeBytes: bytes.length,
          ),
          queuedAt: DateTime.now(),
        ));
        unawaited(cache.evictToLimit());
      }
      if (!mounted) return;
      _armBonoSuggestions(docId, expectOcr: uploaded);
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.bonoAttachedToast)));
    } catch (error, stackTrace) {
      // Failed before we could cache/queue (e.g. the picker) — can't defer.
      _reportError(error, stackTrace, 'attach bono');
      if (mounted) showError(context, l.bonoAttachFailedMessage);
    } finally {
      if (mounted) setState(() => _attachingBono = false);
    }
  }

  // Watch the document row for its OCR result, with a poll fallback. The
  // suggest RPC returns empty until OCR writes document.ocr_result, so we
  // re-fetch on each document-row change and, as a backstop, every 3s up to
  // ~30s. Inert offline (RealtimeWatcher is null, fetches throw and are eaten).
  void _armBonoSuggestions(String docId, {bool expectOcr = true}) {
    _resetBonoState();
    _bonoDocumentId = docId;
    _bonoLoading = expectOcr;
    _bonoWatcher = RealtimeWatcher.tryCreate(
      channelName: 'bono_ocr:$docId',
      subscriptions: [
        RealtimeSubscription(
          table: 'document',
          filter: realtimeEq('id', docId),
        ),
      ],
      onChange: () => _fetchBonoSuggestions(docId),
    );
    _bonoPoll = Timer.periodic(const Duration(seconds: 3), (timer) {
      _bonoPollTicks += 1;
      if (_bonoSuggestions.isNotEmpty || _bonoPollTicks > 10) {
        timer.cancel();
        // Timed out with no result (OCR failed / junk image) → drop the spinner
        // so it never hangs, and surface a dismissible "enter by hand" note so
        // the miss is visible rather than silent.
        if (mounted && _bonoLoading && _bonoSuggestions.isEmpty) {
          setState(() {
            _bonoLoading = false;
            _bonoOcrMissed = true;
          });
        }
        return;
      }
      _fetchBonoSuggestions(docId);
    });
  }

  Future<void> _fetchBonoSuggestions(String docId) async {
    if (!mounted || _bonoDocumentId != docId) return;
    final supplierId = context.read<ReceiveController>().supplier?.id;
    if (supplierId == null) return;
    final api = context.read<ShopApi>();
    final locale = Localizations.localeOf(context).languageCode;
    try {
      final rows = await api.suggestReceiveLinesFromBono(
        shopId: widget.shop.id,
        documentId: docId,
        supplierPartyId: supplierId,
        locale: locale,
      );
      if (!mounted || _bonoDocumentId != docId || rows.isEmpty) return;
      _bonoPoll?.cancel();
      _bonoWatcher?.dispose();
      _bonoWatcher = null;
      // The "Reading…" banner morphs into the "N lines · Review" banner.
      setState(() {
        _bonoSuggestions = rows;
        _bonoLoading = false;
        _bonoOcrMissed = false; // a late tick can still land after a timeout
      });
    } catch (_) {
      // Offline or OCR not ready — a later poll/realtime tick retries.
    }
  }

  // Apply the cashier's chosen suggestions: merge each bound line into the
  // receive (manual lines win — never clobber what they typed) and fire the
  // learning loop so the next bono from this supplier resolves the same text.
  Future<void> _reviewBonoSuggestions() async {
    final l = tr(context);
    final supplierId = context.read<ReceiveController>().supplier?.id;
    final photoDocId = _bonoDocumentId;
    final selected = await openBonoReview(
      context,
      suggestions: _bonoSuggestions,
      shop: widget.shop,
      supplierPartyId: supplierId,
      // The photo is the shopkeeper's real verification tool — surface it in
      // the review app bar, sourced from the just-attached bytes we cached.
      onViewPhoto: photoDocId == null ? null : () => _viewBonoPhoto(photoDocId),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    final controller = context.read<ReceiveController>();
    final api = context.read<ShopApi>();
    final docId = _bonoDocumentId;
    var added = 0;
    for (final line in selected) {
      if (controller.lines.containsKey(line.shopItemUnitId)) {
        continue; // manual wins
      }
      controller.addOrReplaceLine(
        shopItemUnitId: line.shopItemUnitId,
        shopItemId: line.shopItemId,
        itemId: line.itemId,
        displayName: line.displayName,
        packagingLabel: line.packagingLabel,
        baseUnitLabel: line.baseUnitLabel,
        quantity: line.quantity,
        lineTotal: line.lineTotal,
      );
      added += 1;
      if (supplierId != null && docId != null) {
        unawaited(
          api
              .confirmBonoSuggestion(
                shopId: widget.shop.id,
                documentId: docId,
                supplierPartyId: supplierId,
                rawText: line.rawText,
                shopItemId: line.shopItemId,
                shopItemUnitId: line.shopItemUnitId,
                confidence: line.learnConfidence,
              )
              .catchError((_) {}),
        );
      }
    }
    if (!mounted) return;
    setState(() => _bonoSuggestionsDismissed = true);
    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.bonoSuggestionsAppliedToast(added))),
      );
    }
  }

  // Show the attached bono photo from the local cache (bytes are written on
  // attach). Falls back to a brief note if they're not available.
  Future<void> _viewBonoPhoto(String docId) async {
    final l = tr(context);
    final cache = context.read<BonoImageCache>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final bytes = await cache.bytesFor(docId);
    if (!mounted) return;
    if (bytes == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.receiveDetailBonoUnavailable)),
      );
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => BonoPhotoView(imageProvider: MemoryImage(bytes)),
      ),
    );
  }

  void _resetBonoState() {
    _bonoPoll?.cancel();
    _bonoPoll = null;
    _bonoWatcher?.dispose();
    _bonoWatcher = null;
    _bonoPollTicks = 0;
    _bonoDocumentId = null;
    _bonoSuggestions = const [];
    _bonoSuggestionsDismissed = false;
    _bonoLoading = false;
    _bonoOcrMissed = false;
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
      // Don't auto-expand over the item results while the cashier is searching.
      _linesExpanded = !_searchFocus.hasFocus;
    });
  }

  /// Focusing the search field collapses the lines drawer AND hides the
  /// line-entry form (via the `!_searchFocus.hasFocus` guard in build) so
  /// the item results — and the keyboard — aren't fighting for space while
  /// the cashier types a new query. Rebuild on every focus change so the
  /// form re-appears once search is dismissed / a tile is tapped.
  void _onSearchFocusChanged() {
    if (!mounted) return;
    setState(() {
      if (_searchFocus.hasFocus) {
        _linesExpanded = false;
        _linesFull = false;
      }
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
    setState(() {
      _linesExpanded = !_linesExpanded;
      if (!_linesExpanded) _linesFull = false; // collapsing exits full
    });
  }

  void _toggleLinesFull() {
    setState(() => _linesFull = !_linesFull);
  }

  Future<void> _save() async {
    // Re-entrancy guard (synchronous, before any await / setState). The SAVE
    // button only disables on the next rebuild after `_saving` flips, so a
    // fast double-tap on a laggy mid-range Android would run _save twice
    // against the still-full lines, minting two client_op_ids and posting the
    // bono TWICE. Bail immediately on re-entry.
    if (_saving) return;
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
    // Client-minted txn UUID shared by the optimistic mirror, the direct post,
    // and the queued post — a stable id so an offline receive can be voided
    // before it syncs. The cash-paid settlement leg stays server-minted.
    final txnId = generateUuidV4();
    // Backdating (#5): captured once so the background post + optimistic write
    // agree. null = today.
    final occurredAt = controller.workingDate;
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
        txnId: txnId,
        occurredAt: occurredAt,
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
          .map(
            (l) => <String, dynamic>{
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
            },
          )
          .toList();
      await localRepoForOptimistic.writeOptimisticTransaction(
        clientOpId: clientOpId,
        txnId: txnId,
        shopId: widget.shop.id,
        typeCode: 'receive',
        occurredAtMs: (occurredAt ?? DateTime.now()).millisecondsSinceEpoch,
        total: total,
        partyId: supplier.id,
        payload: <String, dynamic>{
          'party_name': supplier.name,
          'payment_method_code': null,
          'paid_amount': 0,
          'lines_summary': linesSummary,
          // Carry the bono link so an offline (mirror-loaded) receive detail can
          // find + show the cached photo via View bono.
          'document_id': _bonoDocumentId,
        },
      );
    } catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'dukan receive',
          context: ErrorDescription('write optimistic receive transaction'),
        ),
      );
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
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'dukan receive',
          context: ErrorDescription('optimistic supplier basket bump'),
        ),
      );
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
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'dukan receive',
          context: ErrorDescription('optimistic receive stock/balance'),
        ),
      );
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
    showHappyToast(context, l.receiveSavedToast);

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
        occurredAt: occurredAt,
        txnId: txnId,
      );

      if (mounted) {
        controller.clearAll();
        setState(_resetBonoState);
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
        // Drop the optimistic history row too — a hard reject means the
        // server has no matching receive, so leaving it would show a phantom
        // in Receive History and a retry would stack a second one.
        await localRepoForOptimistic.deleteOptimisticTransaction(txnId: txnId);
      } catch (_) {
        /* best-effort revert; sync reconciles regardless */
      }
      _handleSaveFailure(
        snapshot,
        error,
        stackTrace,
        l.receivePostFailedMessage,
      );
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
          occurredAt: occurredAt,
          txnId: txnId,
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
        setState(_resetBonoState);
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
    required String txnId,
    required DateTime? occurredAt,
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
        occurredAt: occurredAt,
        txnId: txnId,
      );
      if (!mounted) return;
      controller.clearAll();
      setState(() {
        _resetBonoState();
        _linesExpanded = false;
        _saving = false;
      });
      showHappyToast(context, l.receiveSavedToast);
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
    // Full/review drawer: grow the lines strip to fill the screen (grid + line
    // form hidden) so a long bono can be reviewed. Only when open with lines.
    final linesFull = _linesFull && _linesExpanded && controller.isNotEmpty;
    final linesStrip = _ReceiveLinesStrip(
      shop: widget.shop,
      lines: controller.lines,
      lineCount: controller.lineCount,
      bonoTotal: controller.bonoTotal,
      expanded: _linesExpanded,
      full: linesFull,
      saving: _saving,
      onToggleExpand: _onToggleLinesExpand,
      onToggleFull: _toggleLinesFull,
      onRemoveLine: _onRemoveLine,
      onClearAll: _onConfirmClearLines,
      onSave: _save,
    );
    return Scaffold(
      appBar: dukanAppBar(
        context,
        supplier == null ? l.receiveTitle : l.receiveFrom(supplier.name),
        actions: [
          WorkingDateChip(
            workingDate: controller.workingDate,
            onChanged: controller.setWorkingDate,
          ),
          const QueueStatusPill(),
          // Labeled "Bono" chip (not a bare camera icon) so a first-time
          // shopkeeper reads the purpose — "bono" is their own word for the
          // supplier invoice. Fills + checks once a photo is attached.
          Builder(
            builder: (context) {
              final scheme = Theme.of(context).colorScheme;
              final attached = _bonoDocumentId != null;
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: ActionChip(
                  avatar: _attachingBono
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          attached
                              ? Icons.check_circle
                              : Icons.document_scanner_outlined,
                          size: 18,
                          color: attached
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                  label: Text(l.bonoChipLabel),
                  labelStyle: TextStyle(
                    color: attached
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                    fontWeight: attached ? FontWeight.w700 : FontWeight.w400,
                  ),
                  backgroundColor:
                      attached ? scheme.primaryContainer : Colors.transparent,
                  side: attached
                      ? BorderSide.none
                      : BorderSide(color: scheme.outlineVariant),
                  tooltip: attached
                      ? l.bonoAttachedTooltip
                      : l.bonoAttachTooltip,
                  onPressed:
                      _saving || _attachingBono ? null : _onAttachBono,
                ),
              );
            },
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
            // First-use hint: only in the empty start state, and never
            // alongside a real suggestion / attached bono.
            if (_bonoDocumentId == null &&
                _bonoSuggestions.isEmpty &&
                controller.lines.isEmpty &&
                !_bonoHintDismissed)
              BonoHintBanner(
                onTap: _onAttachBono,
                onDismiss: () => setState(() => _bonoHintDismissed = true),
              ),
            // Appears only once real suggestions arrive — never a lingering
            // "loading" state, so it stays absent offline / when OCR fails.
            if (_bonoSuggestions.isNotEmpty && !_bonoSuggestionsDismissed)
              BonoSuggestionBanner(
                loading: false,
                count: _bonoSuggestions.length,
                onReview: _reviewBonoSuggestions,
                onDismiss: () =>
                    setState(() => _bonoSuggestionsDismissed = true),
              )
            // Bridges the silence between attach and the review: a dismissible
            // "Reading the bono…" strip that morphs into the banner above.
            else if (_bonoLoading)
              BonoSuggestionBanner(
                loading: true,
                count: 0,
                onReview: () {},
                onDismiss: () => setState(() => _bonoLoading = false),
              )
            // OCR read nothing → a visible, dismissible "enter by hand" note.
            else if (_bonoOcrMissed)
              BonoSuggestionBanner(
                loading: false,
                missed: true,
                count: 0,
                onReview: () {},
                onDismiss: () => setState(() => _bonoOcrMissed = false),
              ),
            if (!linesFull)
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
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                            child: _AddNewItemBanner(
                              query: _activeQuery,
                              onTap: _saving
                                  ? null
                                  : () => _onAddNewItem(_activeQuery),
                            ),
                          ),
                        Expanded(
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                            // Dragging the grid dismisses the keyboard so it
                            // reclaims the space the numpad ate. Matches Sale.
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            // Responsive density shared with Sale — ~110dp tiles
                            // that grow with the font scale, columns adapting to
                            // width (2 → 3+ on wider phones).
                            gridDelegate: itemGridDelegate(context),
                            itemCount: results.length,
                            itemBuilder: (context, i) {
                              final item = results[i];
                              final selectedShopItemId =
                                  _selectedItem?.shopItemId;
                              final isSelected =
                                  selectedShopItemId != null &&
                                  item.shopItemId == selectedShopItemId;
                              final isActivating =
                                  _activatingItemId != null &&
                                  item.itemId == _activatingItemId;
                              return _ReceiveItemTile(
                                shop: widget.shop,
                                item: item,
                                selected: isSelected,
                                activating: isActivating,
                                onTap: (_saving || _activatingItemId != null)
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
            // Hidden while the search field is focused (keyboard) or in full
            // review mode so the results grid / review list keep the space.
            if (!linesFull && _selectedItem != null && !_searchFocus.hasFocus)
              _LineEntryForm(
                key: ValueKey(_selectedItem!.shopItemId),
                shop: widget.shop,
                selected: _selectedItem!,
                saving: _saving,
                onAddLine: _onAddLine,
                onCancel: () => setState(() => _selectedItem = null),
              ),
            if (linesFull) Expanded(child: linesStrip) else linesStrip,
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
    // Bare packaging noun ("Carton", not "12 Bottle Carton") so the unit
    // line stays short and the cost beside it isn't truncated.
    final conv = item.defaultUnitConversionToBase;
    final packaging =
        (item.defaultUnitLabel != null && conv != null && conv > 1)
            ? packagingCountNoun(
                packagingLabel: item.defaultUnitLabel!,
                conversion: conv,
                baseLabel: item.baseUnitLabel,
              )
            : (item.packagingLabel ??
                item.defaultUnitLabel ??
                item.baseUnitLabel);
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
      // No Card margin — the grid delegate owns the gutter, so the tile's full
      // cell goes to content (lets _kBaseTileExtent stay tight without clipping).
      margin: EdgeInsets.zero,
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
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.85,
                      ),
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
      margin: EdgeInsets.zero,
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

  /// Per-unit cost used to auto-fill the line total as the quantity
  /// changes. Refreshed when the packaging is swapped.
  late num _seedPerUnit;

  /// True once the cashier hand-edits the total field. After that we
  /// stop auto-scaling it from qty so their bono figure is preserved.
  bool _totalEdited = false;

  @override
  void initState() {
    super.initState();
    _shopItemUnitId = widget.selected.shopItemUnitId;
    _packagingLabel = widget.selected.packagingLabel;
    _qtyController = TextEditingController(text: '1');
    // Pre-fill the line total from last cost × qty so a familiar bono
    // line lands in one tap. The cashier always corrects to whatever
    // the paper says.
    _seedPerUnit = widget.selected.perUnitCost ?? 0;
    _totalController = TextEditingController(
      text: _seedPerUnit > 0 ? _formatField(_seedPerUnit * 1) : '',
    );
    _qtyController.addListener(_onChanged);
    _totalController.addListener(_onChanged);
  }

  /// Re-fill the line total from `_seedPerUnit × qty` whenever the qty
  /// changes — but only while the cashier hasn't hand-typed a total.
  /// Set programmatically, so it never trips the total field's
  /// `onChanged` (that's what flips [_totalEdited]).
  void _maybeReseedTotal() {
    if (_totalEdited || _seedPerUnit <= 0) return;
    final qty = _parsedQty;
    final next = (qty != null && qty > 0)
        ? _formatField(_seedPerUnit * qty)
        : '';
    if (_totalController.text != next) {
      _totalController.text = next;
      _totalController.selection = TextSelection.collapsed(offset: next.length);
    }
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
      // A packaging swap resets the money default: adopt the new
      // packaging's last_cost as the seed, clear the stale total, and
      // re-fill it from seed × current qty. Correcting the packaging is
      // a fresh start, so we clear the hand-edited flag too — and if the
      // new packaging has no known cost the total stays blank for the
      // cashier to type.
      _seedPerUnit = picked.lastCost ?? 0;
      _totalEdited = false;
      _totalController.text = '';
      _maybeReseedTotal();
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
                // Name + packaging travel together on the left; the close
                // button stays pinned to the right. The packaging sits
                // right after the name rather than shoved against the ✕.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName(widget.selected.displayName),
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Packaging selector — the "are you entering against
                      // the right packaging?" anchor, inline to save a row.
                      // Bounded + ellipsis so a long label never crowds the
                      // name.
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: InkWell(
                          onTap: widget.saving ? null : _onTapUnit,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    _packagingLabel,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.saving ? null : widget.onCancel,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // The two numbers the cashier fills — qty and total — share
            // one row so the form stays short and the results grid keeps
            // room while the keyboard is up. Per-packaging cost is derived
            // below; quantity chips sit on their own compact row.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  // Wide enough to fit "Tirada" (Somali, longest of the
                  // qty labels we use) without truncation.
                  width: 110,
                  child: TextField(
                    controller: _qtyController,
                    onTapOutside: dismissKeyboardOnTapOutside,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      // Decimal-friendly so loose weighed items (12.5 kg
                      // of meat) can land on a bono.
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (_) => _maybeReseedTotal(),
                    decoration: InputDecoration(
                      labelText: l.receiveLineQuantityLabel,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _totalController,
                    onTapOutside: dismissKeyboardOnTapOutside,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    // First hand-edit locks the total so qty changes stop
                    // auto-scaling it — the cashier's bono figure wins.
                    onChanged: (_) => _totalEdited = true,
                    decoration: InputDecoration(
                      labelText: l.receiveLineTotalLabel(
                        widget.shop.currencySymbol,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            // Quantity chips were dropped from the bono form: on Receive
            // they only ever offered [1,2,5] (the learned "usual" qty is a
            // Sale-only signal) and the cashier types the qty off the paper
            // anyway — not worth a row in this space-tight inline form.
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
            const SizedBox(height: 8),
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
    required this.full,
    required this.saving,
    required this.onToggleExpand,
    required this.onToggleFull,
    required this.onRemoveLine,
    required this.onClearAll,
    required this.onSave,
  });

  final ShopSummary shop;
  final Map<String, ReceiveLine> lines;
  final int lineCount;
  final double bonoTotal;
  final bool expanded;
  final bool full;
  final bool saving;
  final VoidCallback onToggleExpand;
  final VoidCallback onToggleFull;
  final void Function(String key) onRemoveLine;
  final VoidCallback onClearAll;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final canSave = lineCount > 0 && !saving;
    final canExpand = lineCount > 0;
    final maxListHeight = MediaQuery.of(context).size.height * 0.20;
    final entries = lines.entries.toList(growable: false);
    final showExpanded = expanded && canExpand;
    // Full/review mode only applies once open with lines.
    final full = this.full && canExpand;
    // Compact SAVE in the collapsed peek row; full-width when expanded.
    FilledButton saveButton() => FilledButton(
      onPressed: canSave ? onSave : null,
      child: saving
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Text(l.receiveSaveButton),
    );

    // Shared line list — capped at 25% in normal, Expanded in full; overflow
    // cue taps grow to full.
    Widget lineList() => ExpandableLineList(
      fill: full,
      maxHeight: maxListHeight,
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _ReceiveLineTile(
        shop: shop,
        line: entries[i].value,
        enabled: !saving,
        onRemove: () => onRemoveLine(entries[i].key),
      ),
      onExpandRequested: full ? null : onToggleFull,
    );

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
        if (showExpanded)
          TextButton(
            onPressed: saving ? null : onClearAll,
            child: Text(l.receiveLinesClearAllButton),
          ),
        if (showExpanded)
          IconButton(
            tooltip: full ? l.drawerShrinkTooltip : l.drawerExpandTooltip,
            icon: Icon(
              full ? Icons.unfold_less : Icons.unfold_more,
              size: 28,
              color: Theme.of(context).colorScheme.onSurface,
            ),
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
        child: full
            ? Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  summaryRow,
                  lineList(),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: saveButton()),
                ],
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
                              lineList(),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: saveButton(),
                              ),
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
      // ≥48dp hit target so removing a bono line — destructive, right by
      // the tap-to-edit body — isn't a fat-finger gamble one-handed.
      trailing: IconButton(
        tooltip: l.receiveLineRemoveTooltip(line.displayName),
        icon: const Icon(Icons.close, size: 20),
        onPressed: enabled ? onRemove : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
  const _ReceiveUnknownScanPill({required this.code, required this.onDismiss});

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
