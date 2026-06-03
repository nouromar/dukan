// Stateless data layer over Supabase RPCs and PostgREST. Holds no UI
// state — AuthController stays the single owner of session, shops,
// selectedShop, etc. Screens read AuthController for state and ShopApi
// for data; after a write that affects shop-level state (e.g.
// applyTemplate, completeSetup, updateShopDefaults), the screen calls
// auth.refreshSelectedShop() to pull the new row.

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/types.dart';

class ShopApi {
  ShopApi(this._client);

  final SupabaseClient _client;

  // ----- Templates / setup --------------------------------------------------

  Future<List<TemplateOption>> listAvailableTemplates() async {
    final rows = await _client
        .from('template')
        .select('id, code, name')
        .eq('is_active', true)
        .order('name');
    return rows
        .map<TemplateOption>(
          (row) => TemplateOption.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<void> applyTemplate({
    required String shopId,
    required String templateId,
  }) async {
    await _client.rpc(
      'apply_template',
      params: {'p_shop_id': shopId, 'p_template_id': templateId},
    );
  }

  Future<void> completeSetup({required String shopId}) async {
    await _client.rpc('complete_shop_setup', params: {'p_shop_id': shopId});
  }

  // ----- Catalog / items ----------------------------------------------------

  Future<String> ensureShopItem({
    required String shopId,
    required String catalogItemId,
  }) async {
    final result = await _client.rpc(
      'ensure_shop_item',
      params: {'p_shop_id': shopId, 'p_catalog_item_id': catalogItemId},
    );
    return result as String;
  }

  /// Lists every unit configured for an item (or catalog candidate
  /// if the shop has not yet activated it). Pass exactly one of itemId
  /// or catalogItemId. The `screen` arg decides which default flag the
  /// picker highlights (`sale` → default_sale_unit, `receive` →
  /// default_receive_unit).
  Future<List<ReceiveUnitOption>> listItemUnits({
    required String shopId,
    String? itemId,
    String? catalogItemId,
    String screen = 'receive',
  }) async {
    final rows = await _client.rpc(
      'list_item_units',
      params: {
        'p_shop_id': shopId,
        'p_item_id': itemId,
        'p_catalog_item_id': catalogItemId,
        'p_screen': screen,
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<ReceiveUnitOption>(
          (row) => ReceiveUnitOption.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  /// Persists `sale_price` on a shop's item. Called by the Sale SAVE
  /// flow after a successful post_sale for every line whose unit price
  /// came out of the line editor — future taps on that tile then
  /// fast-add at the entered price instead of re-prompting.
  Future<void> setItemSalePrice({
    required String shopId,
    required String itemId,
    required num salePrice,
  }) async {
    await _client.rpc(
      'set_item_sale_price',
      params: {
        'p_shop_id': shopId,
        'p_item_id': itemId,
        'p_sale_price': salePrice,
      },
    );
  }

  Future<List<ItemSearchResult>> searchItems({
    required String shopId,
    String query = '',
    int limit = 50,
    String? screen,
    String? locale,
    String? partyId,
  }) async {
    final rows = await _client.rpc(
      'search_items',
      params: {
        'p_shop_id': shopId,
        'p_query': query,
        'p_limit': limit,
        if (screen != null) 'p_screen': screen, // ignore: use_null_aware_elements
        if (locale != null) 'p_locale': locale, // ignore: use_null_aware_elements
        if (partyId != null) 'p_party_id': partyId, // ignore: use_null_aware_elements
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<ItemSearchResult>(
          (row) => ItemSearchResult.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  // ----- Parties ------------------------------------------------------------

  /// Creates a new customer or supplier and returns the new party_id.
  /// Cashier-accessible (operational data, not setup). Pickers call this
  /// from their + NEW {CUSTOMER,SUPPLIER} affordances; the new party is
  /// auto-selected on success.
  Future<String> createParty({
    required String shopId,
    required String name,
    required String typeCode,
    String? phone,
  }) async {
    final result = await _client.rpc(
      'create_party',
      params: {
        'p_shop_id': shopId,
        'p_name': name,
        'p_phone': phone,
        'p_type_code': typeCode,
      },
    );
    return result as String;
  }

  Future<List<PartySearchResult>> searchParties({
    required String shopId,
    String query = '',
    String type = 'customer',
    int limit = 50,
  }) async {
    final rows = await _client.rpc(
      'search_parties',
      params: {
        'p_shop_id': shopId,
        'p_query': query,
        'p_type': type,
        'p_limit': limit,
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<PartySearchResult>(
          (row) => PartySearchResult.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  // ----- Posting RPCs -------------------------------------------------------

  Future<String> postSale({
    required String shopId,
    required List<SaleLine> lines,
    required num paidAmount,
    String? partyId,
    String? paymentMethodCode,
    required String clientOpId,
    String? notes,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('post_sale requires at least one line');
    }
    final result = await _client.rpc(
      'post_sale',
      params: {
        'p_shop_id': shopId,
        'p_party_id': partyId,
        'p_lines': lines.map((l) => l.toJson()).toList(),
        'p_paid_amount': paidAmount,
        'p_payment_method_code': paymentMethodCode,
        'p_client_op_id': clientOpId,
        'p_notes': notes,
      },
    );
    return result as String;
  }

  /// Lists the active expense categories for a shop (Rent, Salary,
  /// etc.) with the name resolved to the requested locale via the
  /// stored `name_translations` jsonb.
  Future<List<ExpenseCategoryOption>> listExpenseCategories({
    required String shopId,
    String? locale,
  }) async {
    final rows = await _client
        .from('expense_category')
        .select('id, code, name, name_translations')
        .eq('shop_id', shopId)
        .eq('is_active', true)
        .order('name');
    return rows
        .map<ExpenseCategoryOption>(
          (row) => ExpenseCategoryOption.fromJson(
            Map<String, dynamic>.from(row),
            locale: locale,
          ),
        )
        .toList(growable: false);
  }

  /// post_expense — records a one-line expense transaction. v1 uses
  /// 'cash' as the default payment method.
  Future<String> postExpense({
    required String shopId,
    required String expenseCategoryId,
    required num amount,
    required String paymentMethodCode,
    required String clientOpId,
    String? notes,
  }) async {
    final result = await _client.rpc(
      'post_expense',
      params: {
        'p_shop_id': shopId,
        'p_expense_category_id': expenseCategoryId,
        'p_amount': amount,
        'p_payment_method_code': paymentMethodCode,
        'p_client_op_id': clientOpId,
        'p_notes': notes,
      },
    );
    return result as String;
  }

  /// Lists past sales (originals only) reverse-chronological. `before`
  /// is the pagination cursor: pass the oldest `occurredAt` from the
  /// previous page to fetch older rows.
  Future<List<SaleSummary>> listSales({
    required String shopId,
    DateTime? before,
    int limit = 50,
  }) async {
    final rows = await _client.rpc(
      'list_sales',
      params: {
        'p_shop_id': shopId,
        'p_before': before?.toIso8601String(),
        'p_limit': limit,
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<SaleSummary>(
          (row) => SaleSummary.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  /// Single sale header for the detail screen. Returns null if the
  /// txn id isn't a sale (or is a reversal) in this shop.
  Future<SaleSummary?> getSale({
    required String shopId,
    required String txnId,
  }) async {
    final rows = await _client.rpc(
      'get_sale',
      params: {'p_shop_id': shopId, 'p_txn_id': txnId},
    );
    if (rows is! List || rows.isEmpty) return null;
    return SaleSummary.fromJson(Map<String, dynamic>.from(rows.first));
  }

  Future<List<SaleLineDetail>> getSaleLines({
    required String shopId,
    required String txnId,
  }) async {
    final rows = await _client.rpc(
      'get_sale_lines',
      params: {'p_shop_id': shopId, 'p_txn_id': txnId},
    );
    if (rows is! List) return const [];
    return rows
        .map<SaleLineDetail>(
          (row) => SaleLineDetail.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  /// Reverse a posted sale. Owner-only, ≤7 days, refuses if the
  /// customer has paid down the receivable. Returns the new reversal
  /// txn's id.
  Future<String> voidSale({
    required String shopId,
    required String txnId,
    required String clientOpId,
  }) async {
    final result = await _client.rpc(
      'void_sale',
      params: {
        'p_shop_id': shopId,
        'p_txn_id': txnId,
        'p_client_op_id': clientOpId,
      },
    );
    return result as String;
  }

  /// post_payment — settle a party's outstanding balance. Direction is
  /// 'I' for an inbound payment (customer pays down their receivable)
  /// or 'O' for an outbound payment (shop pays down its payable to a
  /// supplier). The RPC validates the party matches the direction and
  /// that the amount doesn't exceed the outstanding balance.
  Future<String> postPayment({
    required String shopId,
    required String partyId,
    required String direction,
    required num amount,
    required String paymentMethodCode,
    required String clientOpId,
    String? notes,
  }) async {
    final result = await _client.rpc(
      'post_payment',
      params: {
        'p_shop_id': shopId,
        'p_party_id': partyId,
        'p_direction': direction,
        'p_amount': amount,
        'p_payment_method_code': paymentMethodCode,
        'p_client_op_id': clientOpId,
        'p_notes': notes,
      },
    );
    return result as String;
  }

  /// post_receive — supplier-attributed inventory + payable updates.
  /// Always requires a party (the supplier); v1 sends per-unit cost
  /// (`unit_cost`) and skips the alternative `line_total` shape.
  Future<String> postReceive({
    required String shopId,
    required String partyId,
    required List<ReceiveLinePayload> lines,
    required num paidAmount,
    String? paymentMethodCode,
    String? documentId,
    required String clientOpId,
    String? notes,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('post_receive requires at least one line');
    }
    final result = await _client.rpc(
      'post_receive',
      params: {
        'p_shop_id': shopId,
        'p_party_id': partyId,
        'p_lines': lines.map((l) => l.toJson()).toList(),
        'p_paid_amount': paidAmount,
        'p_payment_method_code': paymentMethodCode,
        'p_document_id': documentId,
        'p_client_op_id': clientOpId,
        'p_notes': notes,
      },
    );
    return result as String;
  }

  // ----- Reference / settings -----------------------------------------------

  List<UnitOption>? _unitsCache;
  Future<List<UnitOption>>? _unitsFuture;

  /// Caches the active unit table per session. Used by posting flows that
  /// need a unit_id given a base_unit_code from search_items.
  Future<List<UnitOption>> listUnits() {
    if (_unitsCache != null) return Future.value(_unitsCache);
    return _unitsFuture ??= _fetchUnits();
  }

  Map<String, String>? _currencySymbolsCache;
  Future<Map<String, String>>? _currencySymbolsFuture;

  /// Caches the (currency_code → symbol) map per session. Loaded once
  /// after sign-in so ShopSummary can carry the resolved symbol and the
  /// UI never has to hardcode "$".
  Future<Map<String, String>> currencySymbols() {
    if (_currencySymbolsCache != null) {
      return Future.value(_currencySymbolsCache);
    }
    return _currencySymbolsFuture ??= _fetchCurrencySymbols();
  }

  Future<Map<String, String>> _fetchCurrencySymbols() async {
    final currencies = await listCurrencies();
    final map = {for (final c in currencies) c.code: c.label};
    _currencySymbolsCache = map;
    _currencySymbolsFuture = null;
    return map;
  }

  Future<List<UnitOption>> _fetchUnits() async {
    final rows = await _client
        .from('unit')
        .select('id, code, default_label')
        .eq('is_active', true)
        .order('code');
    final units = rows
        .map<UnitOption>(
          (row) => UnitOption.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
    _unitsCache = units;
    _unitsFuture = null;
    return units;
  }

  Future<List<ReferenceOption>> listLanguages() async {
    final rows = await _client
        .from('language')
        .select('code, name')
        .eq('is_active', true)
        .order('name');
    return rows
        .map<ReferenceOption>(
          (row) => ReferenceOption.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<List<ReferenceOption>> listCurrencies() async {
    final rows = await _client
        .from('currency')
        .select('code, symbol')
        .eq('is_active', true)
        .order('code');
    return rows
        .map<ReferenceOption>(
          (row) => ReferenceOption.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<void> updateShopDefaults({
    required String shopId,
    String? name,
    String? currencyCode,
    String? defaultLanguageCode,
    String? timezone,
  }) async {
    final patch = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) patch['name'] = name.trim();
    if (currencyCode != null) patch['currency_code'] = currencyCode;
    if (defaultLanguageCode != null) {
      patch['default_language_code'] = defaultLanguageCode;
    }
    if (timezone != null && timezone.trim().isNotEmpty) {
      patch['timezone'] = timezone.trim();
    }
    if (patch.isEmpty) return;
    await _client.from('shop').update(patch).eq('id', shopId);
  }

  /// Fetch a single shop row for projecting back into AuthController state
  /// after a successful mutation. Returns null if the row no longer exists
  /// or is no longer accessible to the caller.
  Future<ShopSummary?> fetchShop(String shopId) async {
    final row = await _client
        .from('shop')
        .select(
          'id, name, setup_status, currency_code, default_language_code, timezone',
        )
        .eq('id', shopId)
        .maybeSingle();
    if (row == null) return null;
    final symbols = await currencySymbols();
    return ShopSummary.fromJson(
      Map<String, dynamic>.from(row),
      currencySymbols: symbols,
    );
  }
}
