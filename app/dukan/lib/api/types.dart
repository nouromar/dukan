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
    required this.onboardingDismissedAt,
    this.lowStockWarningEnabled = false,
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
    final dismissedRaw = json['onboarding_dismissed_at'] as String?;
    return ShopSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      setupStatus: json['setup_status'] as String,
      currencyCode: code,
      currencySymbol: currencySymbols[code] ?? code,
      defaultLanguageCode: json['default_language_code'] as String,
      timezone: json['timezone'] as String,
      onboardingDismissedAt:
          dismissedRaw == null ? null : DateTime.parse(dismissedRaw),
      lowStockWarningEnabled:
          json['low_stock_warning_enabled'] as bool? ?? false,
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
  /// Null = the optional item-onboarding step still appears once on
  /// first sign-in after setup. Non-null = shopkeeper dismissed it and
  /// we go straight to Home from now on.
  final DateTime? onboardingDismissedAt;

  /// When false (default), the Sale screen's post-sale stock probe
  /// stays silent. When true, the probe fires toasts for items at or
  /// below their per-item `reorder_threshold` (or below 1 if no
  /// threshold set). Toggle lives in Settings.
  final bool lowStockWarningEnabled;

  bool get isReady => setupStatus == 'ready';
  bool get isTemplateApplied =>
      setupStatus == 'template_applied' || setupStatus == 'opening_stock_done';
  bool get isOnboardingPending => isReady && onboardingDismissedAt == null;
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

/// One row returned by the consolidated `search_items` RPC.
///
/// Three cases the screens have to handle:
///   1. Activated shop_item with packagings — `shopItemId` and
///      `defaultShopItemUnitId` both set; sale/receive flows tap to use.
///   2. Global catalog item the shop has NOT activated yet — `shopItemId`
///      is null, `itemId` is set, `isActivated` is false. Tap triggers
///      `ensureShopItem` (auto-activate) before adding to the cart.
///   3. Barcode hit — same shape as 1; `defaultShopItemUnitId` is the
///      *specific* packaging the barcode resolves to (overrides
///      `is_default_*` flags).
class ItemSearchResult {
  const ItemSearchResult({
    required this.shopItemId,
    required this.itemId,
    required this.displayName,
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required this.defaultShopItemUnitId,
    required this.defaultUnitCode,
    required this.defaultUnitLabel,
    required this.defaultUnitConversionToBase,
    required this.defaultUnitSalePrice,
    required this.defaultUnitLastCost,
    required this.currentStock,
    this.reorderThreshold,
    required this.packagingLabel,
    required this.isActivated,
    required this.rankReason,
  });

  factory ItemSearchResult.fromJson(Map<String, dynamic> json) {
    return ItemSearchResult(
      shopItemId: json['shop_item_id'] as String?,
      itemId: json['item_id'] as String?,
      displayName: json['display_name'] as String,
      baseUnitCode: json['base_unit_code'] as String,
      baseUnitLabel: json['base_unit_label'] as String,
      defaultShopItemUnitId: json['default_shop_item_unit_id'] as String?,
      defaultUnitCode: json['default_unit_code'] as String?,
      defaultUnitLabel: json['default_unit_label'] as String?,
      defaultUnitConversionToBase:
          (json['default_unit_conversion_to_base'] as num?)?.toDouble(),
      defaultUnitSalePrice:
          (json['default_unit_sale_price'] as num?)?.toDouble(),
      defaultUnitLastCost: (json['default_unit_last_cost'] as num?)?.toDouble(),
      currentStock: (json['current_stock'] as num?)?.toDouble(),
      reorderThreshold: (json['reorder_threshold'] as num?)?.toDouble(),
      packagingLabel: json['packaging_label'] as String?,
      isActivated: json['is_activated'] as bool,
      rankReason: json['rank_reason'] as String?,
    );
  }

  /// Null when the global item hasn't been activated by this shop yet.
  /// Tap triggers `ensureShopItem` before the cart line can be added.
  final String? shopItemId;

  /// Null when this is a shop-only item (no global catalog provenance).
  final String? itemId;

  /// Resolved through the alias chain (shop_item_alias → item_alias) in
  /// the search RPC. Already locale-appropriate; render as-is.
  final String displayName;

  final String baseUnitCode;
  final String baseUnitLabel;

