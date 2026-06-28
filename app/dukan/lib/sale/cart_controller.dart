// Cart state for the Sale screen. Lifted out of SaleScreen so the cart
// survives across the screen's push/pop — going back to Home does NOT
// abandon the sale. Clearing is explicit (via the Clear-all button in
// the expanded drawer, or by SAVE on a successful post).
//
// v2 model: cart lines are keyed by `shopItemUnitId` (the packaging),
// not by item. Selling 1 bag and 1 kg loose of the same item is two
// distinct lines because the cashier rang up two distinct packagings.
// Switching a line's packaging in the long-press editor is a
// remove-and-add (the key changes).
//
// Single-cart for v1. Multi-cart (`held: const []` + hold/resume/discard)
// is the documented v2 extension; see docs/decisions.md Q13.

import 'package:flutter/foundation.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/shared/working_date.dart';

class CartLine {
  CartLine({
    required this.shopItemUnitId,
    required this.shopItemId,
    required this.itemId,
    required this.displayName,
    required this.packagingLabel,
    required this.baseUnitLabel,
    required this.unitPrice,
    this.quantity = 1,
    this.priceWasEntered = false,
  });

  /// Primary key for the cart map.
  final String shopItemUnitId;

  /// The parent shop_item (one item, possibly multiple packagings on
  /// distinct cart lines). Kept so the Sale screen can group / dedupe
  /// when needed (e.g., for stock-impact previews).
  final String shopItemId;

  /// Null when the line came from a shop-only item.
  final String? itemId;

  final String displayName;

  /// Derived "25 kg bag" / "kg" — already locale-resolved by the search RPC.
  final String packagingLabel;

  /// Base unit's display label (e.g., "Kg") — useful when showing
  /// "= 25 kg" subtotals for multi-packaging items.
  final String baseUnitLabel;

  final num unitPrice;
  /// Numeric to allow fractional units (e.g., 0.5 kg of rice loose).
  /// Server's `transaction_line.quantity` is already `numeric(14,3)`.
  num quantity;

  /// True if `unitPrice` came out of the long-press / no-price line
  /// editor. The Sale SAVE flow uses this to call
  /// `setShopItemUnitSalePrice` so future taps on the same packaging
  /// fast-add at the entered price instead of re-prompting.
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
    this.occurredAt,
  });

  /// Keyed by `shopItemUnitId`.
  final Map<String, CartLine> lines;
  final bool debt;
  final PartySearchResult? customer;

  /// Backdated transaction date (#5); null = today (post stamps now()).
  final DateTime? occurredAt;
}

class CartController extends ChangeNotifier with WorkingDateMixin {
  final Map<String, CartLine> _lines = {};
  bool _debt = false;
  PartySearchResult? _customer;

  /// Active cart view, immutable from the outside. Keys are stable per
  /// packaging — adding the same packaging a second time increments
  /// the existing line's quantity rather than creating a new line.
  Map<String, CartLine> get lines => Map.unmodifiable(_lines);
  bool get debt => _debt;
  PartySearchResult? get customer => _customer;

  /// "Items in cart" — sum of integer line counts (one line counted
  /// once per row). Fractional qty is for the per-line math; the
  /// cart summary counts rows, not weight.
  int get itemCount => _lines.length;
  double get total =>
      _lines.values.fold(0, (sum, line) => sum + line.subtotal.toDouble());
  bool get isEmpty => _lines.isEmpty;
  bool get isNotEmpty => _lines.isNotEmpty;

  /// Multi-cart v2 shape (docs/decisions.md Q13): always empty in v1.
  List<HeldCart> get held => const [];

  // ----- mutations --------------------------------------------------------

  /// Default tap path. Requires the search result to be activated
  /// (defaultShopItemUnitId non-null). The Sale screen ensures this by
  /// calling ensureShopItem before reaching here on unactivated items.
  void addItem(ItemSearchResult item) {
    final shopItemUnitId = item.defaultShopItemUnitId;
    final shopItemId = item.shopItemId;
    if (shopItemUnitId == null || shopItemId == null) return;
    final existing = _lines[shopItemUnitId];
    if (existing != null) {
      existing.quantity += 1;
    } else {
      _lines[shopItemUnitId] = CartLine(
        shopItemUnitId: shopItemUnitId,
        shopItemId: shopItemId,
        itemId: item.itemId,
        displayName: item.displayName,
        packagingLabel: item.packagingLabel ?? item.baseUnitLabel,
        baseUnitLabel: item.baseUnitLabel,
        unitPrice: item.defaultUnitSalePrice ?? 0,
      );
    }
    notifyListeners();
  }

