// Stateless data layer over Supabase RPCs and PostgREST. Holds no UI
// state — AuthController stays the single owner of session, shops,
// selectedShop, etc. Screens read AuthController for state and ShopApi
// for data; after a write that affects shop-level state (e.g.
// applyTemplate, completeSetup, updateShopDefaults), the screen calls
// auth.refreshSelectedShop() to pull the new row.

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/shared/uuid.dart';

/// Bundle returned by `getShopItem` — header + every packaging + every
/// alias + every barcode in a single round trip. The RPC returns one
/// One row from `suggest_item_packagings` — drives the picker list in
/// the Add packaging sheet.
class PackagingSuggestion {
  const PackagingSuggestion({
    required this.unitCode,
    required this.unitLabel,
    required this.conversionToBase,
    required this.uses,
    required this.source,
  });

  factory PackagingSuggestion.fromJson(Map<String, dynamic> json) =>
      PackagingSuggestion(
        unitCode: json['unit_code'] as String,
        unitLabel: json['unit_label'] as String,
        conversionToBase: (json['conversion_to_base'] as num).toDouble(),
        uses: json['uses'] as int,
        source: json['source'] as String,
      );

  final String unitCode;
  final String unitLabel;
  final double conversionToBase;
  final int uses;

  /// `'category'` when same-category items already use this packaging;
  /// `'cross_category'` when it's a fallback from a different category.
  final String source;
}

/// One row from `suggest_category_units` — drives the "How is it sold?"
/// list in the Add new item sheet.
class CategoryUnitSuggestion {
  const CategoryUnitSuggestion({
    required this.unitCode,
    required this.unitLabel,
    required this.uses,
  });

  factory CategoryUnitSuggestion.fromJson(Map<String, dynamic> json) =>
      CategoryUnitSuggestion(
        unitCode: json['unit_code'] as String,
        unitLabel: json['unit_label'] as String,
        uses: json['uses'] as int,
      );

  final String unitCode;
  final String unitLabel;
  final int uses;
}

/// One row in `NewItemOptions.baseUnits` — "sold loose" choice in the
/// grouped picker on the new item sheet (e.g., Kg / Litre / Piece).
class BaseUnitOption {
  const BaseUnitOption({
    required this.unitCode,
    required this.unitLabel,
    required this.uses,
  });

  factory BaseUnitOption.fromJson(Map<String, dynamic> json) => BaseUnitOption(
    unitCode: json['unit_code'] as String,
    unitLabel: json['unit_label'] as String,
    uses: (json['uses'] as num?)?.toInt() ?? 0,
  );

  final String unitCode;
  final String unitLabel;
  final int uses;
}

/// One row in `NewItemOptions.packagedUnits` — "sold in a packaging"
/// choice in the grouped picker (e.g., 25-Kg bag, 12-Bottle carton).
///
/// Carries the implied base unit so the sheet can render labels like
/// "25-kg bag" without making the shopkeeper pick a base unit first.
class PackagedUnitSuggestion {
  const PackagedUnitSuggestion({
    required this.unitCode,
    required this.unitLabel,
    required this.conversionToBase,
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required this.uses,
    required this.source,
  });

  factory PackagedUnitSuggestion.fromJson(Map<String, dynamic> json) =>
      PackagedUnitSuggestion(
        unitCode: json['unit_code'] as String,
        unitLabel: json['unit_label'] as String,
        conversionToBase: (json['conversion_to_base'] as num).toDouble(),
        baseUnitCode: json['base_unit_code'] as String,
        baseUnitLabel: json['base_unit_label'] as String,
        uses: (json['uses'] as num?)?.toInt() ?? 0,
        source: json['source'] as String,
      );

  final String unitCode;
  final String unitLabel;
  final double conversionToBase;
  final String baseUnitCode;
  final String baseUnitLabel;
  final int uses;

  /// 'category' | 'cross_category'.
  final String source;
}

/// Aggregate returned by `suggest_new_item_options` — populates the
/// "How is it sold?" grouped picker on the Add new item sheet.
class NewItemOptions {
  const NewItemOptions({
    required this.baseUnits,
    required this.packagedUnits,
  });

  factory NewItemOptions.fromJson(Map<String, dynamic> json) => NewItemOptions(
    baseUnits: (json['base_units'] as List? ?? const [])
        .map((row) => BaseUnitOption.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false),
    packagedUnits: (json['packaged_units'] as List? ?? const [])
        .map(
          (row) => PackagedUnitSuggestion.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false),
  );

  final List<BaseUnitOption> baseUnits;
  final List<PackagedUnitSuggestion> packagedUnits;
}

