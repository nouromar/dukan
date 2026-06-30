// Per-shop capability set for the authenticated user. Loaded once on
// shop selection via auth_user_shop_capabilities() and held in
// AuthController; consumed via Provider for UI gating.
//
// Capability codes mirror the seed in supabase/migrations/0048 and
// docs/roles-and-permissions.md §6. The named getters cover the
// codes the mobile UI currently consults — adding a new capability
// gate is "add a getter here, add a check at the use site." No
// hardcoded role string survives in the screens.
//
// The empty-set fallback (Capabilities.empty()) is what the app uses
// while the load is in flight or when no shop is selected — gates
// default to "denied" so the cashier can't see anything they don't
// have explicit access to.

import 'package:flutter/foundation.dart';

@immutable
class Capabilities {
  const Capabilities(this._codes);

  /// Construct from the raw jsonb array returned by
  /// auth_user_shop_capabilities. Accepts the dynamic shape Supabase
  /// gives us (`List<dynamic>` of String).
  factory Capabilities.fromRaw(Object? raw) {
    if (raw is! Iterable) return const Capabilities(<String>{});
    return Capabilities(
      raw
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet(),
    );
  }

  factory Capabilities.empty() => const Capabilities(<String>{});

  /// Test helper — construct from a literal list of codes.
  @visibleForTesting
  factory Capabilities.forTesting(Iterable<String> codes) =>
      Capabilities(Set<String>.from(codes));

  final Set<String> _codes;

  /// Raw set, for debugging or unusual gates. Prefer the named
  /// getters below at use sites so we have a registry of what's
  /// actually consulted.
  Set<String> get codes => Set<String>.unmodifiable(_codes);

  bool has(String code) => _codes.contains(code);

  // ---- Sales ----
  bool get canPostSale => has('sales.post');
  bool get canViewSalesHistory => has('sales.history.view');
  bool get canVoidSale => has('sales.void');

  // ---- Receive ----
  bool get canPostReceive => has('receive.post');
  bool get canViewReceiveHistory => has('receive.history.view');
  bool get canVoidReceive => has('receive.void');

  // ---- Payment / Expense ----
  bool get canPostPayment => has('payment.post');
  bool get canViewPaymentHistory => has('payment.history.view');
  bool get canPostExpense => has('expense.post');
  bool get canViewExpenseHistory => has('expense.history.view');
  bool get canVoidPayment => has('payment.void');
  bool get canVoidExpense => has('expense.void');

  // ---- Inventory ----
  bool get canViewProducts => has('inventory.product.view');
  bool get canEditProducts => has('inventory.product.edit');
  bool get canCreateProducts => has('inventory.product.create');
  bool get canActivateFromCatalog => has('inventory.product.activate');
  bool get canBindBarcode => has('inventory.barcode.bind');
  bool get canAdjustStock => has('inventory.adjustment.post');
  bool get canManageCategories => has('inventory.category.manage');

  // ---- People ----
  bool get canViewParties => has('people.party.view');
  bool get canCreateParty => has('people.party.create');
  bool get canEditParty => has('people.party.edit');
  bool get canPostOpeningBalance => has('people.party.opening_balance');

  // ---- Setup / Dashboard ----
  bool get canEditShopSettings => has('setup.shop.edit');
  bool get canViewDashboard => has('dashboard.view');

  @override
  bool operator ==(Object other) =>
      other is Capabilities && setEquals(_codes, other._codes);

  @override
  int get hashCode => Object.hashAll(_codes.toList()..sort());

  @override
  String toString() {
    final sorted = _codes.toList()..sort();
    return 'Capabilities($sorted)';
  }
}