  /// Used by the long-press / no-price line editor when adding a new
  /// line (cashier picked a packaging + entered a price in the sheet).
  /// Replaces any existing line for the same packaging with the
  /// explicit quantity + unitPrice. Marks the line so SAVE persists
  /// the price.
  void addOrReplaceFromEditor({
    required String shopItemUnitId,
    required String shopItemId,
    required String? itemId,
    required String displayName,
    required String packagingLabel,
    required String baseUnitLabel,
    required num quantity,
    required num unitPrice,
  }) {
    _lines[shopItemUnitId] = CartLine(
      shopItemUnitId: shopItemUnitId,
      shopItemId: shopItemId,
      itemId: itemId,
      displayName: displayName,
      packagingLabel: packagingLabel,
      baseUnitLabel: baseUnitLabel,
      unitPrice: unitPrice,
      quantity: quantity,
      priceWasEntered: true,
    );
    notifyListeners();
  }

  /// Used by the long-press editor opened on an existing cart row,
  /// when the cashier did NOT switch packaging. Mutates the line in
  /// place. No-op if the line was already removed between open and
  /// confirm. Marks the line so SAVE persists the price.
  void updateLineFromEditor(
    String shopItemUnitId, {
    required num quantity,
    required num unitPrice,
  }) {
    final existing = _lines[shopItemUnitId];
    if (existing == null) return;
    _lines[shopItemUnitId] = CartLine(
      shopItemUnitId: existing.shopItemUnitId,
      shopItemId: existing.shopItemId,
      itemId: existing.itemId,
      displayName: existing.displayName,
      packagingLabel: existing.packagingLabel,
      baseUnitLabel: existing.baseUnitLabel,
      unitPrice: unitPrice,
      quantity: quantity,
      priceWasEntered: true,
    );
    notifyListeners();
  }

  /// Long-press editor used to switch a line's packaging — the key
  /// changes, so we remove the old line and add the new one in a
  /// single notification.
  void switchLinePackaging({
    required String oldShopItemUnitId,
    required String newShopItemUnitId,
    required String shopItemId,
    required String? itemId,
    required String displayName,
    required String packagingLabel,
    required String baseUnitLabel,
    required num quantity,
    required num unitPrice,
  }) {
    _lines.remove(oldShopItemUnitId);
    _lines[newShopItemUnitId] = CartLine(
      shopItemUnitId: newShopItemUnitId,
      shopItemId: shopItemId,
      itemId: itemId,
      displayName: displayName,
      packagingLabel: packagingLabel,
      baseUnitLabel: baseUnitLabel,
      unitPrice: unitPrice,
      quantity: quantity,
      priceWasEntered: true,
    );
    notifyListeners();
  }

  void removeLine(String shopItemUnitId) {
    if (_lines.remove(shopItemUnitId) == null) return;
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
            shopItemUnitId: entry.value.shopItemUnitId,
            shopItemId: entry.value.shopItemId,
            itemId: entry.value.itemId,
            displayName: entry.value.displayName,
            packagingLabel: entry.value.packagingLabel,
            baseUnitLabel: entry.value.baseUnitLabel,
            unitPrice: entry.value.unitPrice,
            quantity: entry.value.quantity,
            priceWasEntered: entry.value.priceWasEntered,
          ),
      },
      debt: _debt,
      customer: _customer,
      occurredAt: workingDate,
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

  void hold(String label) {
    throw UnimplementedError(
      'Multi-cart is deferred to v2; see docs/decisions.md Q13.',
    );
  }

  void resume(String heldCartId) {
    throw UnimplementedError(
      'Multi-cart is deferred to v2; see docs/decisions.md Q13.',
    );
  }

  void discard(String heldCartId) {
    throw UnimplementedError(
      'Multi-cart is deferred to v2; see docs/decisions.md Q13.',
    );
  }
}

/// Placeholder for the v2 held-cart record.
class HeldCart {
  const HeldCart({required this.id, required this.label});
  final String id;
  final String label;
}
