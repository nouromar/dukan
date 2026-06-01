// Cross-feature DTOs shared between AuthController (state) and ShopApi
// (data). Kept in one place so neither layer "owns" them and consumers
// (screens, tests, fixtures) import from a single canonical path.

class ShopSummary {
  const ShopSummary({
    required this.id,
    required this.name,
    required this.setupStatus,
    required this.currencyCode,
    required this.defaultLanguageCode,
    required this.timezone,
  });

  factory ShopSummary.fromJson(Map<String, dynamic> json) => ShopSummary(
    id: json['id'] as String,
    name: json['name'] as String,
    setupStatus: json['setup_status'] as String,
    currencyCode: json['currency_code'] as String,
    defaultLanguageCode: json['default_language_code'] as String,
    timezone: json['timezone'] as String,
  );

  final String id;
  final String name;
  final String setupStatus;
  final String currencyCode;
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
  final double? salePrice;
  /// Supplier-specific last unit cost. Populated only when the search
  /// was called with a party_id on the Receive screen; null otherwise.
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

/// post_receive line payload. v1 only sends per-unit cost; the line_total
/// alternative the RPC also accepts is reserved for future bono-OCR
/// flows that surface a line total without a unit cost.
class ReceiveLinePayload {
  const ReceiveLinePayload({
    required this.itemId,
    required this.quantity,
    required this.unitId,
    required this.unitCost,
  });

  final String itemId;
  final num quantity;
  final String unitId;
  final num unitCost;

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'quantity': quantity,
    'unit_id': unitId,
    'unit_cost': unitCost,
  };
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
