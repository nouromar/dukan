// Cross-feature DTOs shared between AuthController (state) and ShopApi
// (data). Kept in one place so neither layer "owns" them and consumers
// (screens, tests, fixtures) import from a single canonical path.

class ShopSummary {
  const ShopSummary({
    required this.id,
    required this.name,
    required this.setupStatus,
    required this.currencyCode,
    required this.currencySymbol,
    required this.defaultLanguageCode,
    required this.timezone,
  });

  /// Pass the currency symbols map (code → symbol) you loaded once from
  /// ShopApi.currencySymbols(). Falls back to the code itself if the
  /// shop's currency isn't in the map — keeps the constructor total
  /// without forcing the caller to handle missing-symbol exceptions.
  factory ShopSummary.fromJson(
    Map<String, dynamic> json, {
    Map<String, String> currencySymbols = const {},
  }) {
    final code = json['currency_code'] as String;
    return ShopSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      setupStatus: json['setup_status'] as String,
      currencyCode: code,
      currencySymbol: currencySymbols[code] ?? code,
      defaultLanguageCode: json['default_language_code'] as String,
      timezone: json['timezone'] as String,
    );
  }

  final String id;
  final String name;
  final String setupStatus;
  final String currencyCode;
  /// Resolved display symbol for `currencyCode` from the currency ref
  /// table (e.g., USD → $, SLSH → SLSH). Used everywhere the UI prints
  /// a monetary value so we never hardcode "$" outside this projection.
  final String currencySymbol;
  final String defaultLanguageCode;
  final String timezone;

  bool get isReady => setupStatus == 'ready';
  bool get isTemplateApplied =>
      setupStatus == 'template_applied' || setupStatus == 'opening_stock_done';
}

class TemplateOption {
  const TemplateOption({
    required this.id,
    required this.code,
    required this.name,
  });

  factory TemplateOption.fromJson(Map<String, dynamic> json) => TemplateOption(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
  );

  final String id;
  final String code;
  final String name;
}

class ItemSearchResult {
  const ItemSearchResult({
    required this.itemId,
    required this.catalogItemId,
    required this.name,
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required this.receiveUnitCode,
    required this.receiveUnitLabel,
    required this.salePrice,
    required this.lastCost,
    required this.currentStock,
    required this.isActivated,
  });

  factory ItemSearchResult.fromJson(Map<String, dynamic> json) {
    return ItemSearchResult(
      itemId: json['item_id'] as String?,
      catalogItemId: json['catalog_item_id'] as String?,
      name: json['name'] as String,
      baseUnitCode: json['base_unit_code'] as String,
      baseUnitLabel: json['base_unit_label'] as String,
      receiveUnitCode: json['receive_unit_code'] as String,
      receiveUnitLabel: json['receive_unit_label'] as String,
      salePrice: (json['sale_price'] as num?)?.toDouble(),
      lastCost: (json['last_cost'] as num?)?.toDouble(),
      currentStock: (json['current_stock'] as num?)?.toDouble(),
      isActivated: json['is_activated'] as bool,
    );
  }

  final String? itemId;
  final String? catalogItemId;
  final String name;
  final String baseUnitCode;
  final String baseUnitLabel;
  /// The unit the supplier delivers in (e.g., "bag" for a 25kg bag of
  /// rice whose base_unit is "kg"). Drives the Receive line form's unit
  /// display and the unit_id passed to post_receive — passing the base
  /// unit's id would cause stock to be recorded in base units.
  final String receiveUnitCode;
  final String receiveUnitLabel;
  final double? salePrice;
  /// Supplier-specific last unit cost (per receive unit). Populated only
  /// when the search was called with a party_id on the Receive screen.
  final double? lastCost;
  final double? currentStock;
  final bool isActivated;
}

class PartySearchResult {
  const PartySearchResult({
    required this.id,
    required this.name,
    required this.phone,
    required this.typeCode,
    required this.receivable,
    required this.payable,
  });

  factory PartySearchResult.fromJson(Map<String, dynamic> json) =>
      PartySearchResult(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        typeCode: json['type_code'] as String,
        receivable: (json['receivable'] as num?)?.toDouble() ?? 0,
        payable: (json['payable'] as num?)?.toDouble() ?? 0,
      );

  final String id;
  final String name;
  final String? phone;
  final String typeCode;
  final double receivable;
  final double payable;
}

class SaleLine {
  const SaleLine({
    required this.itemId,
    required this.quantity,
    required this.unitId,
    required this.unitPrice,
  });

  final String itemId;
  final num quantity;
  final String unitId;
  final num unitPrice;

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'quantity': quantity,
    'unit_id': unitId,
    'unit_price': unitPrice,
  };
}

/// post_receive line payload. v1 sends `line_total` (not `unit_cost`)
/// because the cashier types what's on the bono — usually a line total
/// like "5 bags rice $120" — and we want the stored bono total to match
/// the paper exactly. The RPC computes the per-unit cost from
/// line_total/qty and stores it on transaction_line.unit_amount.
class ReceiveLinePayload {
  const ReceiveLinePayload({
    required this.itemId,
    required this.quantity,
    required this.unitId,
    required this.lineTotal,
  });

