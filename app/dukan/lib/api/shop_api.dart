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
