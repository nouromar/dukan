// Receive-screen state: the supplier we're recording a bono from + the
// lines we've accumulated. Lifted out of the screen widgets so the
// state survives back/forward navigation between the supplier picker,
// the receive screen, and (eventually) a bono-photo capture flow.
//
// v2 model: receive lines key on `shopItemUnitId` — the packaging the
// supplier delivered. Same item received as a 25 kg bag and a 10 kg
// bag in the same bono are two distinct lines (correct: they have
// different per-packaging last_cost values).
//
// SAVE always posts a fully-credit receive transaction (decisions.md
// Q15 — TODO). Cash paid at delivery is recorded separately via the
// Payment screen so receive stays narrowly about stock + cost capture.

import 'package:flutter/foundation.dart';

import 'package:dukan/api/types.dart';

class ReceiveLine {
  ReceiveLine({
    required this.shopItemUnitId,
    required this.shopItemId,
    required this.itemId,
    required this.displayName,
    required this.packagingLabel,
    required this.baseUnitLabel,
    required this.quantity,
    required this.lineTotal,
  });

  /// The packaging this bono line was rung up against. The server
  /// derives shop_item, base_quantity, conversion and stock_movement
  /// unit_cost from this id at post time.
  final String shopItemUnitId;
  final String shopItemId;

  /// Null when this is a shop-only item (no global catalog provenance).
  final String? itemId;

  final String displayName;

  /// "25 kg bag" / "kg" — what the cashier sees on the chip.
  final String packagingLabel;
  final String baseUnitLabel;

  /// Numeric so weighed-on-delivery items (e.g., 12.5 kg of meat) can
  /// land on a bono without forcing integerization. Server's
  /// `transaction_line.quantity` is already `numeric(14,3)`.
  final num quantity;

  /// What the cashier entered as the bono line total. Sent to
  /// post_receive as line_total; per-unit cost (= lineTotal / quantity)
  /// is computed server-side.
  final num lineTotal;

  num get unitCost => quantity == 0 ? 0 : lineTotal / quantity;
}

class ReceiveSnapshot {
  const ReceiveSnapshot({required this.lines, required this.supplier});

  /// Keyed by `shopItemUnitId`.
  final Map<String, ReceiveLine> lines;
  final PartySearchResult? supplier;
}

class ReceiveController extends ChangeNotifier {
  final Map<String, ReceiveLine> _lines = {};
  PartySearchResult? _supplier;

  Map<String, ReceiveLine> get lines => Map.unmodifiable(_lines);
  PartySearchResult? get supplier => _supplier;

  int get lineCount => _lines.length;
  num get unitCount =>
      _lines.values.fold<num>(0, (sum, line) => sum + line.quantity);
  double get bonoTotal =>
      _lines.values.fold(0, (sum, line) => sum + line.lineTotal.toDouble());
  bool get isEmpty => _lines.isEmpty;
  bool get isNotEmpty => _lines.isNotEmpty;

  // ----- mutations --------------------------------------------------------

  void setSupplier(PartySearchResult supplier) {
    if (_supplier?.id == supplier.id) return;
    _supplier = supplier;
    notifyListeners();
  }

  /// Add a new line OR replace an existing line for the same
  /// packaging. Every editor confirmation is authoritative — the
  /// cashier may be correcting a previous qty/total.
  void addOrReplaceLine({
    required String shopItemUnitId,
    required String shopItemId,
    required String? itemId,
    required String displayName,
    required String packagingLabel,
    required String baseUnitLabel,
    required num quantity,
    required num lineTotal,
  }) {
    _lines[shopItemUnitId] = ReceiveLine(
      shopItemUnitId: shopItemUnitId,
      shopItemId: shopItemId,
      itemId: itemId,
      displayName: displayName,
      packagingLabel: packagingLabel,
      baseUnitLabel: baseUnitLabel,
      quantity: quantity,
      lineTotal: lineTotal,
    );
    notifyListeners();
  }

  /// Used when the cashier swaps the packaging on an existing line
  /// (e.g., they typed bono qty against "25 kg bag" then realized the
  /// supplier delivered "50 kg bag"). Removes the old keyed line and
  /// adds the new keyed line in one notify.
  void switchLinePackaging({
    required String oldShopItemUnitId,
    required String newShopItemUnitId,
    required String shopItemId,
    required String? itemId,
    required String displayName,
    required String packagingLabel,
    required String baseUnitLabel,
    required num quantity,
    required num lineTotal,
  }) {
    _lines.remove(oldShopItemUnitId);
    _lines[newShopItemUnitId] = ReceiveLine(
      shopItemUnitId: newShopItemUnitId,
      shopItemId: shopItemId,
      itemId: itemId,
      displayName: displayName,
      packagingLabel: packagingLabel,
      baseUnitLabel: baseUnitLabel,
      quantity: quantity,
      lineTotal: lineTotal,
    );
    notifyListeners();
  }

  void removeLine(String shopItemUnitId) {
    if (_lines.remove(shopItemUnitId) == null) return;
    notifyListeners();
  }

  /// Wipes lines; keeps the supplier so the cashier can re-enter
  /// without re-picking.
  void clearLines() {
    if (_lines.isEmpty) return;
    _lines.clear();
    notifyListeners();
  }

  /// Full reset: clears lines + supplier. Used after a successful save
  /// or on session sign-out.
  void clearAll() {
    final wasEmpty = _lines.isEmpty && _supplier == null;
    _lines.clear();
    _supplier = null;
    if (!wasEmpty) notifyListeners();
  }

  // ----- save flow helpers -----------------------------------------------

  ReceiveSnapshot snapshot() {
    return ReceiveSnapshot(
      lines: {
        for (final entry in _lines.entries)
          entry.key: ReceiveLine(
            shopItemUnitId: entry.value.shopItemUnitId,
            shopItemId: entry.value.shopItemId,
            itemId: entry.value.itemId,
            displayName: entry.value.displayName,
            packagingLabel: entry.value.packagingLabel,
            baseUnitLabel: entry.value.baseUnitLabel,
            quantity: entry.value.quantity,
            lineTotal: entry.value.lineTotal,
          ),
      },
      supplier: _supplier,
    );
  }

  void restore(ReceiveSnapshot snapshot) {
    _lines
      ..clear()
      ..addAll(snapshot.lines);
    _supplier = snapshot.supplier;
    notifyListeners();
  }
}
