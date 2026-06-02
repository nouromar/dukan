// Receive-screen state: the supplier we're recording a bono from + the
// lines we've accumulated. Lifted out of the screen widgets so the state
// survives back/forward navigation between the supplier picker, the
// receive screen, and (eventually) a bono-photo capture flow.
//
// Single-supplier-at-a-time for v1 (matches the Sale single-cart). Held
// supplier sessions are not modelled.
//
// SAVE always posts a fully-credit receive transaction (decisions.md
// Q15 — TODO). Cash paid at delivery is recorded separately via the
// Payment screen so receive stays narrowly about stock + cost capture.

import 'package:flutter/foundation.dart';

import 'package:dukan/api/types.dart';

class ReceiveLine {
  ReceiveLine({
    required this.itemId,
    required this.catalogItemId,
    required this.name,
    required this.receiveUnitCode,
    required this.receiveUnitLabel,
    required this.quantity,
    required this.lineTotal,
  });

  /// Non-null for activated items. Null for catalog candidates that
  /// need ensure_shop_item resolution before posting.
  final String? itemId;
  /// Non-null for catalog candidates; null for already-activated items.
  final String? catalogItemId;
  final String name;
  /// The receive unit (e.g., "bag") the supplier delivered in.
  /// Lookups its unit_id at post time via the units cache.
  final String receiveUnitCode;
  final String receiveUnitLabel;
  final int quantity;
  /// What the cashier entered as the bono line total. Sent to
  /// post_receive as line_total; per-unit cost (= lineTotal / quantity)
  /// is computed server-side.
  final num lineTotal;

  num get unitCost => quantity == 0 ? 0 : lineTotal / quantity;
}

class ReceiveSnapshot {
  const ReceiveSnapshot({required this.lines, required this.supplier});

  final Map<String, ReceiveLine> lines;
  final PartySearchResult? supplier;
}

class ReceiveController extends ChangeNotifier {
  final Map<String, ReceiveLine> _lines = {};
  PartySearchResult? _supplier;

  Map<String, ReceiveLine> get lines => Map.unmodifiable(_lines);
  PartySearchResult? get supplier => _supplier;

  int get lineCount => _lines.length;
  int get unitCount =>
      _lines.values.fold(0, (sum, line) => sum + line.quantity);
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

  /// Add a new line OR replace an existing line for the same item.
  /// Unlike Sale's `addItem`, every editor confirmation is authoritative:
  /// the cashier might be correcting a previous qty/total.
  void addOrReplaceLine(
    ItemSearchResult item, {
    required int quantity,
    required num lineTotal,
  }) {
    final key = item.itemId ?? item.catalogItemId;
    if (key == null) return;
    _lines[key] = ReceiveLine(
      itemId: item.itemId,
      catalogItemId: item.catalogItemId,
      name: item.name,
      receiveUnitCode: item.receiveUnitCode,
      receiveUnitLabel: item.receiveUnitLabel,
      quantity: quantity,
      lineTotal: lineTotal,
    );
    notifyListeners();
  }

  void removeLine(String key) {
    if (_lines.remove(key) == null) return;
    notifyListeners();
  }

  /// Wipes lines; keeps the supplier so the cashier can re-enter without
  /// re-picking from the supplier screen.
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
            itemId: entry.value.itemId,
            catalogItemId: entry.value.catalogItemId,
            name: entry.value.name,
            receiveUnitCode: entry.value.receiveUnitCode,
            receiveUnitLabel: entry.value.receiveUnitLabel,
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