  /// The screen-specific default packaging row id. Null on unactivated
  /// rows; the cart flow must call `ensureShopItem` first.
  final String? defaultShopItemUnitId;
  final String? defaultUnitCode;
  final String? defaultUnitLabel;
  final double? defaultUnitConversionToBase;

  /// Null when the cashier hasn't priced this packaging yet — Sale flow
  /// pops the priceRequired editor on tap.
  final double? defaultUnitSalePrice;

  /// Supplier-scoped on Receive when the search was called with
  /// `party_id`; otherwise the shop-wide last cost for this packaging.
  final double? defaultUnitLastCost;

  /// In base units. Display in the default sale packaging.
  final double? currentStock;

  /// Per-item warning threshold in base units. Null = no per-item
  /// threshold; the Sale tile + low-stock toast fall back to "warn
  /// when current_stock < 1".
  final double? reorderThreshold;

  /// Derived label like "25 kg bag" / "kg" / "12-bottle carton".
  final String? packagingLabel;

  final bool isActivated;

  /// One of: alias_exact_locale, alias_prefix_locale, alias_exact_any,
  /// alias_prefix_any, name_prefix, recency_boost, barcode_match.
  /// Surfaced so the UI can debug ranking surprises (critique #7).
  final String? rankReason;
}

/// Bundle returned by `get_party_detail` — header + last-N rows of
/// sales / receives / payments involving this party. The screen lays
/// these out together with a "PAY" CTA into the Payment flow.
class PartyDetail {
  const PartyDetail({
    required this.header,
    required this.sales,
    required this.receives,
    required this.payments,
  });

  factory PartyDetail.fromJson(Map<String, dynamic> json) => PartyDetail(
        header: PartyDetailHeader.fromJson(
          Map<String, dynamic>.from(json['header'] as Map),
        ),
        sales: (json['sales'] as List? ?? const [])
            .map((row) => PartyTxnRow.fromJson(Map<String, dynamic>.from(row)))
            .toList(growable: false),
        receives: (json['receives'] as List? ?? const [])
            .map((row) => PartyTxnRow.fromJson(Map<String, dynamic>.from(row)))
            .toList(growable: false),
        payments: (json['payments'] as List? ?? const [])
            .map((row) =>
                PartyPaymentRow.fromJson(Map<String, dynamic>.from(row)))
            .toList(growable: false),
      );

  final PartyDetailHeader header;
  final List<PartyTxnRow> sales;
  final List<PartyTxnRow> receives;
  final List<PartyPaymentRow> payments;
}

class PartyDetailHeader {
  const PartyDetailHeader({
    required this.id,
    required this.name,
    required this.phone,
    required this.typeCode,
    required this.receivable,
    required this.payable,
    required this.isActive,
  });

  factory PartyDetailHeader.fromJson(Map<String, dynamic> json) =>
      PartyDetailHeader(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        typeCode: json['type_code'] as String,
        receivable: (json['receivable'] as num?)?.toDouble() ?? 0,
        payable: (json['payable'] as num?)?.toDouble() ?? 0,
        isActive: json['is_active'] as bool? ?? true,
      );

  final String id;
  final String name;
  final String? phone;
  final String typeCode;
  final double receivable;
  final double payable;
  final bool isActive;
}

class PartyTxnRow {
  const PartyTxnRow({
    required this.txnId,
    required this.occurredAt,
    required this.totalAmount,
    required this.paidAmount,
    required this.isVoided,
  });

  factory PartyTxnRow.fromJson(Map<String, dynamic> json) => PartyTxnRow(
        txnId: json['txn_id'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
        totalAmount: (json['total_amount'] as num).toDouble(),
        paidAmount: (json['paid_amount'] as num).toDouble(),
        isVoided: json['is_voided'] as bool? ?? false,
      );

  final String txnId;
  final DateTime occurredAt;
  final double totalAmount;
  final double paidAmount;
  final bool isVoided;
}

class PartyPaymentRow {
  const PartyPaymentRow({
    required this.paymentId,
    required this.occurredAt,
    required this.amount,
    required this.direction,
  });

