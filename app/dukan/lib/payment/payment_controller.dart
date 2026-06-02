// Payment-screen state: party type ('customer' or 'supplier'), the
// selected party, and the entered amount. Lifted into a ChangeNotifier
// so the screen survives back/forward navigation (e.g., cashier opens
// Payment, navigates to look up info, returns — typed amount stays).

import 'package:flutter/foundation.dart';

import 'package:dukan/api/types.dart';

enum PaymentType { customer, supplier }

extension PaymentTypeX on PaymentType {
  String get partyTypeCode =>
      this == PaymentType.customer ? 'customer' : 'supplier';

  /// post_payment direction: 'I' (inbound, customer pays the shop) or
  /// 'O' (outbound, shop pays the supplier).
  String get direction => this == PaymentType.customer ? 'I' : 'O';
}

class PaymentController extends ChangeNotifier {
  PaymentType _type = PaymentType.customer;
  PartySearchResult? _party;
  num _amount = 0;

  PaymentType get type => _type;
  PartySearchResult? get party => _party;
  num get amount => _amount;

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
    notifyListeners();
  }

  void setParty(PartySearchResult party) {
    if (_party?.id == party.id) return;
    _party = party;
    notifyListeners();
  }

  void setAmount(num value) {
    final clamped = value < 0 ? 0 : value;
    if (_amount == clamped) return;
    _amount = clamped;
    notifyListeners();
  }

  void clearAll() {
    final wasEmpty = _party == null && _amount == 0;
    _party = null;
    _amount = 0;
    if (!wasEmpty) notifyListeners();
  }
}
