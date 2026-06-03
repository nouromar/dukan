import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/sale/cart_controller.dart';
import 'package:dukan/sale/line_editor_sheet.dart';
import 'package:dukan/sale/sale_history_screen.dart';
import 'package:dukan/shared/party_picker_sheet.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';

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
  bool _cartExpanded = false;
  final _random = math.Random();
  String? _locale;

  @override
  void initState() {
    super.initState();
    // Auto-expand the drawer when reopening the Sale screen with a
    // non-empty cart: the cashier needs to see at a glance whether the
    // existing items are theirs to continue or a stale cart to clear.
    _cartExpanded = context.read<CartController>().isNotEmpty;
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
        _resultsFuture = _fetch(_activeQuery);
      });
    });
  }

  // Tap routes:
  //   * priced item → fast-path add (the v1 speed contract).
  //   * no-price item (salePrice null OR 0) → editor in price-required
  //     mode. Treating 0 the same as null is intentional; see the design
  //     discussion in the slice. The cashier can still confirm a free sale
  //     by typing 0 explicitly inside the editor.
  void _onTapTile(ItemSearchResult item) {
    if (_isNoPrice(item)) {
      _openEditorForTile(item, priceRequired: true);
    } else {
      context.read<CartController>().addItem(item);
    }
  }

  void _onLongPressTile(ItemSearchResult item) {
    _openEditorForTile(item, priceRequired: _isNoPrice(item));
  }

  Future<void> _openEditorForTile(
    ItemSearchResult item, {
    required bool priceRequired,
  }) async {
    // If the cashier already has a line for this item, seed the editor
    // with the line's current qty/price so the long-press behaves as
    // "edit" rather than "replace with 1".
    final key = item.itemId ?? item.catalogItemId;
    final existing = key == null
        ? null
        : context.read<CartController>().lines[key];
    final result = await showLineEditor(
      context,
      itemName: item.name,
      baseUnitLabel: item.baseUnitLabel,
      currencySymbol: widget.shop.currencySymbol,
      initialQuantity: existing?.quantity ?? 1,
      initialUnitPrice: priceRequired
          ? existing?.unitPrice
          : (existing?.unitPrice ?? item.salePrice),
      priceRequired: priceRequired,
    );
    if (result == null || !mounted) return;
    context.read<CartController>().addOrReplaceFromEditor(
      item,
      quantity: result.quantity,
      unitPrice: result.unitPrice,
    );
    setState(() => _cartExpanded = true);
  }

  Future<void> _onLongPressCartLine(_CartLineEntry entry) async {
    final line = entry.line;
    final result = await showLineEditor(
      context,
      itemName: line.name,
      baseUnitLabel: line.baseUnitLabel,
      currencySymbol: widget.shop.currencySymbol,
      initialQuantity: line.quantity,
      initialUnitPrice: line.unitPrice,
    );
    if (result == null || !mounted) return;
    context.read<CartController>().updateLineFromEditor(
      entry.key,
      quantity: result.quantity,
      unitPrice: result.unitPrice,
    );
  }

  bool _isNoPrice(ItemSearchResult item) {
    final p = item.salePrice;
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

    setState(() => _saving = true);
    final api = context.read<ShopApi>();
    final snapshot = cart.snapshot();
    final cashSale = !snapshot.debt;
    final partyId = snapshot.debt ? snapshot.customer!.id : null;
    final total = snapshot.lines.values
        .fold<double>(0, (sum, line) => sum + line.subtotal.toDouble());

    // Optimistic clear: UI returns to fresh state immediately.
    cart.clearAll();
    setState(() => _cartExpanded = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.saleSavedToast)),
    );

    try {
      final units = {for (final u in await api.listUnits()) u.code: u.id};
      final lines = <SaleLine>[];
      // Pairs of (resolved itemId, entered price) for the lines whose
      // unit price came from the editor — we'll seed item.sale_price
      // after post_sale succeeds so future taps fast-add at this price.
      final priceWriteBacks = <({String itemId, num salePrice})>[];
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
          SaleLine(
            itemId: itemId,
            quantity: line.quantity,
            unitId: unitId,
            unitPrice: line.unitPrice,
          ),
        );
        if (line.priceWasEntered) {
          priceWriteBacks.add((itemId: itemId, salePrice: line.unitPrice));
        }
      }

      await api.postSale(
        shopId: widget.shop.id,
        lines: lines,
        paidAmount: cashSale ? total : 0,
        partyId: partyId,
        paymentMethodCode: cashSale ? 'cash' : null,
        clientOpId: _generateClientOpId(),
      );

      // Persist editor-entered prices. Failures here are non-fatal —
      // the sale is already posted, the cashier just gets re-prompted
      // for that item on the next sale. Reported to the error log so
      // we'd notice a systematic failure.
      for (final write in priceWriteBacks) {
        try {
          await api.setItemSalePrice(
            shopId: widget.shop.id,
            itemId: write.itemId,
            salePrice: write.salePrice,
          );
        } catch (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'dukan sale',
              context: ErrorDescription('set_item_sale_price'),
            ),
          );
        }
      }
    } on PostgrestException catch (error, stackTrace) {
      _handleSaveFailure(snapshot, error, stackTrace, l.salePostFailedMessage);
    } catch (error, stackTrace) {
      _handleSaveFailure(snapshot, error, stackTrace, l.salePostFailedMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _handleSaveFailure(
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
    context.read<CartController>().restore(snapshot);
    showError(context, message);
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
    return Scaffold(
      appBar: dukanAppBar(
        context,
        l.saleTitle,
        actions: [
          IconButton(
            tooltip: l.saleHistoryTooltip,
            icon: const Icon(Icons.history),
            onPressed: _saving
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
                  hintText: l.saleSearchHint,
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
                          l.saleLoadFailedMessage,
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
                              ? l.saleEmptyFavoritesMessage
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
                      return _SaleItemTile(
                        shop: widget.shop,
                        item: item,
                        onTap: _saving ? null : () => _onTapTile(item),
                        onLongPress:
                            _saving ? null : () => _onLongPressTile(item),
                      );
                    },
                  );
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
      ),
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
    final noPrice = item.salePrice == null || item.salePrice == 0;
    final priceText = noPrice
        ? tr(context).lineEditorTilePriceMissing
        : formatMoney(item.salePrice!, shop);
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
                '${item.baseUnitLabel} · $priceText',
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
    final subtitle = l.cartLineSubtotal(
      '${line.quantity}',
      formatMoney(line.unitPrice, shop),
      formatMoney(line.subtotal, shop),
    );
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      visualDensity: VisualDensity.compact,
      onLongPress: enabled ? onLongPress : null,
      title: Text(
        line.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle),
      trailing: IconButton(
        tooltip: l.cartRemoveLineTooltip(line.name),
        icon: const Icon(Icons.close, size: 20),
        onPressed: enabled ? onRemove : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }
}