  factory PartyPaymentRow.fromJson(Map<String, dynamic> json) =>
      PartyPaymentRow(
        paymentId: json['payment_id'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
        amount: (json['amount'] as num).toDouble(),
        direction: json['direction'] as String,
      );

  final String paymentId;
  final DateTime occurredAt;
  final double amount;
  /// 'I' — inbound (customer pays the shop); 'O' — outbound (shop pays
  /// the supplier).
  final String direction;
}

/// Aggregate returned by `get_today_summary` — drives the Home/dashboard
/// "Today" card and the bottom-of-Home counters.
class TodaySummary {
  const TodaySummary({
    required this.salesToday,
    required this.receivablesTotal,
    required this.payablesTotal,
    required this.lowStockCount,
  });

  factory TodaySummary.fromJson(Map<String, dynamic> json) => TodaySummary(
        salesToday: (json['sales_today'] as num).toDouble(),
        receivablesTotal: (json['receivables_total'] as num).toDouble(),
        payablesTotal: (json['payables_total'] as num).toDouble(),
        lowStockCount: (json['low_stock_count'] as num).toInt(),
      );

  final double salesToday;
  final double receivablesTotal;
  final double payablesTotal;
  final int lowStockCount;
}

class PartyBalanceRow {
  const PartyBalanceRow({
    required this.partyId,
    required this.name,
    required this.phone,
    required this.amount,
  });

  factory PartyBalanceRow.fromJson(Map<String, dynamic> json) =>
      PartyBalanceRow(
        partyId: json['party_id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        amount: (json['amount'] as num).toDouble(),
      );

  final String partyId;
  final String name;
  final String? phone;
  /// Either receivable or payable depending on which list this row came
  /// from — the caller knows which.
  final double amount;
}

class LowStockRow {
  const LowStockRow({
    required this.shopItemId,
    required this.displayName,
    required this.currentStock,
    required this.reorderThreshold,
    required this.baseUnitCode,
    required this.baseUnitLabel,
  });

  factory LowStockRow.fromJson(Map<String, dynamic> json) => LowStockRow(
        shopItemId: json['shop_item_id'] as String,
        displayName: json['display_name'] as String,
        currentStock: (json['current_stock'] as num).toDouble(),
        reorderThreshold: (json['reorder_threshold'] as num?)?.toDouble(),
        baseUnitCode: json['base_unit_code'] as String,
        baseUnitLabel: json['base_unit_label'] as String,
      );

  final String shopItemId;
  final String displayName;
  final double currentStock;
  final double? reorderThreshold;
  final String baseUnitCode;
  final String baseUnitLabel;
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

/// One line on a `post_sale` RPC payload. The packaging is the
/// identity — the server derives `shop_item_id`, base-unit, conversion
/// and snapshots from `shop_item_unit_id`.
class SaleLine {
  const SaleLine({
    required this.shopItemUnitId,
    required this.quantity,
    required this.unitPrice,
  });

  final String shopItemUnitId;
  final num quantity;

  /// Per-packaging price the cashier rang up. If different from the
  /// stored `shop_item_unit.sale_price`, the RPC also updates the
  /// stored price (long-press / first-tap override is sticky).
  final num unitPrice;

  Map<String, dynamic> toJson() => {
    'shop_item_unit_id': shopItemUnitId,
    'quantity': quantity,
    'unit_price': unitPrice,
  };
}

/// post_receive line payload. The cashier types what's on the bono —
/// usually a line total like "5 bags rice $120" — and we want the
/// stored bono total to match the paper exactly. The RPC computes
/// per-unit cost from `line_total / quantity`, base-unit cost from
/// `line_total / (quantity * conversion_to_base)`, and upserts the
/// per-supplier last cost into `supplier_item_unit_cost`.
class ReceiveLinePayload {
  const ReceiveLinePayload({
    required this.shopItemUnitId,
    required this.quantity,
    required this.lineTotal,
  });

  final String shopItemUnitId;
  final num quantity;
  final num lineTotal;

  Map<String, dynamic> toJson() => {
    'shop_item_unit_id': shopItemUnitId,
    'quantity': quantity,
    'line_total': lineTotal,
  };
}

/// Item category — the catalog hierarchy's top level, rendered in the
/// Add new item and shop_item editor dropdowns. Translated `name` is
/// resolved by the `list_categories` RPC.
class CategoryOption {
  const CategoryOption({
    required this.id,
    required this.code,
    required this.name,
  });

  factory CategoryOption.fromJson(Map<String, dynamic> json) => CategoryOption(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
      );

