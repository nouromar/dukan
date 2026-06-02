// The bono-entry workhorse: pick an item, set qty + total, ADD LINE,
// repeat. The supplier is already in ReceiveController from the picker.
//
// Layout, top to bottom:
//   * AppBar — "Receive from {supplier}" + a "change supplier" icon
//   * Search field
//   * Favorites grid — search_items(screen='receive', p_party_id) so
//     items this supplier has provided in past bonos rank to the top
//     and the inline form can pre-fill cost from each tile's last_cost
//   * Selected-item form — two-way bound (Per <unit>, Total) money
//     fields. Cashier types whichever matches the bono; the other
//     auto-fills. Qty changes recompute whichever field was NOT the
//     last one typed.
//   * Lines strip — expandable summary, like the Sale cart
//   * SAVE — always creates a fully-credit receive (cash payment is a
//     separate Payment-screen step; see decisions.md TODO)
//
// Tap routing on a tile loads the inline form. Unlike Sale, there is no
// fast-add path — bonos vary line-by-line in a way sales don't.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/receive/supplier_picker_screen.dart';
import 'package:dukan/receive/unit_picker_sheet.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final _searchController = TextEditingController();
  late Future<List<ItemSearchResult>> _resultsFuture;
  String _activeQuery = '';
  Timer? _debounce;
  bool _saving = false;
  bool _linesExpanded = false;
  ItemSearchResult? _selectedItem;
  final _random = math.Random();
  String? _locale;

  @override
  void initState() {
    super.initState();
    _linesExpanded = context.read<ReceiveController>().isNotEmpty;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = Localizations.localeOf(context).languageCode;
    if (_locale != current) {
      _locale = current;
      _resultsFuture = _fetch(_activeQuery);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<ItemSearchResult>> _fetch(String query) {
    final supplier = context.read<ReceiveController>().supplier;
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
        _resultsFuture = _fetch(_activeQuery);
      });
    });
  }

  void _onTapTile(ItemSearchResult item) {
    setState(() => _selectedItem = item);
  }

  void _onChangeSupplier() {
    final api = context.read<ShopApi>();
    final receive = context.read<ReceiveController>();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MultiProvider(
          providers: [
            Provider<ShopApi>.value(value: api),
            ChangeNotifierProvider<ReceiveController>.value(value: receive),
          ],
          child: SupplierPickerScreen(shop: widget.shop),
        ),
      ),
    );
  }

  void _onAddLine(
    int quantity,
    num lineTotal,
    String unitCode,
    String unitLabel,
  ) {
    final item = _selectedItem;
    if (item == null) return;
    context.read<ReceiveController>().addOrReplaceLine(
      item,
      quantity: quantity,
      lineTotal: lineTotal,
      unitCode: unitCode,
      unitLabel: unitLabel,
    );
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

    setState(() => _saving = true);
    final api = context.read<ShopApi>();
    final snapshot = controller.snapshot();

    // Optimistic clear so the screen returns to fresh state immediately.
    // Lines wipe; supplier stays so the cashier could resume a second
    // bono from the same supplier without re-picking.
    controller.clearLines();
    setState(() => _linesExpanded = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.receiveSavedToast)),
    );

    try {
      final units = {for (final u in await api.listUnits()) u.code: u.id};
      final lines = <ReceiveLinePayload>[];
      for (final line in snapshot.lines.values) {
        var itemId = line.itemId;
        itemId ??= await api.ensureShopItem(
          shopId: widget.shop.id,
          catalogItemId: line.catalogItemId!,
        );
        // Crucially we pass the RECEIVE unit's id, not the base unit's.
        // A 5-bag rice line otherwise gets recorded as 5 kg of stock.
        final unitId = units[line.receiveUnitCode];
        if (unitId == null) {
          throw StateError('Unknown unit ${line.receiveUnitCode}');
        }
        lines.add(
          ReceiveLinePayload(
            itemId: itemId,
            quantity: line.quantity,
            unitId: unitId,
            lineTotal: line.lineTotal,
          ),
        );
      }

      await api.postReceive(
        shopId: widget.shop.id,
        partyId: supplier.id,
        lines: lines,
        // Always fully credit; cash payment is a separate Payment step.
        paidAmount: 0,
        paymentMethodCode: null,
        clientOpId: _generateClientOpId(),
      );

      if (mounted) {
        controller.clearAll();
        Navigator.of(context).maybePop();
      }
    } on PostgrestException catch (error, stackTrace) {
      _handleSaveFailure(snapshot, error, stackTrace, l.receivePostFailedMessage);
    } catch (error, stackTrace) {
      _handleSaveFailure(snapshot, error, stackTrace, l.receivePostFailedMessage);
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
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan receive',
        context: ErrorDescription('post_receive'),
      ),
    );
    if (!mounted) return;
    context.read<ReceiveController>().restore(snapshot);
    showError(context, message);
  }

  String _generateClientOpId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = _random.nextInt(1 << 32);
    return 'receive-$ts-$r';
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
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l.receiveSearchHint,
                ),
              ),
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
                  if (results.isEmpty) {
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
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      mainAxisExtent: 110,
                    ),
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final item = results[i];
                      final isSelected =
                          _selectedItem != null &&
                              (item.itemId ?? item.catalogItemId) ==
                                  (_selectedItem!.itemId ??
                                      _selectedItem!.catalogItemId);
                      return _ReceiveItemTile(
                        shop: widget.shop,
                        item: item,
                        selected: isSelected,
                        onTap: _saving ? null : () => _onTapTile(item),
                      );
                    },
                  );
                },
              ),
            ),
            if (_selectedItem != null)
              _LineEntryForm(
                key: ValueKey(
                  _selectedItem!.itemId ?? _selectedItem!.catalogItemId,
                ),
                shop: widget.shop,
                item: _selectedItem!,
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

class _ReceiveItemTile extends StatelessWidget {
  const _ReceiveItemTile({
    required this.shop,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ShopSummary shop;
  final ItemSearchResult item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final costText = item.lastCost == null
        ? tr(context).lineEditorTilePriceMissing
        : formatMoney(item.lastCost!, shop);
    return Card(
      color: selected ? theme.colorScheme.primaryContainer : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${item.receiveUnitLabel} · $costText',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Two-way bound per-unit + total form. Cashier types into whichever
// field matches their bono; the other recomputes. On qty change, the
// last-typed money field stays authoritative and the other recomputes.
// The unit label is tappable: opens a bottom sheet listing every
// allow_receive unit so the cashier can swap from the default (e.g.,
// bag) to base (kg) or another unit for partial bonos.
class _LineEntryForm extends StatefulWidget {
  const _LineEntryForm({
    required this.shop,
    required this.item,
    required this.saving,
    required this.onAddLine,
    required this.onCancel,
    super.key,
  });

  final ShopSummary shop;
  final ItemSearchResult item;
  final bool saving;
  final void Function(
    int quantity,
    num lineTotal,
    String unitCode,
    String unitLabel,
  )
  onAddLine;
  final VoidCallback onCancel;

  @override
  State<_LineEntryForm> createState() => _LineEntryFormState();
}

enum _LastTypedMoney { perUnit, total }

class _LineEntryFormState extends State<_LineEntryForm> {
  late final TextEditingController _qtyController;
  late final TextEditingController _perUnitController;
  late final TextEditingController _totalController;
  _LastTypedMoney _lastTyped = _LastTypedMoney.perUnit;
  // Currently selected receive unit. Starts as the item's default; the
  // unit picker can swap it. Affects what's sent to post_receive and
  // what shows in the cart line.
  late String _unitCode;
  late String _unitLabel;
  // Guard so programmatic controller updates don't trigger our listeners
  // and cause feedback loops.
  bool _suppressNotify = false;

  @override
  void initState() {
    super.initState();
    final perUnit = widget.item.lastCost ?? 0;
    _unitCode = widget.item.receiveUnitCode;
    _unitLabel = widget.item.receiveUnitLabel;
    _qtyController = TextEditingController(text: '1');
    _perUnitController = TextEditingController(
      text: perUnit > 0 ? _formatField(perUnit) : '',
    );
    _totalController = TextEditingController(
      text: perUnit > 0 ? _formatField(perUnit) : '',
    );
    _qtyController.addListener(_onQtyChanged);
    _perUnitController.addListener(_onPerUnitChanged);
    _totalController.addListener(_onTotalChanged);
  }

  Future<void> _onTapUnit() async {
    final picked = await showUnitPicker(
      context,
      shopId: widget.shop.id,
      baseUnitLabel: widget.item.baseUnitLabel,
      itemId: widget.item.itemId,
      catalogItemId: widget.item.itemId == null
          ? widget.item.catalogItemId
          : null,
    );
    if (picked == null || !mounted) return;
    if (picked.unitCode == _unitCode) return;
    setState(() {
      _unitCode = picked.unitCode;
      _unitLabel = picked.unitLabel;
      // Clear cost fields — last_cost was scoped to the previous unit.
      // The cashier types fresh values for the new unit.
      _setProgrammatic(_perUnitController, '');
      _setProgrammatic(_totalController, '');
      _lastTyped = _LastTypedMoney.perUnit;
    });
  }

  @override
  void dispose() {
    _qtyController.removeListener(_onQtyChanged);
    _perUnitController.removeListener(_onPerUnitChanged);
    _totalController.removeListener(_onTotalChanged);
    _qtyController.dispose();
    _perUnitController.dispose();
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

  void _setProgrammatic(TextEditingController c, String text) {
    if (c.text == text) return;
    _suppressNotify = true;
    c.text = text;
    _suppressNotify = false;
  }

  void _onQtyChanged() {
    if (_suppressNotify) return;
    final qty = int.tryParse(_qtyController.text.trim());
    if (qty == null || qty < 1) {
      setState(() {});
      return;
    }
    // Last-typed field stays authoritative; recompute the other.
    if (_lastTyped == _LastTypedMoney.perUnit) {
      final perUnit = _parse(_perUnitController.text);
      if (perUnit != null) {
        _setProgrammatic(_totalController, _formatField(perUnit * qty));
      }
    } else {
      final total = _parse(_totalController.text);
      if (total != null && qty > 0) {
        _setProgrammatic(_perUnitController, _formatField(total / qty));
      }
    }
    setState(() {});
  }

  void _onPerUnitChanged() {
    if (_suppressNotify) return;
    _lastTyped = _LastTypedMoney.perUnit;
    final qty = int.tryParse(_qtyController.text.trim());
    final perUnit = _parse(_perUnitController.text);
    if (qty != null && qty > 0 && perUnit != null) {
      _setProgrammatic(_totalController, _formatField(perUnit * qty));
    } else if (perUnit == null) {
      _setProgrammatic(_totalController, '');
    }
    setState(() {});
  }

  void _onTotalChanged() {
    if (_suppressNotify) return;
    _lastTyped = _LastTypedMoney.total;
    final qty = int.tryParse(_qtyController.text.trim());
    final total = _parse(_totalController.text);
    if (qty != null && qty > 0 && total != null) {
      _setProgrammatic(_perUnitController, _formatField(total / qty));
    } else if (total == null) {
      _setProgrammatic(_perUnitController, '');
    }
    setState(() {});
  }

  bool get _canAdd {
    final qty = int.tryParse(_qtyController.text.trim());
    final total = _parse(_totalController.text);
    return qty != null && qty >= 1 && total != null && total > 0;
  }

  void _onAdd() {
    final qty = int.tryParse(_qtyController.text.trim())!;
    final total = _parse(_totalController.text)!;
    widget.onAddLine(qty, total, _unitCode, _unitLabel);
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
                    widget.item.name,
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
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l.receiveLineQuantityLabel,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
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
                        Text(_unitLabel, style: theme.textTheme.bodyLarge),
                        const SizedBox(width: 2),
                        const Icon(Icons.arrow_drop_down, size: 22),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Money field labels carry the "$" hint so it's obvious
                // these are currency fields even before the cashier
                // taps in. No additional prefixText — would be a second
                // $ on screen once the field is focused.
                Expanded(
                  child: TextField(
                    controller: _perUnitController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: l.receiveLinePerUnitLabel(
                        widget.shop.currencySymbol,
                        _unitLabel,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _totalController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
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
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final unit = _displayUnit(
      line.receiveUnitCode,
      line.receiveUnitLabel,
      line.quantity,
      isEnglish,
    );
    // l.receiveLineSubtotal signature is (quantity, total, unit) — the
    // localization gen sorts placeholders alphabetically so the order
    // here does NOT match the template's left-to-right reading.
    final subtitle = l.receiveLineSubtotal(
      '${line.quantity}',
      formatMoney(line.lineTotal, shop),
      unit,
    );
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(
        line.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle),
      trailing: IconButton(
        tooltip: l.receiveLineRemoveTooltip(line.name),
        icon: const Icon(Icons.close, size: 20),
        onPressed: enabled ? onRemove : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }
}


// English plural forms for the unit codes we use. Hardcoded because a
// blanket "+s" rule breaks "box" (→ "boxes" not "boxs") and isn't
// grammatical for "kg". Somali plural rules are different (often
// context-dependent); we use the label as-is for non-English locales.
const _enUnitPlurals = <String, String>{
  'piece': 'pieces',
  'kg': 'kg',
  'gram': 'grams',
  'litre': 'litres',
  'ml': 'ml',
  'bag': 'bags',
  'bottle': 'bottles',
  'packet': 'packets',
  'box': 'boxes',
  'carton': 'cartons',
};

String _displayUnit(String code, String label, int quantity, bool isEnglish) {
  final lower = label.toLowerCase();
  if (!isEnglish || quantity == 1) return lower;
  return _enUnitPlurals[code] ?? '${lower}s';
}