/// Result of the extended `create_shop_item` RPC — the row id plus the
/// default packaging id the caller should use for the next cart line.
typedef CreateShopItemResult = ({
  String shopItemId,
  String defaultShopItemUnitId,
});

/// jsonb object with four sections; we parse it here so callers get
/// typed lists.
class ShopItemDetail {
  const ShopItemDetail({
    required this.header,
    required this.units,
    required this.aliases,
    required this.barcodes,
  });

  final ShopItemSummary header;
  final List<ShopItemUnitDetail> units;
  final List<ShopItemAliasRow> aliases;
  final List<ShopItemBarcodeRow> barcodes;
}

/// Row in `ShopItemDetail.aliases`. Mirrors `shop_item_alias` — both
/// display-name rows and search-only rows are returned (the editor
/// renders them in two sections).
class ShopItemAliasRow {
  const ShopItemAliasRow({
    required this.aliasId,
    required this.aliasText,
    required this.languageCode,
    required this.isDisplay,
  });

  factory ShopItemAliasRow.fromJson(Map<String, dynamic> json) =>
      ShopItemAliasRow(
        // `alias_id` is the 0044 addition; older DTO callers passed
        // nothing and we tolerate it as empty string to keep tests
        // that build the row in code working without churn.
        aliasId: (json['alias_id'] as String?) ?? '',
        aliasText: json['alias_text'] as String,
        languageCode: json['language_code'] as String?,
        isDisplay: json['is_display'] as bool,
      );

  final String aliasId;
  final String aliasText;
  final String? languageCode;
  final bool isDisplay;
}

/// Row in `ShopItemDetail.barcodes`. Packaging-scoped on the server,
/// but the editor groups by barcode so we surface barcode + is_primary.
class ShopItemBarcodeRow {
  const ShopItemBarcodeRow({
    required this.barcodeId,
    required this.shopItemUnitId,
    required this.barcode,
    required this.isPrimary,
  });

  factory ShopItemBarcodeRow.fromJson(Map<String, dynamic> json) =>
      ShopItemBarcodeRow(
        // 0044 fields; default to empty for older callers.
        barcodeId: (json['barcode_id'] as String?) ?? '',
        shopItemUnitId: (json['shop_item_unit_id'] as String?) ?? '',
        barcode: json['barcode'] as String,
        isPrimary: json['is_primary'] as bool,
      );

  final String barcodeId;