  final String itemId;
  final num quantity;
  final String unitId;
  final num lineTotal;

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'quantity': quantity,
    'unit_id': unitId,
    'line_total': lineTotal,
  };
}

class ExpenseCategoryOption {
  const ExpenseCategoryOption({
    required this.id,
    required this.code,
    required this.name,
  });

  /// Build an option with the locale-appropriate name resolved from
  /// the `name_translations` jsonb (`{"en": ..., "so": ...}`), falling
  /// back to the canonical `name` column.
  factory ExpenseCategoryOption.fromJson(
    Map<String, dynamic> json, {
    String? locale,
  }) {
    final translations = json['name_translations'];
    String? translated;
    if (translations is Map && locale != null) {
      final value = translations[locale];
      if (value is String && value.trim().isNotEmpty) {
        translated = value;
      }
    }
    return ExpenseCategoryOption(
      id: json['id'] as String,
      code: json['code'] as String,
      name: translated ?? json['name'] as String,
    );
  }

  final String id;
  final String code;
  final String name;
}

class ReferenceOption {
  const ReferenceOption({required this.code, required this.label});

  factory ReferenceOption.fromJson(Map<String, dynamic> json) =>
      ReferenceOption(
        code: json['code'] as String,
        label: (json['name'] ?? json['symbol'] ?? json['code']) as String,
      );

  final String code;
  final String label;
}

/// One row from list_sales / get_sale. Customer name is null for cash
/// sales (no party). is_voided is true when a reversing transaction
/// exists for this sale (architecture rule: originals stay immutable,
/// reversals are separate txn rows linked via reverses_transaction_id).
class SaleSummary {
  const SaleSummary({
    required this.txnId,
    required this.occurredAt,
    required this.postedAt,
    required this.partyId,
    required this.partyName,
    required this.totalAmount,
    required this.paidAmount,
    required this.paymentMethodCode,
    required this.isVoided,
    required this.reversalTxnId,
    required this.voidedAt,
  });

  factory SaleSummary.fromJson(Map<String, dynamic> json) => SaleSummary(
    txnId: json['txn_id'] as String,
    occurredAt: DateTime.parse(json['occurred_at'] as String),
    postedAt: json['posted_at'] == null
        ? null
        : DateTime.parse(json['posted_at'] as String),
    partyId: json['party_id'] as String?,
    partyName: json['party_name'] as String?,
    totalAmount: (json['total_amount'] as num).toDouble(),
    paidAmount: (json['paid_amount'] as num).toDouble(),
    paymentMethodCode: json['payment_method_code'] as String?,
    isVoided: json['is_voided'] as bool,
    reversalTxnId: json['reversal_txn_id'] as String?,
    voidedAt: json['voided_at'] == null
        ? null
        : DateTime.parse(json['voided_at'] as String),
  );

  final String txnId;
  final DateTime occurredAt;
  final DateTime? postedAt;
  final String? partyId;
  final String? partyName;
  final double totalAmount;
  final double paidAmount;
  final String? paymentMethodCode;
  final bool isVoided;
  final String? reversalTxnId;
  final DateTime? voidedAt;

  bool get isDebt =>
      (partyId != null) && (paidAmount < totalAmount);
}

/// One line on a sale's receipt. Names + unit labels use the
/// transaction-time snapshots so the receipt stays consistent if the
/// item was renamed afterwards.
class SaleLineDetail {
  const SaleLineDetail({
    required this.lineNo,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unitLabel,
    required this.unitAmount,
    required this.lineTotal,
  });

  factory SaleLineDetail.fromJson(Map<String, dynamic> json) => SaleLineDetail(
    lineNo: json['line_no'] as int,
    itemId: json['item_id'] as String?,
    itemName: json['item_name'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    unitLabel: json['unit_label'] as String? ?? '',
    unitAmount: (json['unit_amount'] as num?)?.toDouble(),
    lineTotal: (json['line_total'] as num).toDouble(),
  );

  final int lineNo;
  final String? itemId;
  final String itemName;
  final double quantity;
  final String unitLabel;
  final double? unitAmount;
  final double lineTotal;
}

class UnitOption {
  const UnitOption({
    required this.id,
    required this.code,
    required this.label,
  });

  factory UnitOption.fromJson(Map<String, dynamic> json) => UnitOption(
    id: json['id'] as String,
    code: json['code'] as String,
    label: json['default_label'] as String,
  );

  final String id;
  final String code;
  final String label;
}

/// One row from list_receive_units. Surfaces both the unit identity and
/// how to convert into base units (so the picker can show "25 kg per
/// bag" alongside the unit name).
class ReceiveUnitOption {
  const ReceiveUnitOption({
    required this.unitId,
    required this.unitCode,
    required this.unitLabel,
    required this.conversionToBase,
    required this.isDefault,
  });

  factory ReceiveUnitOption.fromJson(Map<String, dynamic> json) =>
      ReceiveUnitOption(
        unitId: json['unit_id'] as String,
        unitCode: json['unit_code'] as String,
        unitLabel: json['unit_label'] as String,
        conversionToBase: (json['conversion_to_base'] as num).toDouble(),
        isDefault: json['is_default'] as bool,
      );

  final String unitId;
  final String unitCode;
  final String unitLabel;
  final double conversionToBase;
  final bool isDefault;
}
