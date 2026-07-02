// Dispatches a PendingPost to the corresponding ShopApi method.
// Decoupled from OfflineQueueController so the controller can be
// unit-tested with a stub executor and the executor can be unit-
// tested with a real ShopApi + fake Supabase client.
//
// Phase 1 wired post_sale. Phase 5B (#367) adds post_receive,
// post_payment, and post_expense so all four daily-flow posting
// RPCs queue on transient failure.

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/queue/pending_post.dart';

class PostExecutor {
  PostExecutor(this._api);

  final ShopApi _api;

  Future<void> execute(PendingPost post) async {
    // Mutation RPCs (#390) — no entity-id to audit-stamp; return early
    // after dispatch. The server-side `mutation_idempotency` table from
    // 0074 makes a retry of the same `client_op_id` a safe no-op.
    if (_isMutationRpc(post.rpc)) {
      await _executeMutation(post);
      return;
    }
    final String entityId;
    switch (post.rpc) {
      case 'post_sale':
        entityId = await _executeSale(post);
      case 'post_receive':
        entityId = await _executeReceive(post);
      case 'post_payment':
        entityId = await _executePayment(post);
      case 'post_expense':
        entityId = await _executeExpense(post);
      case 'post_inventory_adjustment':
        entityId = await _executeInventoryAdjustment(post);
      default:
        throw UnsupportedError(
          'OfflineQueue does not yet know how to retry ${post.rpc}',
        );
    }
    // #368 audit-stamping: if the cashier who originated this post
    // is captured (set at enqueue time from auth.uid()), backfill
    // it onto the freshly-created audit row. Best-effort — don't
    // fail the drain over audit metadata.
    if (post.originalActorUserId.isNotEmpty) {
      try {
        await _api.setAuditOriginalActor(
          shopId: post.shopId,
          entityId: entityId,
          originalActorUserId: post.originalActorUserId,
        );
      } catch (_) {
        // Audit-stamp failure is non-fatal. The post landed; the
        // audit row exists with the drainer as actor; we just lost
        // the originator backfill.
      }
    }
  }