  /// Which packaging this barcode belongs to. Drives chip placement
  /// (the chip renders inside the matching packaging row).
  final String shopItemUnitId;
  final String barcode;
  final bool isPrimary;
}

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

  /// One-shot dismissal of the optional item-onboarding step (the
  /// post-setup "set up your products" screen). Idempotent on the
  /// server — calling twice leaves the original timestamp.
  Future<void> dismissOnboarding({required String shopId}) async {
    await _client
        .rpc('dismiss_shop_onboarding', params: {'p_shop_id': shopId});
  }

  /// Returns the caller's effective capability codes for [shopId].
  /// Backed by the auth_user_shop_capabilities RPC (migration 0048).
  /// Empty list when the caller isn't a member.
  Future<List<String>> listUserShopCapabilities({
    required String shopId,
  }) async {
    final raw = await _client.rpc(
      'auth_user_shop_capabilities',
      params: {'p_shop_id': shopId},
    );
    if (raw is List) {
      return raw.whereType<String>().toList(growable: false);
    }
    return const <String>[];
  }

  /// Latest audit entries for a specific entity. Used by the mobile
  /// inline cues on Product detail (`shop_item_unit`) and Party
  /// detail (`party`). Empty list when nothing's been logged for
  /// that entity yet — the caller should render no cue in that case.
  Future<List<AuditEntry>> listAuditEntriesForEntity({
    required String shopId,
    required String entityType,
    required String entityId,
    int limit = 5,
  }) async {
    final raw = await _client.rpc(
      'list_audit_entries_for_entity',
      params: {
        'p_shop_id': shopId,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_limit': limit,
      },
    );
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((row) => AuditEntry.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    }
    return const <AuditEntry>[];
  }

  // ----- Catalog / items ----------------------------------------------------

  /// Idempotent activation of a global catalog item for this shop.
  /// Returns the (existing or newly created) `shop_item_id`. Required
  /// before search-result tiles whose `isActivated` is false can be
  /// added to a cart.
  Future<String> ensureShopItem({
    required String shopId,
    required String itemId,
  }) async {
    final result = await _client.rpc(
      'ensure_shop_item',
      params: {'p_shop_id': shopId, 'p_item_id': itemId},
    );
    return result as String;
  }

  /// Shop-local item creation ("+ Add new item" sheet). Atomic 1-or-2
  /// packaging insert — pass `soldUnitCode` + `soldConversion` when the
  /// shopkeeper picked a packaging (e.g., "25-Kg bag"), leave them null
  /// for sold-in-base ("loose by kg"). `defaultSide` controls how the
  /// initial default flags land: `'sale'` makes the sold row the sale
  /// default (base row stays receive-default); `'receive'` mirrors it.
  /// Returns the new shop_item id plus the packaging id the caller
  /// should attach to the cart line.
  Future<CreateShopItemResult> createShopItem({
    required String shopId,
    required String name,
    required String languageCode,
    required String baseUnitCode,
    num? salePrice,
    String? categoryId,
    String? soldUnitCode,
    num? soldConversion,
    String defaultSide = 'sale',
  }) async {
    final result = await _client.rpc(
      'create_shop_item',
      params: {
        'p_shop_id': shopId,
        'p_name': name,
        'p_language_code': languageCode,
        'p_base_unit_code': baseUnitCode,
        'p_sale_price': salePrice,
        'p_category_id': categoryId,
        'p_sold_unit_code': soldUnitCode,
        'p_sold_conversion': soldConversion,
        'p_default_side': defaultSide,
      },
    );
    final row = (result is List && result.isNotEmpty)
        ? Map<String, dynamic>.from(result.first as Map)
        : Map<String, dynamic>.from(result as Map);
    return (
      shopItemId: row['shop_item_id'] as String,
      defaultShopItemUnitId: row['default_shop_item_unit_id'] as String,
    );
  }

  /// Adds a non-base packaging to an existing shop_item ("+ Add
  /// packaging" entry in the unit picker). Returns the new
  /// `shop_item_unit_id`.
  Future<String> createShopItemUnit({
    required String shopId,
    required String shopItemId,
    required String unitCode,
    required num conversionToBase,
    num? salePrice,
  }) async {
    final result = await _client.rpc(
      'create_shop_item_unit',
      params: {
        'p_shop_id': shopId,
        'p_shop_item_id': shopItemId,
        'p_unit_code': unitCode,
        'p_conversion_to_base': conversionToBase,
        'p_sale_price': salePrice,
      },
    );
    return result as String;
  }

  /// Inserts (or upserts on alias_text_norm) a display or search alias
  /// for a shop_item. Used by OCR feedback + cashier rename. When
  /// `isDisplay` is true the server flips any prior display alias in
  /// the same language off first.
  Future<String> addShopItemAlias({
    required String shopId,
    required String shopItemId,
    required String aliasText,
    String? languageCode,
    bool isDisplay = false,
    String source = 'manual',
  }) async {
    final result = await _client.rpc(
      'add_shop_item_alias',
      params: {
        'p_shop_id': shopId,
        'p_shop_item_id': shopItemId,
        'p_alias_text': aliasText,
        'p_language_code': languageCode,
        'p_is_display': isDisplay,
        'p_source': source,
      },
    );
    return result as String;
  }

  /// Lists every packaging on a shop_item. Returns `ReceiveUnitOption`
  /// rows; the screen arg ('sale' vs 'receive') resolves which default
  /// flag the DTO surfaces as `isDefault`. Both Sale and Receive unit
  /// pickers consume the same data.
  Future<List<ReceiveUnitOption>> listShopItemUnits({
    required String shopId,
    required String shopItemId,
    String screen = 'sale',
  }) async {
    final rows = await _client.rpc(
      'list_shop_item_units',
      params: {
        'p_shop_id': shopId,
        'p_shop_item_id': shopItemId,
        'p_screen': screen,
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<ReceiveUnitOption>(
          (row) => ReceiveUnitOption.fromJson(
            Map<String, dynamic>.from(row),
            screen: screen,
          ),
        )
        .toList(growable: false);
  }

  /// Persists `sale_price` on a packaging. Called by the Sale SAVE
  /// flow after a successful post_sale for every line whose unit price
  /// came out of the line editor — future taps on that tile fast-add
  /// at the entered price instead of re-prompting. Pass null to
  /// "un-price" (forces the priceRequired editor on next use).
  Future<void> setShopItemUnitSalePrice({
    required String shopId,
    required String shopItemUnitId,
    required num? salePrice,
  }) async {
    await _client.rpc(
      'set_shop_item_unit_sale_price',
      params: {
        'p_shop_id': shopId,
        'p_shop_item_unit_id': shopItemUnitId,
        'p_sale_price': salePrice,
      },
    );
  }

  /// Picker source for the Add packaging sheet. Returns common
  /// packagings other items in the catalog already use, ranked by
  /// frequency, with same-category matches first. Packagings already on
  /// the current shop_item are excluded server-side so the picker never
  /// shows a duplicate of what the cashier just added.
  Future<List<PackagingSuggestion>> suggestItemPackagings({
    required String shopId,
    required String shopItemId,
    required String baseUnitCode,
    String? categoryId,
    String? locale,
    int limit = 8,
  }) async {
    final rows = await _client.rpc(
      'suggest_item_packagings',
      params: {
        'p_shop_id': shopId,
        'p_shop_item_id': shopItemId,
        'p_base_unit_code': baseUnitCode,
        'p_category_id': categoryId,
        if (locale != null) 'p_locale': locale, // ignore: use_null_aware_elements
        'p_limit': limit,
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<PackagingSuggestion>(
          (row) => PackagingSuggestion.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
  }

  /// Picker source for "How is it sold?" in the Add new item sheet.
  /// Returns base-unit candidates ranked by how many items in the
  /// given category use each as their base.
  Future<List<CategoryUnitSuggestion>> suggestCategoryUnits({
    required String categoryId,
    String? locale,
    int limit = 5,
  }) async {
    final rows = await _client.rpc(
      'suggest_category_units',
      params: {
        'p_category_id': categoryId,
        if (locale != null) 'p_locale': locale, // ignore: use_null_aware_elements
        'p_limit': limit,
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<CategoryUnitSuggestion>(
          (row) => CategoryUnitSuggestion.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
  }

  /// Single-round-trip source for the Add new item grouped picker.
  /// Returns base-unit candidates ("sold loose by X") and packaged-unit
  /// candidates ("sold as 25-kg bag") together — each packaged row
  /// carries the implied base unit so the sheet doesn't need a separate
  /// base-unit step before showing packaged suggestions.
  Future<NewItemOptions> fetchNewItemOptions({
    String? categoryId,
    String? locale,
  }) async {
    final result = await _client.rpc(
      'suggest_new_item_options',
      params: {
        'p_category_id': categoryId,
        if (locale != null) 'p_locale': locale, // ignore: use_null_aware_elements
      },
    );
    if (result == null) {
      return const NewItemOptions(baseUnits: [], packagedUnits: []);
    }
    return NewItemOptions.fromJson(Map<String, dynamic>.from(result as Map));
  }

  /// Lists shop_items for the Products screen. Optional filters:
  /// `categoryId` (exact match) and `query` (prefix on any active
  /// alias). Ordered by display_name. Not cached — items change when
  /// the cashier adds a new one mid-sale.
  Future<List<ShopItemSummary>> listShopItems({
    required String shopId,
    String? categoryId,
    String? query,
    String? locale,
  }) async {
    final rows = await _client.rpc(
      'list_shop_items',
      params: {
        'p_shop_id': shopId,
        'p_category_id': categoryId,
        'p_query': query,
        if (locale != null) 'p_locale': locale, // ignore: use_null_aware_elements
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<ShopItemSummary>(
          (row) => ShopItemSummary.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  /// Single-round-trip detail fetch for the Products editor: header +
  /// every packaging (with both default flags raw) + every alias + every
  /// barcode. Server aggregates into one jsonb object; we split it
  /// client-side into typed lists.
  Future<ShopItemDetail> getShopItem({
    required String shopId,
    required String shopItemId,
    String? locale,
  }) async {
    final result = await _client.rpc(
      'get_shop_item',
      params: {
        'p_shop_id': shopId,
        'p_shop_item_id': shopItemId,
        if (locale != null) 'p_locale': locale, // ignore: use_null_aware_elements
      },
    );
    final json = Map<String, dynamic>.from(result as Map);
    final unitsRaw = (json['units'] as List?) ?? const [];
    final aliasesRaw = (json['aliases'] as List?) ?? const [];
    final barcodesRaw = (json['barcodes'] as List?) ?? const [];
    return ShopItemDetail(
      header: ShopItemSummary.fromJson(
        Map<String, dynamic>.from(json['header'] as Map),
      ),
      units: unitsRaw
          .map<ShopItemUnitDetail>(
            (row) => ShopItemUnitDetail.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false),
      aliases: aliasesRaw
          .map<ShopItemAliasRow>(
            (row) => ShopItemAliasRow.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false),
      barcodes: barcodesRaw
          .map<ShopItemBarcodeRow>(
            (row) => ShopItemBarcodeRow.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Consolidated item picker. Single canonical entry point for Sale,
  /// Receive, and Products search. `screen` controls which default
  /// packaging flag the row carries; `partyId` (Receive only) prefers
  /// supplier-scoped last cost. Rows map to `ItemSearchResult` shape.
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

  /// Owner-only rename / phone-update of an existing party. Type is
  /// not mutable in v1.
  Future<void> updateParty({
    required String shopId,
    required String partyId,
    required String name,
    String? phone,
  }) async {
    await _client.rpc(
      'update_party',
      params: {
        'p_shop_id': shopId,
        'p_party_id': partyId,
        'p_name': name,
        'p_phone': phone,
      },
    );
  }

  /// Records an opening balance for a party — direction 'I' (customer
  /// owes us, bumps receivable) or 'O' (we owe supplier, bumps
  /// payable). Inserts a no-line sale/receive txn so reports stay
  /// coherent; idempotent on `clientOpId`.
  Future<String> postOpeningPartyBalance({
    required String shopId,
    required String partyId,
    required num amount,
    required String direction,
    String? clientOpId,
    String? notes,
  }) async {
    final result = await _client.rpc(
      'post_opening_party_balance',
      params: {
        'p_shop_id': shopId,
        'p_party_id': partyId,
        'p_amount': amount,
        'p_direction': direction,
        'p_client_op_id': clientOpId,
        'p_notes': notes,
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

  /// Posts a sale. Each line identifies its packaging via
  /// `shop_item_unit_id`; the server derives shop_item, base unit, and
  /// COGS snapshot from there. `clientOpId` deduplicates retries.
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
  /// Single-round-trip dashboard tile: sales-today, total receivables
  /// + payables, low-stock count.
  Future<TodaySummary> getTodaySummary({
    required String shopId,
    String? locale,
  }) async {
    final result = await _client.rpc(
      'get_today_summary',
      params: {
        'p_shop_id': shopId,
        if (locale != null) 'p_locale': locale, // ignore: use_null_aware_elements
      },
    );
    return TodaySummary.fromJson(Map<String, dynamic>.from(result as Map));
  }

  /// Receivables list — parties who owe the shop (`receivable > 0`).
  /// Caller maps each row's `amount` into the right meaning (receivable
  /// vs payable) before rendering.
  Future<List<PartyBalanceRow>> listReceivables({
    required String shopId,
    String? locale,
  }) async {
    final rows = await _client.rpc(
      'list_receivables',
      params: {
        'p_shop_id': shopId,
        if (locale != null) 'p_locale': locale, // ignore: use_null_aware_elements
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<PartyBalanceRow>((row) {
          final map = Map<String, dynamic>.from(row as Map);
          return PartyBalanceRow.fromJson({
            ...map,
            'amount': map['receivable'],
          });
        })
        .toList(growable: false);
  }

  Future<List<PartyBalanceRow>> listPayables({
    required String shopId,
    String? locale,
  }) async {
    final rows = await _client.rpc(
      'list_payables',
      params: {
        'p_shop_id': shopId,
        if (locale != null) 'p_locale': locale, // ignore: use_null_aware_elements
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<PartyBalanceRow>((row) {
          final map = Map<String, dynamic>.from(row as Map);
          return PartyBalanceRow.fromJson({
            ...map,
            'amount': map['payable'],
          });
        })
        .toList(growable: false);
  }

  Future<List<LowStockRow>> listLowStock({
    required String shopId,
    String? locale,
  }) async {
    final rows = await _client.rpc(
      'list_low_stock',
      params: {
        'p_shop_id': shopId,
        if (locale != null) 'p_locale': locale, // ignore: use_null_aware_elements
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<LowStockRow>(
          (row) => LowStockRow.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  /// Loads the Party detail bundle (header + last-N sales/receives/
  /// payments) for the Party detail screen.
  Future<PartyDetail> getPartyDetail({
    required String shopId,
    required String partyId,
    int limit = 20,
  }) async {
    final result = await _client.rpc(
      'get_party_detail',
      params: {
        'p_shop_id': shopId,
        'p_party_id': partyId,
        'p_limit': limit,
      },
    );
    return PartyDetail.fromJson(Map<String, dynamic>.from(result as Map));
  }

  /// Catalog top-level categories for the Add new item + editor
  /// dropdowns. Locale-resolved server-side; the UI just renders
  /// `name`.
  Future<List<CategoryOption>> listCategories({String? locale}) async {
    final rows = await _client.rpc(
      'list_categories',
      params: {
        if (locale != null) 'p_locale': locale, // ignore: use_null_aware_elements
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<CategoryOption>(
          (row) => CategoryOption.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

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
  /// previous page to fetch older rows. `dateFrom` / `dateTo` clamp to
  /// a date window (server-side); `partyId` narrows to one customer.
  /// "Include voided" is enforced client-side by inspecting
  /// `isVoided` on the returned rows.
  Future<List<SaleSummary>> listSales({
    required String shopId,
    DateTime? before,
    int limit = 50,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? partyId,
  }) async {
    final rows = await _client.rpc(
      'list_sales',
      params: {
        'p_shop_id': shopId,
        'p_before': before?.toIso8601String(),
        'p_limit': limit,
        'p_date_from': dateFrom?.toIso8601String(),
        'p_date_to': dateTo?.toIso8601String(),
        'p_party_id': partyId,
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

  /// Sale lines for the detail receipt. Rows include
  /// `shop_item_unit_id` (the snapshot packaging) and `packaging_label`
  /// derived from the snapshot fields so the receipt stays consistent
  /// even after later packaging edits.
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
  ///
  /// `refundAmount` (optional) atomically records an outbound payment
  /// to the customer for cash already paid at the till. Must be > 0
  /// and ≤ the sale's `paid_amount`. Null = no refund.
  Future<String> voidSale({
    required String shopId,
    required String txnId,
    required String clientOpId,
    num? refundAmount,
  }) async {
    final result = await _client.rpc(
      'void_sale',
      params: {
        'p_shop_id': shopId,
        'p_txn_id': txnId,
        'p_client_op_id': clientOpId,
        'p_refund_amount': refundAmount,
      },
    );
    return result as String;
  }

  /// Receive-side mirror of listSales. Same row shape and filter params.
  Future<List<ReceiveSummary>> listReceives({
    required String shopId,
    DateTime? before,
    int limit = 50,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? partyId,
  }) async {
    final rows = await _client.rpc(
      'list_receives',
      params: {
        'p_shop_id': shopId,
        'p_before': before?.toIso8601String(),
        'p_limit': limit,
        'p_date_from': dateFrom?.toIso8601String(),
        'p_date_to': dateTo?.toIso8601String(),
        'p_party_id': partyId,
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<ReceiveSummary>(
          (row) => ReceiveSummary.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  /// Full party directory for the Parties screen. Same row shape as
  /// `search_parties` (reuse `PartySearchResult`); supports "all"
  /// type and a `hasBalanceOnly` toggle for the Parties screen filter.
  Future<List<PartySearchResult>> listParties({
    required String shopId,
    String query = '',
    String? type,
    bool hasBalanceOnly = false,
    int limit = 200,
  }) async {
    final rows = await _client.rpc(
      'list_parties',
      params: {
        'p_shop_id': shopId,
        'p_query': query,
        'p_type': type,
        'p_has_balance_only': hasBalanceOnly,
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

  /// Payment history — paginated. Direction 'I' = inbound (customer
  /// paid us), 'O' = outbound (we paid a supplier); null = both.
  Future<List<PaymentSummary>> listPayments({
    required String shopId,
    DateTime? before,
    int limit = 50,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? partyId,
    String? direction,
  }) async {
    final rows = await _client.rpc(
      'list_payments',
      params: {
        'p_shop_id': shopId,
        'p_before': before?.toIso8601String(),
        'p_limit': limit,
        'p_date_from': dateFrom?.toIso8601String(),
        'p_date_to': dateTo?.toIso8601String(),
        'p_party_id': partyId,
        'p_direction': direction,
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<PaymentSummary>(
          (row) => PaymentSummary.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  /// Expense-side mirror — paginated history with date + category
  /// filters. Category name is locale-resolved server-side.
  Future<List<ExpenseSummary>> listExpenses({
    required String shopId,
    DateTime? before,
    int limit = 50,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? categoryId,
    String? locale,
  }) async {
    final rows = await _client.rpc(
      'list_expenses',
      params: {
        'p_shop_id': shopId,
        'p_before': before?.toIso8601String(),
        'p_limit': limit,
        'p_date_from': dateFrom?.toIso8601String(),
        'p_date_to': dateTo?.toIso8601String(),
        'p_category_id': categoryId,
        if (locale != null) 'p_locale': locale, // ignore: use_null_aware_elements
      },
    );
    if (rows is! List) return const [];
    return rows
        .map<ExpenseSummary>(
          (row) => ExpenseSummary.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<ReceiveSummary?> getReceive({
    required String shopId,
    required String txnId,
  }) async {
    final rows = await _client.rpc(
      'get_receive',
      params: {'p_shop_id': shopId, 'p_txn_id': txnId},
    );
    if (rows is! List || rows.isEmpty) return null;
    return ReceiveSummary.fromJson(Map<String, dynamic>.from(rows.first));
  }

  /// Receive lines for the detail bono. Same `shop_item_unit_id` +
  /// `packaging_label` snapshot fields as `getSaleLines`.
  Future<List<ReceiveLineDetail>> getReceiveLines({
    required String shopId,
    required String txnId,
  }) async {
    final rows = await _client.rpc(
      'get_receive_lines',
      params: {'p_shop_id': shopId, 'p_txn_id': txnId},
    );
    if (rows is! List) return const [];
    return rows
        .map<ReceiveLineDetail>(
          (row) => ReceiveLineDetail.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  /// Reverse a posted receive (same-shift, owner-only, refuses when
  /// later stock activity exists for any item on the bono). Tighter
  /// scope than voidSale: no refund parameter (v1 receives are all
  /// credit) and a 24-hour window.
  Future<String> voidReceive({
    required String shopId,
    required String txnId,
    required String clientOpId,
  }) async {
    final result = await _client.rpc(
      'void_receive',
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
  /// Always requires a party (the supplier). Each line carries the
  /// packaging (`shop_item_unit_id`) plus the cashier-typed `lineTotal`
  /// so the bono total matches the paper exactly; the server derives
  /// per-unit cost from `line_total / quantity`.
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

  /// Persists the per-item low-stock warning threshold (in base units).
  /// Pass null to clear — the warning then falls back to the shop-wide
  /// "below 1" rule. Cashier or owner can call this.
  Future<void> setShopItemReorderThreshold({
    required String shopId,
    required String shopItemId,
    required num? reorderThreshold,
  }) async {
    await _client.rpc(
      'set_shop_item_reorder_threshold',
      params: {
        'p_shop_id': shopId,
        'p_shop_item_id': shopItemId,
        'p_reorder_threshold': reorderThreshold,
      },
    );
  }

  /// Uploads the picked bono bytes to the `shop-documents` bucket and
  /// inserts a `document` row of type `bono`. Returns the new
  /// document_id, which Receive SAVE then passes to `post_receive` as
  /// `p_document_id`. Storage path is `{shop_id}/bono/{uuid}.{ext}`.
  Future<String> uploadBonoImage({
    required String shopId,
    required Uint8List bytes,
    required String mimeType,
    required String fileExtension,
  }) async {
    // Path shape is fixed by the `document_storage_path_shape` check
    // in 0008: `{shop_id}/documents/{document_id}/image.{ext}`. We mint
    // the document UUID client-side so the path can be built before
    // upload, then pass that same id into the RPC.
    final documentId = uuidV4();
    final path = '$shopId/documents/$documentId/image.$fileExtension';
    await _client.storage.from('shop-documents').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    final result = await _client.rpc(
      'create_bono_document',
      params: {
        'p_shop_id': shopId,
        'p_document_id': documentId,
        'p_storage_path': path,
        'p_mime_type': mimeType,
        'p_size_bytes': bytes.length,
      },
    );
    return result as String;
  }

  /// Flip the per-screen default flags on a packaging row. Setting a
  /// flag to true atomically unsets the previous holder in the same
  /// shop_item (one default per side). Setting both false leaves the
  /// shop_item with no default — the picker falls back to base.
  Future<void> setShopItemUnitDefaultFlags({
    required String shopId,
    required String shopItemUnitId,
    required bool isDefaultSale,
    required bool isDefaultReceive,
  }) async {
    await _client.rpc(
      'set_shop_item_unit_default_flags',
      params: {
        'p_shop_id': shopId,
        'p_shop_item_unit_id': shopItemUnitId,
        'p_is_default_sale': isDefaultSale,
        'p_is_default_receive': isDefaultReceive,
      },
    );
  }

  /// Owner-only. Sets (or clears, when [categoryId] is null) the
  /// category on an existing shop_item. Backed by the
  /// `set_shop_item_category` RPC introduced in 0038.
  Future<void> setShopItemCategory({
    required String shopId,
    required String shopItemId,
    required String? categoryId,
  }) async {
    await _client.rpc(
      'set_shop_item_category',
      params: {
        'p_shop_id': shopId,
        'p_shop_item_id': shopItemId,
        'p_category_id': categoryId,
      },
    );
  }

  /// Owner-only. Soft-removes a non-base packaging — flips is_active
  /// to false and clears any default-sale/receive flags. Refuses on
  /// the base packaging. Idempotent.
  Future<void> deactivateShopItemUnit({
    required String shopId,
    required String shopItemUnitId,
  }) async {
    await _client.rpc(
      'deactivate_shop_item_unit',
      params: {
        'p_shop_id': shopId,
        'p_shop_item_unit_id': shopItemUnitId,
      },
    );
  }

  /// Removes a non-display alias from a shop_item. Refuses to remove
  /// the active display alias (the user must add a replacement first).
  Future<void> removeShopItemAlias({
    required String shopId,
    required String aliasId,
  }) async {
    await _client.rpc(
      'remove_shop_item_alias',
      params: {
        'p_shop_id': shopId,
        'p_alias_id': aliasId,
      },
    );
  }

  /// Adds a barcode to a packaging. `isPrimary: true` atomically
  /// demotes any previous primary in the same packaging. Returns the
  /// barcode row id.
  Future<String> addShopItemBarcode({
    required String shopId,
    required String shopItemUnitId,
    required String barcode,
    bool isPrimary = false,
    String? symbology,
  }) async {
    final result = await _client.rpc(
      'add_shop_item_barcode',
      params: {
        'p_shop_id': shopId,
        'p_shop_item_unit_id': shopItemUnitId,
        'p_barcode': barcode,
        'p_is_primary': isPrimary,
        'p_symbology': symbology,
      },
    );
    return result as String;
  }

  Future<void> removeShopItemBarcode({
    required String shopId,
    required String barcodeId,
  }) async {
    await _client.rpc(
      'remove_shop_item_barcode',
      params: {
        'p_shop_id': shopId,
        'p_barcode_id': barcodeId,
      },
    );
  }

  /// Promotes one barcode to primary, atomically demoting whichever
  /// barcode was previously primary on the same packaging.
  Future<void> setPrimaryShopItemBarcode({
    required String shopId,
    required String barcodeId,
  }) async {
    await _client.rpc(
      'set_primary_shop_item_barcode',
      params: {
        'p_shop_id': shopId,
        'p_barcode_id': barcodeId,
      },
    );
  }

  /// Top movers report — aggregates sales over the last
  /// [periodDays] and returns the busiest products + dead stock in
  /// one round trip. Server caps each segment at [limit].
  Future<ProductVelocity> listProductVelocity({
    required String shopId,
    int periodDays = 7,
    int limit = 10,
    String? locale,
  }) async {
    final result = await _client.rpc(
      'list_product_velocity',
      params: {
        'p_shop_id': shopId,
        'p_period_days': periodDays,
        'p_limit': limit,
        if (locale != null) 'p_locale': locale, // ignore: use_null_aware_elements
      },
    );
    final map = Map<String, dynamic>.from(result as Map);
    final topRaw = (map['top'] as List?) ?? const [];
    final deadRaw = (map['dead'] as List?) ?? const [];
    return ProductVelocity(
      top: topRaw
          .map<TopMoverRow>(
            (row) => TopMoverRow.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false),
      dead: deadRaw
          .map<DeadStockRow>(
            (row) => DeadStockRow.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false),
    );
  }

  /// Owner-only stock adjustment. Single-line shape sufficient for
  /// the product-detail "Adjust stock" sheet (opening / correction /
  /// spoilage). `unitCost` is required by the server when reason
  /// increases stock and no prior stock exists; for everyday
  /// "set/add/subtract" corrections we pass null and let the server's
  /// avg-cost logic carry forward.
  Future<String> postInventoryAdjustment({
    required String shopId,
    required String reasonCode,
    required String shopItemId,
    required num quantityDelta,
    num? unitCost,
    String? clientOpId,
    String? notes,
  }) async {
    final result = await _client.rpc(
      'post_inventory_adjustment',
      params: {
        'p_shop_id': shopId,
        'p_reason_code': reasonCode,
        'p_lines': [
          {
            'shop_item_id': shopItemId,
            'quantity_delta': quantityDelta,
            if (unitCost != null) 'unit_cost': unitCost, // ignore: use_null_aware_elements
          }
        ],
        'p_client_op_id': clientOpId,
        'p_notes': notes,
      },
    );
    return result as String;
  }

  /// Fetch a single shop row for projecting back into AuthController state
  /// after a successful mutation. Returns null if the row no longer exists
  /// or is no longer accessible to the caller.
  Future<ShopSummary?> fetchShop(String shopId) async {
    final row = await _client
        .from('shop')
        .select(
          'id, name, setup_status, currency_code, default_language_code, timezone, onboarding_dismissed_at',
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
