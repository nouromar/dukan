// Payment-screen state: party type ('customer' or 'supplier'), the
// selected party, the entered amount, and the optional per-invoice
// allocation breakdown (#234). Lifted into a ChangeNotifier so the
// screen survives back/forward navigation (e.g., cashier opens
// Payment, navigates to look up info, returns — typed amount stays).

import 'package:flutter/foundation.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/shared/working_date.dart';

enum PaymentType { customer, supplier }

extension PaymentTypeX on PaymentType {
  String get partyTypeCode =>
      this == PaymentType.customer ? 'customer' : 'supplier';

  /// post_payment direction: 'I' (inbound, customer pays the shop) or
  /// 'O' (outbound, shop pays the supplier).
  String get direction => this == PaymentType.customer ? 'I' : 'O';
}

class PaymentController extends ChangeNotifier with WorkingDateMixin {
  PaymentType _type = PaymentType.customer;
  PartySearchResult? _party;
  num _amount = 0;
  List<PaymentAllocationInput>? _allocations;

  PaymentType get type => _type;
  PartySearchResult? get party => _party;
  num get amount => _amount;

  /// Cashier-chosen per-invoice breakdown. Null on the default path
  /// (server-side FIFO). Non-null only when the cashier opened the
  /// allocation sheet and tapped APPLY.
  List<PaymentAllocationInput>? get allocations => _allocations;

  /// True when an explicit breakdown is in effect for this payment.
  bool get hasExplicitAllocations =>
      _allocations != null && _allocations!.isNotEmpty;

  /// The outstanding balance for the selected party in the active type's
  /// direction. Returns 0 when no party is selected or when type/party
  /// disagree (defensive — UI clears the party on type change).
  num get outstandingBalance {
    final p = _party;
    if (p == null) return 0;
    return _type == PaymentType.customer ? p.receivable : p.payable;
  }

  void setType(PaymentType type) {
    if (_type == type) return;
    _type = type;
    // A customer-typed party makes no sense when the screen flips to
    // supplier — clear so the cashier picks fresh.
    _party = null;
    _amount = 0;
    _allocations = null;
    notifyListeners();
  }

  /// Set the direction at screen-open (Home "Money In"/"Money Out" tile)
  /// WITHOUT notifying — safe to call from `initState`, since the screen reads
  /// `type` in its first build. Clears stale party/amount only when the
  /// direction actually changes. (The notifying [setType] is for the on-screen
  /// toggle and must not run during build.)
  void initType(PaymentType type) {
    if (_type == type) return;
    _type = type;
    _party = null;
    _amount = 0;
    _allocations = null;
  }

  void setParty(PartySearchResult party) {
    if (_party?.id == party.id) return;
    _party = party;
    // A new party invalidates any prior allocation — the invoice ids
    // belonged to the previous party.
    _allocations = null;
    notifyListeners();
  }

  void setAmount(num value) {
    final clamped = value < 0 ? 0 : value;
    if (_amount == clamped) return;
    _amount = clamped;
    // Changing the amount invalidates any prior allocation — the sum
    // would no longer match. Cashier reopens the sheet to re-allocate.
    _allocations = null;
    notifyListeners();
  }

  /// Persist the cashier's per-invoice breakdown from the allocation
  /// sheet. Pass null (or an empty list) to revert to FIFO defaults.
  void setAllocations(List<PaymentAllocationInput>? allocations) {
    if (allocations == null || allocations.isEmpty) {
      if (_allocations == null) return;
      _allocations = null;
    } else {
      _allocations = List.unmodifiable(allocations);
    }
    notifyListeners();
  }

  void clearAll() {
    final wasEmpty =
        _party == null && _amount == 0 && _allocations == null;
    _party = null;
    _amount = 0;
    _allocations = null;
    if (!wasEmpty) notifyListeners();
  }

  /// Snapshot for the optimistic-SAVE dance: the screen snapshots
  /// before clearing, then restores on failure so the cashier sees
  /// their typed values come back instead of having to re-enter.
  PaymentSnapshot snapshot() => PaymentSnapshot(
        type: _type,
        party: _party,
        amount: _amount,
        allocations: _allocations,
      );

  void restore(PaymentSnapshot snapshot) {
    _type = snapshot.type;
    _party = snapshot.party;
    _amount = snapshot.amount;
    _allocations = snapshot.allocations;
    notifyListeners();
  }
}

class PaymentSnapshot {
  const PaymentSnapshot({
    required this.type,
    required this.party,
    required this.amount,
    this.allocations,
  });

  final PaymentType type;
  final PartySearchResult? party;
  final num amount;
  final List<PaymentAllocationInput>? allocations;
}
