// Receive-screen state: the supplier we're recording a bono from + the
// lines we've accumulated. Lifted out of the screen widgets so the state
// survives back/forward navigation between the supplier picker, the
// receive screen, and (eventually) a bono-photo capture flow.
//
// Single-supplier-at-a-time for v1 (matches the Sale single-cart). Held
// supplier sessions are not modelled; if the cashier abandons a partial
// bono and starts a new one, an explicit Clear-all on the Receive screen
// wipes lines (no implicit reset on supplier-change).

import 'package:flutter/foundation.dart';

import 'package:dukan/api/types.dart';

class ReceiveLine {
  ReceiveLine({
    required this.itemId,
    required this.catalogItemId,
    required this.name,
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required this.unitCost,
    this.quantity = 1,
  });

  /// Non-null for activated items. Null for catalog candidates that need
  /// `ensure_shop_item` resolution before posting.
  final String? itemId;
  /// Non-null for catalog candidates; null for already-activated items.
  final String? catalogItemId;
  final String name;
  final String baseUnitCode;
  final String baseUnitLabel;
  /// Per-unit cost in base units. Always > 0 — receive lines without a
  /// real cost are rejected at the inline form layer before they reach
  /// the controller.
  final num unitCost;
  int quantity;

  num get subtotal => unitCost * quantity;
}

class ReceiveSnapshot {
  const ReceiveSnapshot({
    required this.lines,
    required this.supplier,
    required this.paidAmount,
  });

  final Map<String, ReceiveLine> lines;
  final PartySearchResult? supplier;
  final num paidAmount;
}

class ReceiveController extends ChangeNotifier {
  final Map<String, ReceiveLine> _lines = {};
  PartySearchResult? _supplier;
  num _paidAmount = 0;

  Map<String, ReceiveLine> get lines => Map.unmodifiable(_lines);
  PartySearchResult? get supplier => _supplier;
  num get paidAmount => _paidAmount;

  int get lineCount => _lines.length;
  int get unitCount =>
      _lines.values.fold(0, (sum, line) => sum + line.quantity);
  double get bonoTotal =>
      _lines.values.fold(0, (sum, line) => sum + line.subtotal.toDouble());
  double get credit => (bonoTotal - _paidAmount).toDouble().clamp(0, double.infinity);
  bool get isEmpty => _lines.isEmpty;
  bool get isNotEmpty => _lines.isNotEmpty;

  // ----- mutations --------------------------------------------------------

  void setSupplier(PartySearchResult supplier) {
    if (_supplier?.id == supplier.id) return;
    _supplier = supplier;
    notifyListeners();
  }

  /// Add a new line OR replace an existing line for the same item. Unlike
  /// Sale's `addItem` which increments quantity on repeat, Receive treats
  /// every confirmation of the inline form as authoritative — the cashier
  /// may be correcting a previous line's qty/cost.
  void addOrReplaceLine(
    ItemSearchResult item, {
    required int quantity,
    required num unitCost,
  }) {
    final key = item.itemId ?? item.catalogItemId;
    if (key == null) return;
    _lines[key] = ReceiveLine(
      itemId: item.itemId,
      catalogItemId: item.catalogItemId,
      name: item.name,
      baseUnitCode: item.baseUnitCode,
      baseUnitLabel: item.baseUnitLabel,
      unitCost: unitCost,
      quantity: quantity,
    );
    notifyListeners();
  }

  void removeLine(String key) {
    if (_lines.remove(key) == null) return;
    notifyListeners();
  }

  void setPaidAmount(num value) {
    final clamped = value < 0 ? 0 : value;
    if (_paidAmount == clamped) return;
    _paidAmount = clamped;
    notifyListeners();
  }

  /// Wipes lines + paid; keeps the supplier so the cashier can re-enter
  /// without re-picking from the supplier screen.
  void clearLines() {
    final wasEmpty = _lines.isEmpty && _paidAmount == 0;
    _lines.clear();
    _paidAmount = 0;
    if (!wasEmpty) notifyListeners();
  }

  /// Full reset: clears lines + paid + supplier. Used when the bono is
  /// successfully posted or when the cashier explicitly leaves Receive.
  void clearAll() {
    final wasEmpty = _lines.isEmpty && _supplier == null && _paidAmount == 0;
    _lines.clear();
    _supplier = null;
    _paidAmount = 0;
    if (!wasEmpty) notifyListeners();
  }

  // ----- save flow helpers -----------------------------------------------

  ReceiveSnapshot snapshot() {
    return ReceiveSnapshot(
      lines: {
        for (final entry in _lines.entries)
          entry.key: ReceiveLine(
            itemId: entry.value.itemId,
            catalogItemId: entry.value.catalogItemId,
            name: entry.value.name,
            baseUnitCode: entry.value.baseUnitCode,
            baseUnitLabel: entry.value.baseUnitLabel,
            unitCost: entry.value.unitCost,
            quantity: entry.value.quantity,
          ),
      },
      supplier: _supplier,
      paidAmount: _paidAmount,
    );
  }

  void restore(ReceiveSnapshot snapshot) {
    _lines
      ..clear()
      ..addAll(snapshot.lines);
    _supplier = snapshot.supplier;
    _paidAmount = snapshot.paidAmount;
    notifyListeners();
  }
}
