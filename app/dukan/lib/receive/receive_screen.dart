// The bono-entry workhorse: pick an item, set qty + cost, ADD LINE,
// repeat. The supplier is already in ReceiveController from the picker
// (we pushReplacement here once a supplier is chosen).
//
// Layout, top to bottom:
//   * AppBar — "Receive from {supplier}" + a "change supplier" icon
//   * Search field
//   * Favorites grid — search_items(screen='receive', p_party_id) so
//     items this supplier has provided in past bonos rank to the top
//     and the inline form can pre-fill cost from each tile's last_cost
//   * Selected-item form — qty stepper + cost field + ADD LINE
//   * Lines strip — expandable summary, just like the Sale cart but
//     with cost/subtotal instead of price/subtotal
//   * Paid now / credit + SAVE
//
// Tap routing on a tile is simpler than Sale: there's no "fast-add"
// path. Every tile tap loads the inline form so the cashier reviews
// qty + cost before committing. Bonos vary line-by-line in a way sales
// don't (mixed units, partial cases, variable per-unit cost).

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
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final _searchController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _costController = TextEditingController();
  final _paidController = TextEditingController(text: '0');
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
    // Resume case: auto-expand the lines strip so the cashier sees the
    // existing bono at a glance.
    _linesExpanded = context.read<ReceiveController>().isNotEmpty;
    _paidController.text = _formatNumForField(
      context.read<ReceiveController>().paidAmount,
    );
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
    _qtyController.dispose();
    _costController.dispose();
    _paidController.dispose();
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
    // Pre-fill qty=1 and cost from the supplier-specific last cost if we
    // have one. Otherwise leave cost blank so the cashier types it.
    setState(() {
      _selectedItem = item;
      _qtyController.text = '1';
      _costController.text = item.lastCost == null
          ? ''
          : _formatNumForField(item.lastCost!);
    });
  }

  void _onChangeSupplier() {
    final api = context.read<ShopApi>();
    final receive = context.read<ReceiveController>();
    // Same provider re-export pattern: providers live in AuthBootstrap
    // (a child of MaterialApp), so routes pushed through the root
    // Navigator have to carry them across.
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

  Future<void> _onAddLine() async {
    final l = tr(context);
    final item = _selectedItem;
    if (item == null) return;
    final qty = int.tryParse(_qtyController.text.trim());
    final cost = num.tryParse(_costController.text.trim());
    if (qty == null || qty < 1) {
      showError(context, l.chooseItemWarning);
      return;
    }
    if (cost == null || cost < 0) {
      showError(context, l.chooseItemWarning);
      return;
    }
    context.read<ReceiveController>().addOrReplaceLine(
      item,
      quantity: qty,
      unitCost: cost,
    );
    setState(() {
      _selectedItem = null;
      _qtyController.text = '1';
      _costController.clear();
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
      _paidController.text = '0';
      setState(() => _linesExpanded = false);
    }
  }

  void _onToggleLinesExpand() {
    final controller = context.read<ReceiveController>();
    if (controller.isEmpty) return;
    setState(() => _linesExpanded = !_linesExpanded);
  }

  void _onPaidChanged(String value) {
    final parsed = num.tryParse(value.trim()) ?? 0;
    context.read<ReceiveController>().setPaidAmount(parsed);
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
    if (controller.paidAmount > controller.bonoTotal) {
      showError(context, l.receivePaidExceedsTotalMessage);
      return;
    }

    setState(() => _saving = true);
    final api = context.read<ShopApi>();
    final snapshot = controller.snapshot();
    final paid = snapshot.paidAmount;

    // Optimistic clear so the screen returns to fresh state immediately.
    // Lines + paid wipe; supplier stays so the cashier could resume a
    // second bono from the same supplier without re-picking.
    controller.clearLines();
    _paidController.text = '0';
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
        final unitId = units[line.baseUnitCode];
        if (unitId == null) {
          throw StateError('Unknown unit ${line.baseUnitCode}');
        }
        lines.add(
          ReceiveLinePayload(
            itemId: itemId,
            quantity: line.quantity,
            unitId: unitId,
            unitCost: line.unitCost,
          ),
        );
      }

      await api.postReceive(
        shopId: widget.shop.id,
        partyId: supplier.id,
        lines: lines,
        paidAmount: paid,
        paymentMethodCode: paid > 0 ? 'cash' : null,
        clientOpId: _generateClientOpId(),
      );

      // Successful post — fully clear the controller (supplier too) so
      // the next Receive launch starts from a clean Home → picker flow.
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
    _paidController.text = _formatNumForField(snapshot.paidAmount);
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
                item: _selectedItem!,
                qtyController: _qtyController,
                costController: _costController,
                saving: _saving,
                onAddLine: _onAddLine,
                onCancel: () => setState(() => _selectedItem = null),
              ),
            _ReceiveLinesStrip(
              lines: controller.lines,
              lineCount: controller.lineCount,
              bonoTotal: controller.bonoTotal,
              credit: controller.credit,
              expanded: _linesExpanded,
              saving: _saving,
              paidController: _paidController,
              onToggleExpand: _onToggleLinesExpand,
              onRemoveLine: _onRemoveLine,
              onClearAll: _onConfirmClearLines,
              onPaidChanged: _onPaidChanged,
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
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ItemSearchResult item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final costText = item.lastCost == null
        ? tr(context).lineEditorTilePriceMissing
        : _formatMoney(item.lastCost!);
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
                '${item.baseUnitLabel} · $costText',
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

class _LineEntryForm extends StatelessWidget {
  const _LineEntryForm({
    required this.item,
    required this.qtyController,
    required this.costController,
    required this.saving,
    required this.onAddLine,
    required this.onCancel,
  });

  final ItemSearchResult item;
  final TextEditingController qtyController;
  final TextEditingController costController;
  final bool saving;
  final VoidCallback onAddLine;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: saving ? null : onCancel,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      labelText: l.receiveLineQuantityLabel,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: costController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: l.receiveLineCostLabel(item.baseUnitLabel),
                      prefixText: '\$ ',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: saving ? null : onAddLine,
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
    required this.lines,
    required this.lineCount,
    required this.bonoTotal,
    required this.credit,
    required this.expanded,
    required this.saving,
    required this.paidController,
    required this.onToggleExpand,
    required this.onRemoveLine,
    required this.onClearAll,
    required this.onPaidChanged,
    required this.onSave,
  });

  final Map<String, ReceiveLine> lines;
  final int lineCount;
  final double bonoTotal;
  final double credit;
  final bool expanded;
  final bool saving;
  final TextEditingController paidController;
  final VoidCallback onToggleExpand;
  final void Function(String key) onRemoveLine;
  final VoidCallback onClearAll;
  final ValueChanged<String> onPaidChanged;
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
                                _formatMoney(bonoTotal),
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
                        entries: entries,
                        saving: saving,
                        onRemoveLine: onRemoveLine,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: paidController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: onPaidChanged,
                    decoration: InputDecoration(
                      labelText: l.receivePaidNowLabel,
                      prefixText: '\$ ',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${l.receiveCreditLabel}: ${_formatMoney(credit)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
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
    required this.entries,
    required this.saving,
    required this.onRemoveLine,
  });

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
    required this.line,
    required this.enabled,
    required this.onRemove,
  });

  final ReceiveLine line;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final subtitle = l.receiveLineSubtotal(
      '${line.quantity}',
      _formatMoney(line.unitCost),
      _formatMoney(line.subtotal),
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

String _formatMoney(num value) {
  final v = value.toDouble();
  if (v == v.roundToDouble()) {
    return '\$${v.toStringAsFixed(0)}';
  }
  return '\$${v.toStringAsFixed(2)}';
}

String _formatNumForField(num value) {
  final v = value.toDouble();
  if (v == v.roundToDouble()) {
    return v.toInt().toString();
  }
  return v.toString();
}
