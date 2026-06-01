import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/sale/customer_picker_sheet.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

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

  // Cart keyed by either item_id (activated) or catalog_item_id (will
  // activate on save). Either may be null on the search result; we
  // require at least one to be non-null before adding.
  final Map<String, _CartLine> _cart = {};
  bool _debt = false;
  PartySearchResult? _customer;
  bool _saving = false;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _resultsFuture = _fetch('');
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

  double get _total =>
      _cart.values.fold(0, (sum, line) => sum + line.subtotal);
  int get _itemCount =>
      _cart.values.fold(0, (sum, line) => sum + line.quantity);

  void _addItem(ItemSearchResult item) {
    final key = item.itemId ?? item.catalogItemId;
    if (key == null) return;
    setState(() {
      final existing = _cart[key];
      if (existing != null) {
        existing.quantity += 1;
      } else {
        _cart[key] = _CartLine(
          itemId: item.itemId,
          catalogItemId: item.catalogItemId,
          name: item.name,
          baseUnitCode: item.baseUnitCode,
          baseUnitLabel: item.baseUnitLabel,
          unitPrice: item.salePrice ?? 0,
        );
      }
    });
  }

  void _toggleDebt(bool debt) {
    setState(() => _debt = debt);
    if (debt && _customer == null) {
      _pickCustomer();
    }
  }

  Future<void> _pickCustomer() async {
    final picked = await showCustomerPicker(context, shopId: widget.shop.id);
    if (picked != null && mounted) {
      setState(() => _customer = picked);
    }
  }

  Future<void> _save() async {
    final l = tr(context);
    if (_cart.isEmpty) {
      showError(context, l.saleNeedItemsMessage);
      return;
    }
    if (_debt && _customer == null) {
      showError(context, l.saleNeedCustomerMessage);
      _pickCustomer();
      return;
    }

    setState(() => _saving = true);
    final api = context.read<ShopApi>();
    final snapshot = _cart.values
        .map(
          (line) => _CartLine(
            itemId: line.itemId,
            catalogItemId: line.catalogItemId,
            name: line.name,
            baseUnitCode: line.baseUnitCode,
            baseUnitLabel: line.baseUnitLabel,
            unitPrice: line.unitPrice,
            quantity: line.quantity,
          ),
        )
        .toList(growable: false);
    final cashSale = !_debt;
    final partyId = _debt ? _customer!.id : null;
    final total = _total;

    // Optimistic clear: UI returns to fresh state immediately.
    setState(() {
      _cart.clear();
      _debt = false;
      _customer = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.saleSavedToast)),
    );

    try {
      // Resolve unit IDs (mostly base units since we don't yet support
      // per-line unit override) and lazy-activate any catalog candidates.
      final units = {for (final u in await api.listUnits()) u.code: u.id};
      final lines = <SaleLine>[];
      for (final line in snapshot) {
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
      }

      await api.postSale(
        shopId: widget.shop.id,
        lines: lines,
        paidAmount: cashSale ? total : 0,
        partyId: partyId,
        paymentMethodCode: cashSale ? 'cash' : null,
        clientOpId: _generateClientOpId(),
      );
    } on PostgrestException catch (error, stackTrace) {
      _handleSaveFailure(snapshot, error, stackTrace, l.salePostFailedMessage);
    } catch (error, stackTrace) {
      _handleSaveFailure(snapshot, error, stackTrace, l.salePostFailedMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _handleSaveFailure(
    List<_CartLine> snapshot,
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
    setState(() {
      _cart
        ..clear()
        ..addAll({
          for (final line in snapshot)
            (line.itemId ?? line.catalogItemId!): line,
        });
    });
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
    return Scaffold(
      appBar: dukanAppBar(context, l.saleTitle),
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
                        item: item,
                        onTap: _saving ? null : () => _addItem(item),
                      );
                    },
                  );
                },
              ),
            ),
            _SaleCartStrip(
              itemCount: _itemCount,
              total: _total,
              debt: _debt,
              customer: _customer,
              saving: _saving,
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

class _CartLine {
  _CartLine({
    required this.itemId,
    required this.catalogItemId,
    required this.name,
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required this.unitPrice,
    this.quantity = 1,
  });

  final String? itemId;
  final String? catalogItemId;
  final String name;
  final String baseUnitCode;
  final String baseUnitLabel;
  final num unitPrice;
  int quantity;

  num get subtotal => unitPrice * quantity;
}

class _SaleItemTile extends StatelessWidget {
  const _SaleItemTile({required this.item, required this.onTap});

  final ItemSearchResult item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: Colors.white,
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
                item.salePrice == null
                    ? item.baseUnitLabel
                    : '${item.baseUnitLabel} · ${_formatMoney(item.salePrice!)}',
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

class _SaleCartStrip extends StatelessWidget {
  const _SaleCartStrip({
    required this.itemCount,
    required this.total,
    required this.debt,
    required this.customer,
    required this.saving,
    required this.onModeChanged,
    required this.onPickCustomer,
    required this.onSave,
  });

  final int itemCount;
  final double total;
  final bool debt;
  final PartySearchResult? customer;
  final bool saving;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onPickCustomer;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final canSave = itemCount > 0 && (!debt || customer != null) && !saving;
    return Material(
      elevation: 10,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.saleCartSummary(itemCount, _formatMoney(total)),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
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
                const SizedBox(width: 10),
                Expanded(
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
                            _formatMoney(customer!.receivable),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: saving ? null : onPickCustomer,
                      ),
              ),
            ],
          ],
        ),
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