  Future<String> _executeSale(PendingPost post) async {
    final p = post.params;
    final lines = (p['lines'] as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .map((m) => SaleLine(
              shopItemUnitId: m['shop_item_unit_id'] as String,
              quantity: (m['quantity'] as num),
              unitPrice: (m['unit_price'] as num),
            ))
        .toList(growable: false);
    return _api.postSale(
      shopId: post.shopId,
      lines: lines,
      paidAmount: (p['paid_amount'] as num),
      partyId: p['party_id'] as String?,
      paymentMethodCode: p['payment_method_code'] as String?,
      clientOpId: post.clientOpId,
      occurredAt: _occurredAt(p),
    );
  }

  Future<String> _executeReceive(PendingPost post) async {
    final p = post.params;
    final lines = (p['lines'] as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .map((m) => ReceiveLinePayload(
              shopItemUnitId: m['shop_item_unit_id'] as String,
              quantity: (m['quantity'] as num),
              lineTotal: (m['line_total'] as num),
            ))
        .toList(growable: false);
    return _api.postReceive(
      shopId: post.shopId,
      partyId: p['party_id'] as String,
      lines: lines,
      paidAmount: (p['paid_amount'] as num),
      paymentMethodCode: p['payment_method_code'] as String?,
      documentId: p['document_id'] as String?,
      clientOpId: post.clientOpId,
      notes: p['notes'] as String?,
      occurredAt: _occurredAt(p),
    );
  }

  Future<String> _executePayment(PendingPost post) async {
    final p = post.params;
    final rawAllocs = p['allocations'];
    final allocations = rawAllocs is List
        ? rawAllocs
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .map((m) => PaymentAllocationInput(
                  transactionId: m['transaction_id'] as String,
                  amount: (m['amount'] as num),
                ))
            .toList(growable: false)
        : null;
    return _api.postPayment(
      shopId: post.shopId,
      partyId: p['party_id'] as String,
      direction: p['direction'] as String,
      amount: (p['amount'] as num),
      paymentMethodCode: p['payment_method_code'] as String,
      clientOpId: post.clientOpId,
      notes: p['notes'] as String?,
      allocations: allocations,
      occurredAt: _occurredAt(p),
    );
  }

  Future<String> _executeExpense(PendingPost post) async {
    final p = post.params;
    return _api.postExpense(
      shopId: post.shopId,
      expenseCategoryId: p['expense_category_id'] as String,
      amount: (p['amount'] as num),
      paymentMethodCode: p['payment_method_code'] as String,
      clientOpId: post.clientOpId,
      notes: p['notes'] as String?,
      occurredAt: _occurredAt(p),
    );
  }

  /// Parse the optional backdated timestamp (#5) from queued params.
  static DateTime? _occurredAt(Map<String, dynamic> p) {
    final raw = p['occurred_at'] as String?;
    return raw == null ? null : DateTime.parse(raw);
  }

  Future<String> _executeInventoryAdjustment(PendingPost post) async {
    final p = post.params;
    return _api.postInventoryAdjustment(
      shopId: post.shopId,
      reasonCode: p['reason_code'] as String,
      shopItemId: p['shop_item_id'] as String,
      quantityDelta: p['quantity_delta'] as num,
      unitCost: p['unit_cost'] as num?,
      clientOpId: post.clientOpId,
      notes: p['notes'] as String?,
    );
  }

  // #390: admin-side mutation dispatch ----------------------------------

  static bool _isMutationRpc(String rpc) {
    switch (rpc) {
      case 'add_shop_item_alias':
      case 'remove_shop_item_alias':
      case 'set_shop_item_unit_sale_price':
      case 'set_shop_item_unit_default_flags':
      case 'set_shop_item_category':
      case 'set_supplier_item_unit_cost':
      case 'remove_or_disable_shop_item_unit':
      case 'add_shop_item_barcode':
      case 'remove_shop_item_barcode':
      case 'set_primary_shop_item_barcode':
      case 'update_party':
      case 'set_party_active':
      case 'create_party':
      case 'post_opening_party_balance':
      case 'create_shop_item':
      case 'create_shop_item_unit':
      case 'set_shop_item_active':
      case 'create_shop_category':
      case 'rename_shop_category':
      case 'set_shop_category_active':
      case 'create_expense_category':
      case 'rename_expense_category':
      case 'set_expense_category_active':
        return true;
      default:
        return false;
    }
  }

  Future<void> _executeMutation(PendingPost post) async {
    final p = post.params;
    final shopId = post.shopId;
    final clientOpId = post.clientOpId;
    switch (post.rpc) {
      case 'add_shop_item_alias':
        await _api.addShopItemAlias(
          shopId: shopId,
          shopItemId: p['shop_item_id'] as String,
          aliasText: p['alias_text'] as String,
          languageCode: p['language_code'] as String?,
          isDisplay: (p['is_display'] as bool?) ?? false,
          source: (p['source'] as String?) ?? 'manual',
          clientOpId: clientOpId,
        );
      case 'remove_shop_item_alias':
        await _api.removeShopItemAlias(
          shopId: shopId,
          aliasId: p['alias_id'] as String,
          clientOpId: clientOpId,
        );
      case 'set_shop_item_unit_sale_price':
        await _api.setShopItemUnitSalePrice(
          shopId: shopId,
          shopItemUnitId: p['shop_item_unit_id'] as String,
          salePrice: p['sale_price'] as num?,
          clientOpId: clientOpId,
        );
      case 'set_shop_item_unit_default_flags':
        await _api.setShopItemUnitDefaultFlags(
          shopId: shopId,
          shopItemUnitId: p['shop_item_unit_id'] as String,
          isDefaultSale: p['is_default_sale'] as bool,
          isDefaultReceive: p['is_default_receive'] as bool,
          clientOpId: clientOpId,
        );
      case 'set_shop_item_category':
        await _api.setShopItemCategory(
          shopId: shopId,
          shopItemId: p['shop_item_id'] as String,
          categoryId: p['category_id'] as String?,
          clientOpId: clientOpId,
        );
      case 'remove_or_disable_shop_item_unit':
        await _api.removeOrDisableShopItemUnit(
          shopId: shopId,
          shopItemUnitId: p['shop_item_unit_id'] as String,
          clientOpId: clientOpId,
        );
      case 'add_shop_item_barcode':
        await _api.addShopItemBarcode(
          shopId: shopId,
          shopItemUnitId: p['shop_item_unit_id'] as String,
          barcode: p['barcode'] as String,
          isPrimary: (p['is_primary'] as bool?) ?? false,
          symbology: p['symbology'] as String?,
          clientOpId: clientOpId,
        );
      case 'remove_shop_item_barcode':
        await _api.removeShopItemBarcode(
          shopId: shopId,
          barcodeId: p['barcode_id'] as String,
          clientOpId: clientOpId,
        );
      case 'set_primary_shop_item_barcode':
        await _api.setPrimaryShopItemBarcode(
          shopId: shopId,
          barcodeId: p['barcode_id'] as String,
          clientOpId: clientOpId,
        );
      case 'create_party':
        // Offline party create (0093): the client minted party_id, so the
        // drain is a fire-and-confirm idempotent upsert; the returned id is
        // ignored (the cart/mirror already hold it).
        await _api.createParty(
          shopId: shopId,
          name: p['name'] as String,
          typeCode: p['type_code'] as String,
          phone: p['phone'] as String?,
          partyId: p['party_id'] as String,
          clientOpId: clientOpId,
        );
      case 'post_opening_party_balance':
        await _api.postOpeningPartyBalance(
          shopId: shopId,
          partyId: p['party_id'] as String,
          amount: p['amount'] as num,
          direction: p['direction'] as String,
          clientOpId: clientOpId,
          notes: p['notes'] as String?,
        );
      case 'create_shop_item':
        // Offline product create (0095): client minted the item + unit ids
        // → idempotent fire-and-confirm; the returned ids are ignored (the
        // cart/mirror already hold them).
        await _api.createShopItem(
          shopId: shopId,
          name: p['name'] as String,
          languageCode: p['language_code'] as String,
          baseUnitCode: p['base_unit_code'] as String,
          salePrice: p['sale_price'] as num?,
          categoryId: p['category_id'] as String?,
          soldUnitCode: p['sold_unit_code'] as String?,
          soldConversion: p['sold_conversion'] as num?,
          defaultSide: (p['default_side'] as String?) ?? 'sale',
          shopItemId: p['shop_item_id'] as String,
          baseUnitId: p['base_unit_id'] as String,
          soldUnitId: p['sold_unit_id'] as String?,
          clientOpId: clientOpId,
        );
      case 'set_supplier_item_unit_cost':
        // Naturally idempotent (last-write-wins), so no client_op_id needed.
        await _api.setSupplierItemUnitCost(
          shopId: shopId,
          partyId: p['party_id'] as String,
          shopItemUnitId: p['shop_item_unit_id'] as String,
          unitCost: p['unit_cost'] as num,
        );
      case 'create_shop_item_unit':
        // Offline packaging create (0094): client minted the id → idempotent
        // fire-and-confirm; the returned id is ignored (mirror already holds it).
        await _api.createShopItemUnit(
          shopId: shopId,
          shopItemId: p['shop_item_id'] as String,
          unitCode: p['unit_code'] as String,
          conversionToBase: p['conversion_to_base'] as num,
          salePrice: p['sale_price'] as num?,
          shopItemUnitId: p['shop_item_unit_id'] as String,
          clientOpId: clientOpId,
        );
      case 'update_party':
        await _api.updateParty(
          shopId: shopId,
          partyId: p['party_id'] as String,
          name: p['name'] as String,
          phone: p['phone'] as String?,
          clientOpId: clientOpId,
        );
      case 'set_party_active':
        await _api.setPartyActive(
          shopId: shopId,
          partyId: p['party_id'] as String,
          isActive: p['is_active'] as bool,
          clientOpId: clientOpId,
        );
      case 'set_shop_item_active':
        await _api.setShopItemActive(
          shopId: shopId,
          shopItemId: p['shop_item_id'] as String,
          isActive: p['is_active'] as bool,
        );
      case 'create_shop_category':
        await _api.createShopCategory(
          shopId: shopId,
          categoryId: p['category_id'] as String,
          name: p['name'] as String,
          clientOpId: clientOpId,
        );
      case 'rename_shop_category':
        await _api.renameShopCategory(
          shopId: shopId,
          categoryId: p['category_id'] as String,
          name: p['name'] as String,
          clientOpId: clientOpId,
        );
      case 'set_shop_category_active':
        await _api.setShopCategoryActive(
          shopId: shopId,
          categoryId: p['category_id'] as String,
          isActive: p['is_active'] as bool,
          clientOpId: clientOpId,
        );
      case 'create_expense_category':
        await _api.createExpenseCategory(
          shopId: shopId,
          categoryId: p['category_id'] as String,
          name: p['name'] as String,
          clientOpId: clientOpId,
        );
      case 'rename_expense_category':
        await _api.renameExpenseCategory(
          shopId: shopId,
          categoryId: p['category_id'] as String,
          name: p['name'] as String,
          clientOpId: clientOpId,
        );
      case 'set_expense_category_active':
        await _api.setExpenseCategoryActive(
          shopId: shopId,
          categoryId: p['category_id'] as String,
          isActive: p['is_active'] as bool,
          clientOpId: clientOpId,
        );
      default:
        throw UnsupportedError(
          'PostExecutor mutation branch missing for ${post.rpc}',
        );
    }
  }
}

/// Helper that builds the params map for a post_sale enqueue. Lives
/// here so the screen call sites stay simple and the schema is
/// shared with the executor that reads it.
Map<String, dynamic> buildPostSaleParams({
  required List<SaleLine> lines,
  required num paidAmount,
  String? partyId,
  String? paymentMethodCode,
  DateTime? occurredAt,
}) =>
    <String, dynamic>{
      'lines': lines
          .map((l) => {
                'shop_item_unit_id': l.shopItemUnitId,
                'quantity': l.quantity,
                'unit_price': l.unitPrice,
              })
          .toList(growable: false),
      'paid_amount': paidAmount,
      if (partyId != null) 'party_id': partyId,
      if (paymentMethodCode != null) 'payment_method_code': paymentMethodCode,
      if (occurredAt != null) 'occurred_at': occurredAt.toUtc().toIso8601String(),
    };

Map<String, dynamic> buildPostReceiveParams({
  required String partyId,
  required List<ReceiveLinePayload> lines,
  required num paidAmount,
  String? paymentMethodCode,
  String? documentId,
  String? notes,
  DateTime? occurredAt,
}) =>
    <String, dynamic>{
      'party_id': partyId,
      'lines': lines
          .map((l) => {
                'shop_item_unit_id': l.shopItemUnitId,
                'quantity': l.quantity,
                'line_total': l.lineTotal,
              })
          .toList(growable: false),
      'paid_amount': paidAmount,
      if (paymentMethodCode != null) 'payment_method_code': paymentMethodCode,
      if (documentId != null) 'document_id': documentId,
      if (notes != null) 'notes': notes,
      if (occurredAt != null) 'occurred_at': occurredAt.toUtc().toIso8601String(),
    };

Map<String, dynamic> buildPostPaymentParams({
  required String partyId,
  required String direction,
  required num amount,
  required String paymentMethodCode,
  String? notes,
  List<PaymentAllocationInput>? allocations,
  DateTime? occurredAt,
}) =>
    <String, dynamic>{
      'party_id': partyId,
      'direction': direction,
      'amount': amount,
      'payment_method_code': paymentMethodCode,
      if (notes != null) 'notes': notes,
      if (occurredAt != null) 'occurred_at': occurredAt.toUtc().toIso8601String(),
      if (allocations != null && allocations.isNotEmpty)
        'allocations': allocations
            .map((a) => {
                  'transaction_id': a.transactionId,
                  'amount': a.amount,
                })
            .toList(growable: false),
    };

Map<String, dynamic> buildPostExpenseParams({
  required String expenseCategoryId,
  required num amount,
  required String paymentMethodCode,
  String? notes,
  DateTime? occurredAt,
}) =>
    <String, dynamic>{
      'expense_category_id': expenseCategoryId,
      'amount': amount,
      'payment_method_code': paymentMethodCode,
      if (notes != null) 'notes': notes,
      if (occurredAt != null) 'occurred_at': occurredAt.toUtc().toIso8601String(),
    };

Map<String, dynamic> buildPostInventoryAdjustmentParams({
  required String reasonCode,
  required String shopItemId,
  required num quantityDelta,
  num? unitCost,
  String? notes,
}) =>
    <String, dynamic>{
      'reason_code': reasonCode,
      'shop_item_id': shopItemId,
      'quantity_delta': quantityDelta,
      if (unitCost != null) 'unit_cost': unitCost,
      if (notes != null) 'notes': notes,
    };

// #390: builders for admin-side mutation params ------------------------

Map<String, dynamic> buildAddShopItemAliasParams({
  required String shopItemId,
  required String aliasText,
  String? languageCode,
  bool isDisplay = false,
  String source = 'manual',
}) =>
    <String, dynamic>{
      'shop_item_id': shopItemId,
      'alias_text': aliasText,
      if (languageCode != null) 'language_code': languageCode,
      'is_display': isDisplay,
      'source': source,
    };

Map<String, dynamic> buildRemoveShopItemAliasParams({
  required String aliasId,
}) =>
    <String, dynamic>{'alias_id': aliasId};

Map<String, dynamic> buildSetShopItemUnitSalePriceParams({
  required String shopItemUnitId,
  required num? salePrice,
}) =>
    <String, dynamic>{
      'shop_item_unit_id': shopItemUnitId,
      'sale_price': salePrice,
    };

Map<String, dynamic> buildSetShopItemUnitDefaultFlagsParams({
  required String shopItemUnitId,
  required bool isDefaultSale,
  required bool isDefaultReceive,
}) =>
    <String, dynamic>{
      'shop_item_unit_id': shopItemUnitId,
      'is_default_sale': isDefaultSale,
      'is_default_receive': isDefaultReceive,
    };

Map<String, dynamic> buildSetShopItemCategoryParams({
  required String shopItemId,
  required String? categoryId,
}) =>
    <String, dynamic>{
      'shop_item_id': shopItemId,
      'category_id': categoryId,
    };

// Manage-categories (0076). Create passes a client-generated category_id
// so the optimistic mirror row and the server row share one id.
Map<String, dynamic> buildCreateCategoryParams({
  required String categoryId,
  required String name,
}) =>
    <String, dynamic>{'category_id': categoryId, 'name': name};

Map<String, dynamic> buildRenameCategoryParams({
  required String categoryId,
  required String name,
}) =>
    <String, dynamic>{'category_id': categoryId, 'name': name};

Map<String, dynamic> buildSetCategoryActiveParams({
  required String categoryId,
  required bool isActive,
}) =>
    <String, dynamic>{'category_id': categoryId, 'is_active': isActive};

Map<String, dynamic> buildRemoveOrDisableShopItemUnitParams({
  required String shopItemUnitId,
}) =>
    <String, dynamic>{'shop_item_unit_id': shopItemUnitId};

Map<String, dynamic> buildAddShopItemBarcodeParams({
  required String shopItemUnitId,
  required String barcode,
  bool isPrimary = false,
  String? symbology,
}) =>
    <String, dynamic>{
      'shop_item_unit_id': shopItemUnitId,
      'barcode': barcode,
      'is_primary': isPrimary,
      if (symbology != null) 'symbology': symbology,
    };

Map<String, dynamic> buildRemoveShopItemBarcodeParams({
  required String barcodeId,
}) =>
    <String, dynamic>{'barcode_id': barcodeId};

Map<String, dynamic> buildSetPrimaryShopItemBarcodeParams({
  required String barcodeId,
}) =>
    <String, dynamic>{'barcode_id': barcodeId};

// Offline party create (0093). partyId is client-generated so the
// optimistic mirror row and the eventual server row share one id.
Map<String, dynamic> buildCreatePartyParams({
  required String partyId,
  required String name,
  required String typeCode,
  String? phone,
}) =>
    <String, dynamic>{
      'party_id': partyId,
      'name': name,
      'type_code': typeCode,
      if (phone != null) 'phone': phone,
    };

Map<String, dynamic> buildPostOpeningPartyBalanceParams({
  required String partyId,
  required num amount,
  required String direction,
  String? notes,
}) =>
    <String, dynamic>{
      'party_id': partyId,
      'amount': amount,
      'direction': direction,
      if (notes != null) 'notes': notes,
    };

// Supplier per-unit cost (offline Products editor). Naturally idempotent —
// re-draining sets the same last-write-wins cost.
Map<String, dynamic> buildSetSupplierItemUnitCostParams({
  required String partyId,
  required String shopItemUnitId,
  required num unitCost,
}) =>
    <String, dynamic>{
      'party_id': partyId,
      'shop_item_unit_id': shopItemUnitId,
      'unit_cost': unitCost,
    };

// Offline product create (0095). The client mints the item id + both
// possible packaging ids (base, and the distinct sold unit when present)
// so the optimistic mirror rows and the server rows share ids.
Map<String, dynamic> buildCreateShopItemParams({
  required String shopItemId,
  required String baseUnitId,
  required String name,
  required String languageCode,
  required String baseUnitCode,
  num? salePrice,
  String? categoryId,
  String? soldUnitCode,
  num? soldConversion,
  String? soldUnitId,
  String defaultSide = 'sale',
}) =>
    <String, dynamic>{
      'shop_item_id': shopItemId,
      'base_unit_id': baseUnitId,
      'name': name,
      'language_code': languageCode,
      'base_unit_code': baseUnitCode,
      'default_side': defaultSide,
      if (salePrice != null) 'sale_price': salePrice,
      if (categoryId != null) 'category_id': categoryId,
      if (soldUnitCode != null) 'sold_unit_code': soldUnitCode,
      if (soldConversion != null) 'sold_conversion': soldConversion,
      if (soldUnitId != null) 'sold_unit_id': soldUnitId,
    };

// Offline packaging create (0094). shopItemUnitId is client-generated so
// the optimistic mirror row and the server row share one id.
Map<String, dynamic> buildCreateShopItemUnitParams({
  required String shopItemUnitId,
  required String shopItemId,
  required String unitCode,
  required num conversionToBase,
  num? salePrice,
}) =>
    <String, dynamic>{
      'shop_item_unit_id': shopItemUnitId,
      'shop_item_id': shopItemId,
      'unit_code': unitCode,
      'conversion_to_base': conversionToBase,
      if (salePrice != null) 'sale_price': salePrice,
    };

Map<String, dynamic> buildUpdatePartyParams({
  required String partyId,
  required String name,
  String? phone,
}) =>
    <String, dynamic>{
      'party_id': partyId,
      'name': name,
      if (phone != null) 'phone': phone,
    };

Map<String, dynamic> buildSetPartyActiveParams({
  required String partyId,
  required bool isActive,
}) =>
    <String, dynamic>{
      'party_id': partyId,
      'is_active': isActive,
    };

Map<String, dynamic> buildSetShopItemActiveParams({
  required String shopItemId,
  required bool isActive,
}) =>
    <String, dynamic>{
      'shop_item_id': shopItemId,
      'is_active': isActive,
    };
// ignore_for_file: use_null_aware_elements