  final String id;
  final String code;
  final String name;
}

/// One row in the Top movers list — a product that sold in the
/// period with its aggregate volume + revenue. Units are in the
/// product's base unit (kg, piece, etc.).
class TopMoverRow {
  const TopMoverRow({
    required this.shopItemId,
    required this.displayName,
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required this.unitsSoldBase,
    required this.revenue,
    required this.salesCount,
  });

  factory TopMoverRow.fromJson(Map<String, dynamic> json) => TopMoverRow(
        shopItemId: json['shop_item_id'] as String,
        displayName: json['display_name'] as String,
        baseUnitCode: json['base_unit_code'] as String,
        baseUnitLabel: json['base_unit_label'] as String,
        unitsSoldBase: (json['units_sold_base'] as num).toDouble(),
        revenue: (json['revenue'] as num).toDouble(),
        salesCount: json['sales_count'] as int,
      );

  final String shopItemId;
  final String displayName;
  final String baseUnitCode;
  final String baseUnitLabel;
  final double unitsSoldBase;
  final double revenue;
  final int salesCount;
}

/// Row in the Dead-stock segment — has stock on hand, zero sales in
/// the period. Same id/name/base-unit shape, just no aggregates.
class DeadStockRow {
  const DeadStockRow({
    required this.shopItemId,
    required this.displayName,
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required this.currentStock,
  });

  factory DeadStockRow.fromJson(Map<String, dynamic> json) => DeadStockRow(
        shopItemId: json['shop_item_id'] as String,
        displayName: json['display_name'] as String,
        baseUnitCode: json['base_unit_code'] as String,
        baseUnitLabel: json['base_unit_label'] as String,
        currentStock: (json['current_stock'] as num).toDouble(),
      );

  final String shopItemId;
  final String displayName;
  final String baseUnitCode;
  final String baseUnitLabel;
  final double currentStock;
}

class ProductVelocity {
  const ProductVelocity({required this.top, required this.dead});
  final List<TopMoverRow> top;
  final List<DeadStockRow> dead;
}

/// Row returned by `list_payments`. Direction 'I' = inbound (customer
/// paid us); 'O' = outbound (we paid a supplier). `isRefund` flags
/// outbound payments minted by void_sale's refund path.
class PaymentSummary {
  const PaymentSummary({
    required this.paymentId,
    required this.occurredAt,
    required this.createdAt,
    required this.amount,
    required this.direction,
    this.partyId,
    this.partyName,
    this.paymentMethodCode,
    this.notes,
    this.isRefund = false,
  });

  factory PaymentSummary.fromJson(Map<String, dynamic> json) => PaymentSummary(
        paymentId: json['payment_id'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        amount: (json['amount'] as num).toDouble(),
        direction: json['direction'] as String,
        partyId: json['party_id'] as String?,
        partyName: json['party_name'] as String?,
        paymentMethodCode: json['payment_method_code'] as String?,
        notes: json['notes'] as String?,
        isRefund: json['is_refund'] as bool? ?? false,
      );

  final String paymentId;
  final DateTime occurredAt;
  final DateTime createdAt;
  final double amount;

  /// 'I' (inbound, customer → us) or 'O' (outbound, us → supplier).
  final String direction;
  final String? partyId;
  final String? partyName;
  final String? paymentMethodCode;
  final String? notes;
  final bool isRefund;
}

/// Row returned by `list_expenses`. Mirrors the SaleSummary / ReceiveSummary
/// shape but tailored to the expense single-line, no-party model.
class ExpenseSummary {
  const ExpenseSummary({
    required this.txnId,
    required this.occurredAt,
    required this.postedAt,
    required this.amount,
    this.paymentMethodCode,
    this.categoryId,
    this.categoryName,
    this.notes,
  });

