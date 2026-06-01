// Prototype Sale screen (mock data only). Replaced in slice 2 of the
// mobile UI rebuild; see docs/ux-screens.md §5.2 for the design target.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dukan/mock/mock_data.dart';
import 'package:dukan/prototype/_widgets.dart';
import 'package:dukan/prototype/inline_party_search.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/formatting.dart';
import 'package:dukan/shared/l10n.dart';

class CartEntry {
  CartEntry({required this.item, required this.quantity, required this.price});
  final MockItem item;
  double quantity;
  double price;
  double get total => quantity * price;
}

class SaleScreen extends StatefulWidget {
  const SaleScreen({super.key});

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  final searchController = TextEditingController();
  final customerController = TextEditingController();
  final Map<String, CartEntry> cart = {};
  bool debt = false;

  @override
  void dispose() {
    searchController.dispose();
    customerController.dispose();
    super.dispose();
  }

  double get total => cart.values.fold(0, (sum, entry) => sum + entry.total);
  double get count => cart.values.fold(0, (sum, entry) => sum + entry.quantity);

  void addItem(MockItem item, {double quantity = 1, double? price}) {
    setState(() {
      final entry = cart[item.id];
      if (entry == null) {
        cart[item.id] = CartEntry(
          item: item,
          quantity: quantity,
          price: price ?? item.price,
        );
      } else {
        entry.quantity += quantity;
        if (price != null) entry.price = price;
      }
    });
    HapticFeedback.selectionClick();
  }

  Future<void> openQuantityDialog(MockItem item) async {
    final l = tr(context);
    final result = await showDialog<_QtyPrice>(
      context: context,
      builder: (context) => QtyPriceDialog(
        item: item,
        title: item.name(Localizations.localeOf(context)),
      ),
    );
    if (result != null && result.quantity > 0) {
      addItem(item, quantity: result.quantity, price: result.price);
    }
    if (mounted && result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${item.name(Localizations.localeOf(context))}: ${l.addToCart}',
          ),
        ),
      );
    }
  }

  void confirmSale() {
    if (cart.isEmpty) return;
    final oldCart = Map<String, CartEntry>.fromEntries(
      cart.entries.map(
        (e) => MapEntry(
          e.key,
          CartEntry(
            item: e.value.item,
            quantity: e.value.quantity,
            price: e.value.price,
          ),
        ),
      ),
    );
    setState(() => cart.clear());
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(tr(context).savedUndo),
        action: SnackBarAction(
          label: tr(context).undo,
          onPressed: () => setState(() => cart.addAll(oldCart)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final locale = Localizations.localeOf(context);
    final items = [
      ...mockItems.where((item) => item.matches(searchController.text)),
    ]..sort((a, b) => b.frequency.compareTo(a.frequency));
    return Scaffold(
      appBar: dukanAppBar(context, l.sale),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: TextField(
                controller: searchController,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: l.searchItems,
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 116,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) => ItemTile(
                  item: items[index],
                  locale: locale,
                  onTap: () => addItem(items[index]),
                  onLongPress: () => openQuantityDialog(items[index]),
                ),
              ),
            ),
            if (cart.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  l.emptySaleHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            SaleCartStrip(
              cart: cart.values.toList(),
              total: total,
              count: count,
              debt: debt,
              customerController: customerController,
              onModeChanged: (value) => setState(() => debt = value),
              onConfirm: confirmSale,
            ),
          ],
        ),
      ),
    );
  }
}

class ItemTile extends StatelessWidget {
  const ItemTile({
    required this.item,
    required this.locale,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });
  final MockItem item;
  final Locale locale;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                item.icon,
                size: 26,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 4),
              Text(
                item.name(locale),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${item.unit(locale)} · ${money(item.price)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SaleCartStrip extends StatelessWidget {
  const SaleCartStrip({
    required this.cart,
    required this.total,
    required this.count,
    required this.debt,
    required this.customerController,
    required this.onModeChanged,
    required this.onConfirm,
    super.key,
  });

  final List<CartEntry> cart;
  final double total;
  final double count;
  final bool debt;
  final TextEditingController customerController;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
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
                    '${l.cart}: ${l.itemsCount(count.round())}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${l.total}: ${money(total)}',
                  style: Theme.of(context).textTheme.titleLarge,
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
                        label: Text(l.cash),
                        icon: const Icon(Icons.payments),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(l.debt),
                        icon: const Icon(Icons.person),
                      ),
                    ],
                    selected: {debt},
                    onSelectionChanged: (set) => onModeChanged(set.first),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: cart.isEmpty ? null : onConfirm,
                    icon: const Icon(Icons.check_circle),
                    label: Text(l.confirm),
                  ),
                ),
              ],
            ),
            if (debt) ...[
              const SizedBox(height: 8),
              InlinePartySearch(
                controller: customerController,
                parties: customers,
                label: l.customerDebt,
                hint: l.searchCustomers,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QtyPrice {
  const _QtyPrice(this.quantity, this.price);
  final double quantity;
  final double? price;
}

class QtyPriceDialog extends StatefulWidget {
  const QtyPriceDialog({required this.item, required this.title, super.key});
  final MockItem item;
  final String title;

  @override
  State<QtyPriceDialog> createState() => _QtyPriceDialogState();
}

class _QtyPriceDialogState extends State<QtyPriceDialog> {
  final qty = TextEditingController(text: '1');
  final price = TextEditingController();
  TextEditingController? active;

  @override
  void initState() {
    super.initState();
    active = qty;
  }

  @override
  void dispose() {
    qty.dispose();
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    label: l.quantity,
                    controller: qty,
                    selected: active == qty,
                    onTap: () => setState(() => active = qty),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NumberField(
                    label: l.optionalPrice,
                    controller: price,
                    selected: active == price,
                    onTap: () => setState(() => active = price),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            BigNumpad(controller: active ?? qty),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            _QtyPrice(
              parseAmount(qty.text),
              price.text.trim().isEmpty ? null : parseAmount(price.text),
            ),
          ),
          icon: const Icon(Icons.add_shopping_cart),
          label: Text(l.addToCart),
        ),
      ],
    );
  }
}
