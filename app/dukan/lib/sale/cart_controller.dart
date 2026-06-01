// Cart state for the Sale screen. Lifted out of SaleScreen so the cart
// survives across the screen's push/pop — going back to Home does NOT
// abandon the sale. Clearing is explicit (via the Clear-all button in
// the expanded drawer, or by SAVE on a successful post).
//
// Single-cart for v1. Multi-cart (`held: const []` + hold/resume/discard)
// is the documented v2 extension; see docs/decisions.md Q13. The shape
// below is the one we want today so v2 is mechanical rather than
// architectural.

import 'package:flutter/foundation.dart';

import 'package:dukan/api/types.dart';

class CartLine {
  CartLine({
    required this.itemId,
    required this.catalogItemId,
    required this.name,
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required this.unitPrice,
    this.quantity = 1,
    this.priceWasEntered = false,
  });

  final String? itemId;
  final String? catalogItemId;
  final String name;
  final String baseUnitCode;
  final String baseUnitLabel;
  final num unitPrice;
  int quantity;

  /// True if `unitPrice` came out of the long-press / no-price line
  /// editor (tap on a no-price tile, long-press on any tile, long-press
  /// on a cart row). The Sale SAVE flow uses this to call
  /// `set_item_sale_price` so future taps on the same item fast-add at
  /// the entered price instead of re-prompting.
  final bool priceWasEntered;

  num get subtotal => unitPrice * quantity;
}

/// An immutable point-in-time copy of the active cart, used for the SAVE
/// flow: snapshot → clear optimistically → post → on failure restore.
class CartSnapshot {
  const CartSnapshot({
    required this.lines,
    required this.debt,
    required this.customer,
  });

  /// Keyed by item_id or catalog_item_id (whichever is non-null on the
  /// underlying search result).
  final Map<String, CartLine> lines;
  final bool debt;
  final PartySearchResult? customer;
}

class CartController extends ChangeNotifier {
  final Map<String, CartLine> _lines = {};
  bool _debt = false;
  PartySearchResult? _customer;

  /// Active cart view, immutable from the outside. Keys are stable per
  /// item — adding the same search result a second time increments the
  /// existing line's quantity rather than creating a new line.
  Map<String, CartLine> get lines => Map.unmodifiable(_lines);
  bool get debt => _debt;
  PartySearchResult? get customer => _customer;

  int get itemCount =>
      _lines.values.fold(0, (sum, line) => sum + line.quantity);
  double get total =>
      _lines.values.fold(0, (sum, line) => sum + line.subtotal.toDouble());
  bool get isEmpty => _lines.isEmpty;
  bool get isNotEmpty => _lines.isNotEmpty;

  /// Multi-cart v2 shape (docs/decisions.md Q13): always empty in v1.
  /// Stubs below let consumers write code that compiles forward when the
  /// list and methods are turned on.
  List<HeldCart> get held => const [];

  // ----- mutations --------------------------------------------------------

  void addItem(ItemSearchResult item) {
    final key = item.itemId ?? item.catalogItemId;
    if (key == null) return;
    final existing = _lines[key];
    if (existing != null) {
      existing.quantity += 1;
    } else {
      _lines[key] = CartLine(
        itemId: item.itemId,
        catalogItemId: item.catalogItemId,
        name: item.name,
        baseUnitCode: item.baseUnitCode,
        baseUnitLabel: item.baseUnitLabel,
        unitPrice: item.salePrice ?? 0,
      );
    }
    notifyListeners();
  }