  factory ExpenseSummary.fromJson(Map<String, dynamic> json) => ExpenseSummary(
        txnId: json['txn_id'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
        postedAt: DateTime.parse(json['posted_at'] as String),
        amount: (json['amount'] as num).toDouble(),
        paymentMethodCode: json['payment_method_code'] as String?,
        categoryId: json['category_id'] as String?,
        categoryName: json['category_name'] as String?,
        notes: json['notes'] as String?,
      );

  final String txnId;
  final DateTime occurredAt;
  final DateTime postedAt;
  final double amount;
  final String? paymentMethodCode;
  final String? categoryId;
  final String? categoryName;
  final String? notes;
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

/// One line on a sale's (or receive's) receipt. Names + unit labels +
/// packaging label all come from transaction-time snapshots so the
/// receipt stays consistent even if the item/packaging was renamed,
/// retired, or had its conversion changed afterwards.
class SaleLineDetail {
  const SaleLineDetail({
    required this.lineNo,
    required this.itemId,
    required this.shopItemUnitId,
    required this.itemName,
    required this.quantity,
    required this.unitLabel,
    required this.unitAmount,
    required this.lineTotal,
    required this.packagingLabel,
  });

  factory SaleLineDetail.fromJson(Map<String, dynamic> json) => SaleLineDetail(
    lineNo: json['line_no'] as int,
    itemId: json['item_id'] as String?,
    shopItemUnitId: json['shop_item_unit_id'] as String?,
    itemName: json['item_name'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    unitLabel: json['unit_label'] as String? ?? '',
    unitAmount: (json['unit_amount'] as num?)?.toDouble(),
    lineTotal: (json['line_total'] as num).toDouble(),
    packagingLabel: json['packaging_label'] as String?,
  );

  final int lineNo;
  final String? itemId;

  /// Snapshot of the packaging used on this line. Stays stable for
  /// receipt re-render regardless of subsequent shop_item_unit edits.
  final String? shopItemUnitId;

  final String itemName;
  final double quantity;
  final String unitLabel;
  final double? unitAmount;
  final double lineTotal;

  /// Derived "25 kg bag" / "kg" label as it appeared at posting time.
  /// Null on expense lines.
  final String? packagingLabel;
}

/// Receive history rows have the same shape as sale history (header
/// + voided flag). Reusing SaleSummary directly is tempting but the
/// "Sale" name leaks into receive UI code; a typedef gives us better
/// labels without duplicating the model.
typedef ReceiveSummary = SaleSummary;
typedef ReceiveLineDetail = SaleLineDetail;

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

/// One row from `list_shop_item_units`. The identity is the
/// `shopItemUnitId` (a packaging, not a unit) — that's what posting RPCs
/// take. The unit_code / unit_label / conversion are denormalized for
/// display.
///
/// `isDefault` is screen-resolved by the ShopApi method that wraps the
/// RPC (the underlying row carries both `is_default_sale` and
/// `is_default_receive`; the wrapper picks the right one based on the
/// caller's screen argument). The editor screen wanting both flags
/// should use `ShopItemUnitDetail` instead.
class ReceiveUnitOption {
  const ReceiveUnitOption({
    required this.shopItemUnitId,
    required this.unitCode,
    required this.unitLabel,
    required this.packagingLabel,
    required this.conversionToBase,
    required this.salePrice,
    required this.lastCost,
    required this.isDefault,
    required this.isBaseUnit,
  });

  factory ReceiveUnitOption.fromJson(
    Map<String, dynamic> json, {
    required String screen,
  }) {
    final defaultFlagKey =
        screen == 'sale' ? 'is_default_sale' : 'is_default_receive';
    return ReceiveUnitOption(
      shopItemUnitId: json['shop_item_unit_id'] as String,
      unitCode: json['unit_code'] as String,
      unitLabel: json['unit_label'] as String,
      packagingLabel: json['packaging_label'] as String,
      conversionToBase: (json['conversion_to_base'] as num).toDouble(),
      salePrice: (json['sale_price'] as num?)?.toDouble(),
      lastCost: (json['last_cost'] as num?)?.toDouble(),
      isDefault: json[defaultFlagKey] as bool,
      isBaseUnit: json['is_base_unit'] as bool,
    );
  }

  final String shopItemUnitId;
  final String unitCode;
  final String unitLabel;

  /// Derived label like "25 kg bag" / "kg".
  final String packagingLabel;

  final double conversionToBase;
  final double? salePrice;
  final double? lastCost;

  /// Resolved at fetch time based on screen ('sale' vs 'receive').
  final bool isDefault;

  /// True when this packaging IS the item's base unit (conversion=1).
  final bool isBaseUnit;
}

/// One row from `listShopItems` — the Products screen list.
class ShopItemSummary {
  const ShopItemSummary({
    required this.shopItemId,
    required this.itemId,
    required this.displayName,
    required this.categoryName,
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required this.currentStock,
    this.reorderThreshold,
    required this.unitCount,
    required this.isActive,
    this.defaultSalePrice,
    this.anyPriceSet = false,
  });

  factory ShopItemSummary.fromJson(Map<String, dynamic> json) =>
      ShopItemSummary(
        shopItemId: json['shop_item_id'] as String,
        itemId: json['item_id'] as String?,
        displayName: json['display_name'] as String,
        categoryName: json['category_name'] as String?,
        baseUnitCode: json['base_unit_code'] as String,
        baseUnitLabel: json['base_unit_label'] as String,
        currentStock: (json['current_stock'] as num).toDouble(),
        reorderThreshold: (json['reorder_threshold'] as num?)?.toDouble(),
        unitCount: json['unit_count'] as int,
        isActive: json['is_active'] as bool,
        // 0045 additions — null in older callers / fixtures.
        defaultSalePrice:
            (json['default_sale_price'] as num?)?.toDouble(),
        anyPriceSet: json['any_price_set'] as bool? ?? false,
      );

  final String shopItemId;

  /// Null = shop-only item (no global catalog provenance).
  final String? itemId;
  final String displayName;
  final String? categoryName;
  final String baseUnitCode;
  final String baseUnitLabel;

  /// In base units. Render in the default sale packaging at the call site.
  final double currentStock;

  /// Per-item low-stock warning threshold in base units. Null when the
  /// shopkeeper hasn't set one — the indicator/toast falls back to
  /// "warn when current_stock < 1".
  final double? reorderThreshold;

  /// How many packagings the shop has for this item. Drives whether the
  /// Products screen renders a "+ Add packaging" entry inline.
  final int unitCount;

  final bool isActive;

  /// Sale price of the default-for-sale packaging (or the base
  /// packaging if no default is marked). Null when neither has a
  /// price — drives the "no price yet" row label + headline count.
  final double? defaultSalePrice;

  /// True if any packaging on this shop_item has a non-null
  /// sale_price. Drives the "no price yet" filter.
  final bool anyPriceSet;
}

/// Full per-packaging detail for the shop_item editor / detail screen.
///
/// Differs from `ReceiveUnitOption` in that both default flags are
/// surfaced raw — the editor needs to show "default for sale" + "default
/// for receive" independently and let the shopkeeper flip either.
class ShopItemUnitDetail {
  const ShopItemUnitDetail({
    required this.shopItemUnitId,
    required this.itemUnitId,
    required this.unitCode,
    required this.unitLabel,
    required this.packagingLabel,
    required this.conversionToBase,
    required this.salePrice,
    required this.lastCost,
    required this.isDefaultSale,
    required this.isDefaultReceive,
    required this.isBaseUnit,
    required this.isActive,
  });

  factory ShopItemUnitDetail.fromJson(Map<String, dynamic> json) =>
      ShopItemUnitDetail(
        shopItemUnitId: json['shop_item_unit_id'] as String,
        itemUnitId: json['item_unit_id'] as String?,
        unitCode: json['unit_code'] as String,
        unitLabel: json['unit_label'] as String,
        packagingLabel: json['packaging_label'] as String,
        conversionToBase: (json['conversion_to_base'] as num).toDouble(),
        salePrice: (json['sale_price'] as num?)?.toDouble(),
        lastCost: (json['last_cost'] as num?)?.toDouble(),
        isDefaultSale: json['is_default_sale'] as bool,
        isDefaultReceive: json['is_default_receive'] as bool,
        isBaseUnit: json['is_base_unit'] as bool,
        isActive: json['is_active'] as bool? ?? true,
      );

  final String shopItemUnitId;

  /// Null = shop-only packaging (no global item_unit provenance).
  final String? itemUnitId;

  final String unitCode;
  final String unitLabel;
  final String packagingLabel;
  final double conversionToBase;

  /// Null is meaningful — packaging hasn't been priced; priceRequired
  /// editor fires on first sale (matches `shop_item_unit.sale_price`
  /// semantics in 0007).
  final double? salePrice;
  final double? lastCost;
  final bool isDefaultSale;
  final bool isDefaultReceive;
  final bool isBaseUnit;
  final bool isActive;
}