  /// Used by the long-press / no-price line editor. Replaces any existing
  /// line for the item with the explicit quantity + unitPrice the cashier
  /// confirmed in the sheet (no incrementing — the editor's quantity is
  /// the authoritative one). Marks the line so SAVE persists the price
  /// back to item.sale_price.
  void addOrReplaceFromEditor(
    ItemSearchResult item, {
    required int quantity,
    required num unitPrice,
  }) {
    final key = item.itemId ?? item.catalogItemId;
    if (key == null) return;
    _lines[key] = CartLine(
      itemId: item.itemId,
      catalogItemId: item.catalogItemId,
      name: item.name,
      baseUnitCode: item.baseUnitCode,
      baseUnitLabel: item.baseUnitLabel,
      unitPrice: unitPrice,
      quantity: quantity,
      priceWasEntered: true,
    );
    notifyListeners();
  }

  /// Used by the long-press editor opened on an existing cart row. Mutates
  /// the line in place (keys are stable). No-op if the line was already
  /// removed between open and confirm. Marks the line so SAVE persists
  /// the price back to item.sale_price.
  void updateLineFromEditor(
    String key, {
    required int quantity,
    required num unitPrice,
  }) {
    final existing = _lines[key];
    if (existing == null) return;
    _lines[key] = CartLine(
      itemId: existing.itemId,
      catalogItemId: existing.catalogItemId,
      name: existing.name,
      baseUnitCode: existing.baseUnitCode,
      baseUnitLabel: existing.baseUnitLabel,
      unitPrice: unitPrice,
      quantity: quantity,
      priceWasEntered: true,
    );
    notifyListeners();
  }

  void removeLine(String key) {
    if (_lines.remove(key) == null) return;
    notifyListeners();
  }

  void clearAll() {
    final wasEmpty = _lines.isEmpty && !_debt && _customer == null;
    _lines.clear();
    _debt = false;
    _customer = null;
    if (!wasEmpty) notifyListeners();
  }

  void setDebt(bool value) {
    if (_debt == value) return;
    _debt = value;
    notifyListeners();
  }

  void setCustomer(PartySearchResult? customer) {
    if (_customer == customer) return;
    _customer = customer;
    notifyListeners();
  }

  // ----- save flow helpers -----------------------------------------------

  /// Returns a deep-copy snapshot so the caller can clear the cart
  /// optimistically and still restore the lines if the network post
  /// later fails.
  CartSnapshot snapshot() {
    return CartSnapshot(
      lines: {
        for (final entry in _lines.entries)
          entry.key: CartLine(
            itemId: entry.value.itemId,
            catalogItemId: entry.value.catalogItemId,
            name: entry.value.name,
            baseUnitCode: entry.value.baseUnitCode,
            baseUnitLabel: entry.value.baseUnitLabel,
            unitPrice: entry.value.unitPrice,
            quantity: entry.value.quantity,
            priceWasEntered: entry.value.priceWasEntered,
          ),
      },
      debt: _debt,
      customer: _customer,
    );
  }

  /// Restores a snapshot into the live cart (e.g., after a post failed
  /// and the user needs to correct + re-save).
  void restore(CartSnapshot snapshot) {
    _lines
      ..clear()
      ..addAll(snapshot.lines);
    _debt = snapshot.debt;
    _customer = snapshot.customer;
    notifyListeners();
  }

  // ----- v2 multi-cart stubs (per decisions.md Q13) ----------------------

  /// Hold the active cart under a label and start fresh. v2.
  void hold(String label) {
    throw UnimplementedError(
      'Multi-cart is deferred to v2; see docs/decisions.md Q13.',
    );
  }

  /// Swap a held cart into the active slot. v2.
  void resume(String heldCartId) {
    throw UnimplementedError(
      'Multi-cart is deferred to v2; see docs/decisions.md Q13.',
    );
  }

  /// Discard a held cart. v2.
  void discard(String heldCartId) {
    throw UnimplementedError(
      'Multi-cart is deferred to v2; see docs/decisions.md Q13.',
    );
  }
}

/// Placeholder for the v2 held-cart record. Kept in the same file so when
/// multi-cart ships, the model lives next to the controller that owns it.
/// In v1 the `held` list is always empty so this type is never instantiated.
class HeldCart {
  const HeldCart({required this.id, required this.label});
  final String id;
  final String label;
}
