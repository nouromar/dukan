// Read-side abstraction over the local sqflite mirror tables.
// All daily-flow screens read through this when offline_mode=full;
// SWR caches stay in place for offline_mode=light.
//
// Methods return plain DTOs (LocalShopItem, LocalParty, etc) so
// the consumer screens don't depend on sqflite types. UPSERTs
// from the SyncEngine live in this file too — keeps the
// "things that touch local_* tables" surface in one place.

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:dukan/api/shop_api.dart' show ShopItemDetail, ShopItemAliasRow,
    ShopItemBarcodeRow, UnpaidInvoice;
import 'package:dukan/api/types.dart';
import 'package:dukan/storage/app_database.dart';

// ---------------------------------------------------------------------------
// DTOs
// ---------------------------------------------------------------------------

class LocalShopItem {
  const LocalShopItem({
    required this.shopItemId,
    required this.shopId,
    required this.itemId,
    required this.displayName,
    required this.categoryId,
    required this.baseUnitCode,
    required this.currentStock,
    required this.avgCost,
    required this.reorderThreshold,
    required this.isActive,
    required this.serverUpdatedAtMs,
  });

  final String shopItemId;
  final String shopId;
  final String? itemId;
  final String displayName;
  final String? categoryId;
  final String baseUnitCode;
  final num currentStock;
  final num avgCost;
  final num? reorderThreshold;
  final bool isActive;
  final int serverUpdatedAtMs;

  factory LocalShopItem._fromRow(Map<String, Object?> r) => LocalShopItem(
        // #378: sqflite type-affinity — INTEGER columns can come
        // back as `double` if anything ever wrote a non-int value
        // (e.g., JSON `1.0`). Cast via `num.toInt()` defensively
        // so we never throw "type 'double' is not a subtype of
        // type 'int' in type cast" on read.
        shopItemId: r['shop_item_id'] as String,
        shopId: r['shop_id'] as String,
        itemId: r['item_id'] as String?,
        displayName: r['display_name'] as String,
        categoryId: r['category_id'] as String?,
        baseUnitCode: r['base_unit_code'] as String,
        currentStock: r['current_stock'] as num,
        avgCost: r['avg_cost'] as num,
        reorderThreshold: r['reorder_threshold'] as num?,
        isActive: (r['is_active'] as num).toInt() == 1,
        serverUpdatedAtMs: (r['server_updated_at'] as num).toInt(),
      );
}

class LocalShopItemUnit {
  const LocalShopItemUnit({
    required this.shopItemUnitId,
    required this.shopItemId,
    required this.unitCode,
    required this.packagingLabel,
    required this.conversionToBase,
    required this.salePrice,
    required this.lastCost,
    required this.isDefaultSale,
    required this.isDefaultReceive,
    required this.isActive,
    required this.serverUpdatedAtMs,
    this.lastSaleQty,
    this.lastReceiveQty,
  });

  final String shopItemUnitId;
  final String shopItemId;
  final String unitCode;
  final String packagingLabel;
  final num conversionToBase;
  final num? salePrice;
  final num? lastCost;
  final bool isDefaultSale;
  final bool isDefaultReceive;
  final bool isActive;
  final int serverUpdatedAtMs;

  /// Slice 4: learned usual quantity per packaging (null until first used).
  final num? lastSaleQty;
  final num? lastReceiveQty;

  factory LocalShopItemUnit._fromRow(Map<String, Object?> r) =>
      LocalShopItemUnit(
        shopItemUnitId: r['shop_item_unit_id'] as String,
        shopItemId: r['shop_item_id'] as String,
        unitCode: r['unit_code'] as String,
        packagingLabel: r['packaging_label'] as String,
        conversionToBase: r['conversion_to_base'] as num,
        salePrice: r['sale_price'] as num?,
        lastCost: r['last_cost'] as num?,
        lastSaleQty: r['last_sale_qty'] as num?,
        lastReceiveQty: r['last_receive_qty'] as num?,
        isDefaultSale: (r['is_default_sale'] as num).toInt() == 1,
        isDefaultReceive: (r['is_default_receive'] as num).toInt() == 1,
        isActive: (r['is_active'] as num).toInt() == 1,
        serverUpdatedAtMs: (r['server_updated_at'] as num).toInt(),
      );
}

class LocalParty {
  const LocalParty({
    required this.partyId,
    required this.shopId,
    required this.name,
    required this.phone,
    required this.typeCode,
    required this.receivable,
    required this.payable,
    required this.isActive,
    required this.serverUpdatedAtMs,
  });

  final String partyId;
  final String shopId;
  final String name;
  final String? phone;
  final String typeCode;
  final num receivable;
  final num payable;
  final bool isActive;
  final int serverUpdatedAtMs;

  factory LocalParty._fromRow(Map<String, Object?> r) => LocalParty(
        partyId: r['party_id'] as String,
        shopId: r['shop_id'] as String,
        name: r['name'] as String,
        phone: r['phone'] as String?,
        typeCode: r['type_code'] as String,
        receivable: r['receivable'] as num,
        payable: r['payable'] as num,
        isActive: (r['is_active'] as num).toInt() == 1,
        serverUpdatedAtMs: (r['server_updated_at'] as num).toInt(),
      );
}

class LocalExpenseCategory {
  const LocalExpenseCategory({
    required this.categoryId,
    required this.shopId,
    required this.code,
    required this.name,
    required this.isActive,
  });

  final String categoryId;
  final String shopId;
  final String code;
  final String name;
  final bool isActive;

  factory LocalExpenseCategory._fromRow(Map<String, Object?> r) =>
      LocalExpenseCategory(
        categoryId: r['category_id'] as String,
        shopId: r['shop_id'] as String,
        code: r['code'] as String,
        name: r['name'] as String,
        isActive: (r['is_active'] as num).toInt() == 1,
      );
}

/// A product category from the local mirror. `shopId` is null for the
/// global, platform-curated categories and set for this shop's custom
/// ones (`isCustom`). Only the latter are owner-editable.
class LocalCategory {
  const LocalCategory({
    required this.categoryId,
    required this.shopId,
    required this.name,
    required this.isActive,
  });

  final String categoryId;
  final String? shopId;
  final String name;
  final bool isActive;

  bool get isCustom => shopId != null;

  factory LocalCategory._fromRow(Map<String, Object?> r) => LocalCategory(
        categoryId: r['category_id'] as String,
        shopId: r['shop_id'] as String?,
        name: r['name'] as String,
        isActive: (r['is_active'] as num).toInt() == 1,
      );
}

class LocalTransaction {
  const LocalTransaction({
    required this.txnId,
    required this.shopId,
    required this.typeCode,
    required this.occurredAtMs,
    required this.total,
    required this.partyId,
    required this.isVoided,
    required this.serverUpdatedAtMs,
    required this.payload,
    this.clientOpId,
  });

  final String txnId;
  final String shopId;
  final String typeCode;
  final int occurredAtMs;
  final num total;
  final String? partyId;
  final bool isVoided;
  final int serverUpdatedAtMs;

  /// Denormalized display payload (party_name, payment_method_code,
  /// lines_summary). Mirrors what `get_transactions_delta` returns
  /// for a single row.
  final Map<String, dynamic> payload;

  /// Set on optimistic rows (#385) so the server-side authoritative
  /// copy can replace this row when it arrives via delta sync. Also
  /// populated by the server payload itself (post-0071) so foreign
  /// devices can identify a row's origin.
  final String? clientOpId;

  /// True if this row was written optimistically at queue-enqueue
  /// time and hasn't been replaced by the server-authoritative copy
  /// yet. Drives the "Sale details syncing..." spinner on detail
  /// screens, etc.
  bool get isOptimistic => serverUpdatedAtMs == 0;

  factory LocalTransaction._fromRow(Map<String, Object?> r) {
    Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(
        jsonDecode(r['payload_json'] as String) as Map,
      );
    } catch (_) {
      payload = const <String, dynamic>{};
    }
    return LocalTransaction(
      txnId: r['txn_id'] as String,
      shopId: r['shop_id'] as String,
      typeCode: r['type_code'] as String,
      occurredAtMs: (r['occurred_at'] as num).toInt(),
      total: r['total'] as num,
      partyId: r['party_id'] as String?,
      isVoided: (r['is_voided'] as num).toInt() == 1,
      serverUpdatedAtMs: (r['server_updated_at'] as num).toInt(),
      payload: payload,
      clientOpId: r['client_op_id'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// Read-mostly accessor for the local mirror tables. `apply*` helpers
/// are the write side, called only by `SyncEngine` (full / delta /
/// realtime).
class LocalRepository {
  LocalRepository(this._database);

  final Future<AppDatabase> _database;

  Future<Database> get _db => _database.then((d) => d.db);

  // ---- Reads --------------------------------------------------------------

  /// Items matching [query] for [shopId]. Empty query → top 50 by
  /// name. Non-empty → contains-match on display_name OR any alias.
  /// Returns active items only.
  Future<List<LocalShopItem>> searchItems(
    String query, {
    required String shopId,
    int limit = 50,
    String rankBy = 'name',
  }) async {
    final db = await _db;
    final trimmed = query.trim();
    // Sale ranks "most / most-recently sold first"; everywhere else stays
    // alphabetical. Never-sold items (sale_count 0, last_sold_at NULL) fall to
    // the bottom under recency, which is what we want.
    final recency = rankBy == 'recency';
    if (trimmed.isEmpty) {
      // Simple ordered listing — caller (Sale grid) will overlay
      // favorites elsewhere.
      final rows = await db.query(
        'local_shop_item',
        where: 'shop_id = ? AND is_active = 1',
        whereArgs: [shopId],
        orderBy: recency
            ? 'sale_count DESC, last_sold_at DESC, display_name COLLATE NOCASE ASC'
            : 'display_name COLLATE NOCASE ASC',
        limit: limit,
      );
      return rows.map(LocalShopItem._fromRow).toList(growable: false);
    }
    // Match either display_name OR any alias. Aliases live in a
    // separate table; UNION-SELECT keeps it to one SQL roundtrip.
    final pattern = '%${trimmed.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final orderBy = recency
        ? 'si.sale_count DESC, si.last_sold_at DESC, si.display_name COLLATE NOCASE ASC'
        : 'si.display_name COLLATE NOCASE ASC';
    final rows = await db.rawQuery('''
      SELECT DISTINCT si.*
        FROM local_shop_item si
        LEFT JOIN local_shop_item_alias a
          ON a.shop_item_id = si.shop_item_id
       WHERE si.shop_id = ?
         AND si.is_active = 1
         AND (si.display_name LIKE ? COLLATE NOCASE
              OR a.alias LIKE ? COLLATE NOCASE)
       ORDER BY $orderBy
       LIMIT ?
    ''', [shopId, pattern, pattern, limit]);
    return rows.map(LocalShopItem._fromRow).toList(growable: false);
  }

  Future<LocalShopItem?> getShopItem(String shopItemId) async {
    final rows = await (await _db).query(
      'local_shop_item',
      where: 'shop_item_id = ?',
      whereArgs: [shopItemId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocalShopItem._fromRow(rows.first);
  }

  /// Slice 3: the supplier's usual items, most-recently-received first, for the
  /// Receive screen (`local_supplier_item`, mirrored from
  /// supplier_item_unit_cost). One row per item — a supplier may use several
  /// packagings; we surface the item ranked by its latest receive. v1 uses the
  /// item's default receive unit + shop-wide cost (supplier-scoped
  /// packaging/cost is a future refinement).
  Future<List<ItemSearchResult>> supplierBasket(
    String supplierId, {
    required String shopId,
    int limit = 50,
  }) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT si.*
        FROM local_shop_item si
        JOIN (
          SELECT u.shop_item_id, MAX(lsi.last_received_at) AS last_at
            FROM local_supplier_item lsi
            JOIN local_shop_item_unit u
              ON u.shop_item_unit_id = lsi.shop_item_unit_id
           WHERE lsi.party_id = ?
           GROUP BY u.shop_item_id
        ) b ON b.shop_item_id = si.shop_item_id
       WHERE si.shop_id = ? AND si.is_active = 1
       ORDER BY b.last_at DESC
       LIMIT ?
    ''', [supplierId, shopId, limit]);
    final out = <ItemSearchResult>[];
    for (final r in rows) {
      out.add(
        await toItemSearchResult(LocalShopItem._fromRow(r), screen: 'receive'),
      );
    }
    return out;
  }

  /// O(1) barcode → packaging lookup. Returns the unit row, not the
  /// item — callers walk to the item via `shop_item_id`.
  Future<LocalShopItemUnit?> lookupBarcode(String code) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT siu.*
        FROM local_shop_item_barcode b
        JOIN local_shop_item_unit siu
          ON siu.shop_item_unit_id = b.shop_item_unit_id
       WHERE b.barcode = ?
       LIMIT 1
    ''', [code]);
    if (rows.isEmpty) return null;
    return LocalShopItemUnit._fromRow(rows.first);
  }

  /// All active packagings for an item, sorted by conversion_to_base
  /// ASC (smallest first — typical till display order).
  Future<List<LocalShopItemUnit>> packagingsForItem(String shopItemId) async {
    final rows = await (await _db).query(
      'local_shop_item_unit',
      where: 'shop_item_id = ? AND is_active = 1',
      whereArgs: [shopItemId],
      orderBy: 'conversion_to_base ASC',
    );
    return rows.map(LocalShopItemUnit._fromRow).toList(growable: false);
  }

  /// All active items for [shopId] — used by the Products list when
  /// offline_mode = full. Sorted alphabetically.
  Future<List<LocalShopItem>> allActiveItems(String shopId) async {
    final rows = await (await _db).query(
      'local_shop_item',
      where: 'shop_id = ? AND is_active = 1',
      whereArgs: [shopId],
      orderBy: 'display_name COLLATE NOCASE ASC',
    );
    return rows.map(LocalShopItem._fromRow).toList(growable: false);
  }

  /// Low-stock rows computed straight from the mirror (offline Low-stock
  /// report). Matches the server rule: low = at/below the reorder threshold,
  /// or below 1 when no threshold is set. current_stock already reflects
  /// optimistic sale/receive bumps. base_unit_code doubles as the label
  /// locally (we don't mirror unit labels — same as the other local reads).
  /// Most-below-threshold first.
  Future<List<LowStockRow>> lowStockLocal(String shopId) async {
    final rows = await (await _db).rawQuery(
      '''
      SELECT shop_item_id, display_name, current_stock,
             reorder_threshold, base_unit_code
        FROM local_shop_item
       WHERE shop_id = ?
         AND is_active = 1
         AND (
              (reorder_threshold IS NOT NULL AND current_stock <= reorder_threshold)
           OR (reorder_threshold IS NULL AND current_stock < 1)
         )
       ORDER BY (current_stock - COALESCE(reorder_threshold, 1)) ASC,
                display_name COLLATE NOCASE ASC
      ''',
      [shopId],
    );
    return rows
        .map((r) => LowStockRow(
              shopItemId: r['shop_item_id'] as String,
              displayName: r['display_name'] as String,
              currentStock: (r['current_stock'] as num).toDouble(),
              reorderThreshold: (r['reorder_threshold'] as num?)?.toDouble(),
              baseUnitCode: r['base_unit_code'] as String,
              baseUnitLabel: r['base_unit_code'] as String,
            ))
        .toList(growable: false);
  }

  /// All active parties for [shopId] filtered to [typeCode]. Used by
  /// the People screen + the lookup pickers when offline_mode = full.
  Future<List<LocalParty>> allActiveParties(
    String shopId, {
    required String typeCode,
  }) async {
    final rows = await (await _db).query(
      'local_party',
      where: 'shop_id = ? AND type_code = ? AND is_active = 1',
      whereArgs: [shopId, typeCode],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(LocalParty._fromRow).toList(growable: false);
  }

  /// Alias rows for an item — used by Product Detail when composing
  /// the bootstrap from local data instead of the get_shop_item RPC.
  Future<List<LocalShopItemAlias>> aliasesForItem(String shopItemId) async {
    final rows = await (await _db).query(
      'local_shop_item_alias',
      where: 'shop_item_id = ?',
      whereArgs: [shopItemId],
    );
    return rows
        .map((r) => LocalShopItemAlias(
              shopItemId: r['shop_item_id'] as String,
              alias: r['alias'] as String,
              isDisplay: (r['is_display'] as int) == 1,
            ))
        .toList(growable: false);
  }

  /// Barcode rows attached to packagings of [shopItemId].
  Future<List<LocalShopItemBarcode>> barcodesForItem(String shopItemId) async {
    final rows = await (await _db).rawQuery('''
      SELECT b.* FROM local_shop_item_barcode b
      JOIN local_shop_item_unit u ON u.shop_item_unit_id = b.shop_item_unit_id
      WHERE u.shop_item_id = ?
    ''', [shopItemId]);
    return rows
        .map((r) => LocalShopItemBarcode(
              barcode: r['barcode'] as String,
              shopItemUnitId: r['shop_item_unit_id'] as String,
              isPrimary: (r['is_primary'] as int) == 1,
            ))
        .toList(growable: false);
  }

  // ---- Converters → public DTOs --------------------------------------------
  // Screens consume ItemSearchResult / PartySearchResult / etc.
  // Converters keep the screen render path identical regardless of
  // whether the data came from network or local.

  /// Map a LocalShopItem + its default packaging into the shape Sale
  /// / Receive search-results expect. [screen] picks the default
  /// packaging by `is_default_sale` (Sale) or `is_default_receive`
  /// (Receive).
  Future<ItemSearchResult> toItemSearchResult(
    LocalShopItem item, {
    required String screen,
  }) async {
    final packagings = await packagingsForItem(item.shopItemId);
    LocalShopItemUnit? defaultUnit;
    for (final p in packagings) {
      if (screen == 'sale' && p.isDefaultSale) {
        defaultUnit = p;
        break;
      }
      if (screen == 'receive' && p.isDefaultReceive) {
        defaultUnit = p;
        break;
      }
    }
    // Fallback: base packaging (conversion = 1) if no default flagged.
    defaultUnit ??= packagings.firstWhere(
      (p) => p.conversionToBase == 1,
      orElse: () =>
          packagings.isNotEmpty ? packagings.first : _emptyUnit(item),
    );
    return ItemSearchResult(
      shopItemId: item.shopItemId,
      itemId: item.itemId,
      displayName: item.displayName,
      baseUnitCode: item.baseUnitCode,
      baseUnitLabel: item.baseUnitCode, // we don't cache unit label
      defaultShopItemUnitId: defaultUnit.shopItemUnitId,
      defaultUnitCode: defaultUnit.unitCode,
      defaultUnitLabel: defaultUnit.packagingLabel,
      defaultUnitConversionToBase: defaultUnit.conversionToBase.toDouble(),
      defaultUnitSalePrice: defaultUnit.salePrice?.toDouble(),
      defaultUnitLastCost: defaultUnit.lastCost?.toDouble(),
      currentStock: item.currentStock.toDouble(),
      reorderThreshold: item.reorderThreshold?.toDouble(),
      packagingLabel: defaultUnit.packagingLabel,
      isActivated: true, // local rows are by definition activated
      rankReason: null,
      // Slice 4: learned usual quantity for this screen's context.
      learnedQty: screen == 'sale'
          ? defaultUnit.lastSaleQty
          : defaultUnit.lastReceiveQty,
    );
  }

  LocalShopItemUnit _emptyUnit(LocalShopItem item) => LocalShopItemUnit(
        shopItemUnitId: '${item.shopItemId}-base',
        shopItemId: item.shopItemId,
        unitCode: item.baseUnitCode,
        packagingLabel: item.baseUnitCode,
        conversionToBase: 1,
        salePrice: null,
        lastCost: null,
        isDefaultSale: true,
        isDefaultReceive: true,
        isActive: true,
        serverUpdatedAtMs: 0,
      );

  /// LocalParty → PartySearchResult.
  PartySearchResult toPartySearchResult(LocalParty p) => PartySearchResult(
        id: p.partyId,
        name: p.name,
        phone: p.phone,
        typeCode: p.typeCode,
        receivable: p.receivable.toDouble(),
        payable: p.payable.toDouble(),
      );

  /// LocalExpenseCategory → ExpenseCategoryOption.
  ExpenseCategoryOption toExpenseCategoryOption(LocalExpenseCategory c) =>
      ExpenseCategoryOption(id: c.categoryId, code: c.code, name: c.name);

  /// Compose a full `ShopItemDetail` from local rows. Used by the
  /// Product Detail screen when offline_mode = full. Aliases'
  /// `aliasId` + `languageCode` aren't mirrored (server-only fields);
  /// the edit affordances on the detail screen still go online so
  /// missing IDs only block the inline view, not edit/save.
  Future<ShopItemDetail?> getShopItemDetail(String shopItemId) async {
    final item = await getShopItem(shopItemId);
    if (item == null) return null;
    final unitRows = await packagingsForItem(shopItemId);
    final aliasRows = await aliasesForItem(shopItemId);
    final barcodeRows = await barcodesForItem(shopItemId);
    final projected = await projectedStock(shopItemId);
    final summary = await toShopItemSummary(
      item,
      projectionDelta: projected - item.currentStock,
    );
    return ShopItemDetail(
      header: summary,
      units: unitRows
          .map((u) => ShopItemUnitDetail(
                shopItemUnitId: u.shopItemUnitId,
                itemUnitId: null,
                unitCode: u.unitCode,
                unitLabel: u.unitCode,
                packagingLabel: u.packagingLabel,
                conversionToBase: u.conversionToBase.toDouble(),
                salePrice: u.salePrice?.toDouble(),
                lastCost: u.lastCost?.toDouble(),
                isDefaultSale: u.isDefaultSale,
                isDefaultReceive: u.isDefaultReceive,
                isBaseUnit: u.conversionToBase == 1,
                isActive: u.isActive,
              ))
          .toList(growable: false),
      aliases: aliasRows
          .map((a) => ShopItemAliasRow(
                aliasId: '',
                aliasText: a.alias,
                languageCode: null,
                isDisplay: a.isDisplay,
              ))
          .toList(growable: false),
      barcodes: barcodeRows
          .map((b) => ShopItemBarcodeRow(
                barcodeId: '',
                shopItemUnitId: b.shopItemUnitId,
                barcode: b.barcode,
                isPrimary: b.isPrimary,
              ))
          .toList(growable: false),
    );
  }

  /// Map a LocalShopItem (+ its packagings) into the
  /// `ShopItemSummary` shape the Products list expects. The
  /// `defaultSalePrice` / `anyPriceSet` flags fall out of the unit
  /// rows so the "no price yet" indicator behaves the same way
  /// offline.
  Future<ShopItemSummary> toShopItemSummary(
    LocalShopItem item, {
    num projectionDelta = 0,
  }) async {
    final units = await packagingsForItem(item.shopItemId);
    LocalShopItemUnit? defaultSale;
    LocalShopItemUnit? defaultReceive;
    LocalShopItemUnit? baseUnit;
    var anyPriceSet = false;
    for (final u in units) {
      if (u.salePrice != null && u.salePrice != 0) anyPriceSet = true;
      if (u.isDefaultSale) defaultSale = u;
      if (u.isDefaultReceive) defaultReceive = u;
      if (u.conversionToBase == 1) baseUnit = u;
    }
    final preferred = defaultSale ?? baseUnit;
    // Stock on the Products list renders in the default *receive* packaging
    // when the shop has one that isn't the base unit; otherwise base.
    final receiveUnit = defaultReceive ?? baseUnit;
    final showReceivePack =
        receiveUnit != null && receiveUnit.conversionToBase != 1;
    // Resolve the category display name from the mirror so the Products list
    // subtitle and the detail screen's Category tile show the real category
    // (not "Other") when offline_mode = full. Without this the mirror path
    // reported a null name and every item read as uncategorized.
    final categoryName = await _localCategoryName(item.categoryId);
    return ShopItemSummary(
      shopItemId: item.shopItemId,
      itemId: item.itemId,
      displayName: item.displayName,
      categoryName: categoryName,
      baseUnitCode: item.baseUnitCode,
      baseUnitLabel: item.baseUnitCode,
      // Show projected stock (mirror + pending queued deltas) so a queued
      // sale/receive/adjustment reflects instantly; sync reconciles.
      currentStock: (item.currentStock + projectionDelta).toDouble(),
      reorderThreshold: item.reorderThreshold?.toDouble(),
      unitCount: units.length,
      isActive: item.isActive,
      defaultSalePrice: preferred?.salePrice?.toDouble(),
      anyPriceSet: anyPriceSet,
      defaultReceivePackagingLabel:
          showReceivePack ? receiveUnit.packagingLabel : null,
      defaultReceiveConversion:
          showReceivePack ? receiveUnit.conversionToBase.toDouble() : null,
    );
  }

  /// Sum of pending projection deltas per shop_item across the (single,
  /// selected) shop's mirror — one query so the product list can show
  /// projected stock without an N-item lookup. Items with no pending
  /// delta are absent from the map (treat as 0).
  Future<Map<String, num>> projectionDeltas() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT shop_item_id, SUM(delta) AS d '
      'FROM local_stock_projection GROUP BY shop_item_id',
    );
    return {
      for (final r in rows) r['shop_item_id'] as String: (r['d'] as num?) ?? 0,
    };
  }

  /// Parties matching [query] within [shopId] filtered to
  /// [typeCode] ('customer' or 'supplier'). Empty query → first 50
  /// by name.
  Future<List<LocalParty>> searchParties(
    String query, {
    required String shopId,
    required String typeCode,
    int limit = 50,
    String rankBy = 'balance',
  }) async {
    final trimmed = query.trim();
    final db = await _db;
    final hasQuery = trimmed.isNotEmpty;
    final pattern = hasQuery
        ? '%${trimmed.replaceAll('%', r'\%').replaceAll('_', r'\_')}%'
        : null;

    if (rankBy == 'recency') {
      // Recents first, then name. The mirror has no usage table, but
      // local_transaction carries party_id + occurred_at — enough to rank
      // recents offline (SQLite sorts NULL last under DESC, so parties with
      // no transactions fall to the bottom).
      final nameClause = hasQuery ? ' AND p.name LIKE ? COLLATE NOCASE' : '';
      final args = <Object?>[shopId, shopId, typeCode];
      if (hasQuery) args.add(pattern);
      args.add(limit);
      final rows = await db.rawQuery(
        'SELECT p.* FROM local_party p '
        'LEFT JOIN (SELECT party_id, MAX(occurred_at) AS last_at '
        'FROM local_transaction WHERE shop_id = ? AND party_id IS NOT NULL '
        'GROUP BY party_id) t ON t.party_id = p.party_id '
        'WHERE p.shop_id = ? AND p.type_code = ? AND p.is_active = 1$nameClause '
        'ORDER BY t.last_at DESC, p.name COLLATE NOCASE ASC LIMIT ?',
        args,
      );
      return rows.map(LocalParty._fromRow).toList(growable: false);
    }

    // Default ('balance'): people with the most outstanding balance first
    // (customers by receivable, suppliers by payable), then name — matching
    // the server and the People-list default. (people_screen re-sorts in
    // memory, so changing this shared order is safe for it.)
    final balanceCol = typeCode == 'customer' ? 'receivable' : 'payable';
    final where = hasQuery
        ? 'shop_id = ? AND type_code = ? AND is_active = 1 AND name LIKE ? COLLATE NOCASE'
        : 'shop_id = ? AND type_code = ? AND is_active = 1';
    final whereArgs = hasQuery
        ? <Object?>[shopId, typeCode, pattern]
        : <Object?>[shopId, typeCode];
    final rows = await db.query(
      'local_party',
      where: where,
      whereArgs: whereArgs,
      orderBy: '$balanceCol DESC, name COLLATE NOCASE ASC',
      limit: limit,
    );
    return rows.map(LocalParty._fromRow).toList(growable: false);
  }

  Future<List<LocalExpenseCategory>> expenseCategories({
    required String shopId,
  }) async {
    final rows = await (await _db).query(
      'local_expense_category',
      where: 'shop_id = ? AND is_active = 1',
      whereArgs: [shopId],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(LocalExpenseCategory._fromRow).toList(growable: false);
  }

  /// Product categories for the Manage Categories screen + pickers:
  /// the global set (shop_id NULL) plus this shop's custom ones. Global
  /// first, then alphabetical.
  Future<List<LocalCategory>> productCategories({
    required String shopId,
    bool includeHidden = false,
  }) async {
    final db = await _db;
    final activeClause = includeHidden ? '' : ' AND is_active = 1';
    final rows = await db.query(
      'local_category',
      where:
          'parent_id IS NULL AND (shop_id IS NULL OR shop_id = ?)$activeClause',
      whereArgs: [shopId],
      orderBy: '(shop_id IS NOT NULL) ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(LocalCategory._fromRow).toList(growable: false);
  }

  /// Recent sales — most-recent first. Used by Sales History.
  Future<List<LocalTransaction>> historySales({
    required String shopId,
    int limit = 50,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? partyId,
  }) =>
      _historyOfType(
        shopId: shopId,
        typeCode: 'sale',
        limit: limit,
        dateFrom: dateFrom,
        dateTo: dateTo,
        partyId: partyId,
      );

  /// Recent receives — most-recent first. Used by Receive History.
  Future<List<LocalTransaction>> historyReceives({
    required String shopId,
    int limit = 50,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? partyId,
  }) =>
      _historyOfType(
        shopId: shopId,
        typeCode: 'receive',
        limit: limit,
        dateFrom: dateFrom,
        dateTo: dateTo,
        partyId: partyId,
      );

  /// Recent payments — most-recent first. Used by Payment History.
  Future<List<LocalTransaction>> historyPayments({
    required String shopId,
    int limit = 50,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? partyId,
    String? direction,
  }) async {
    final where = <String>['shop_id = ?', "type_code = 'payment'"];
    final args = <Object?>[shopId];
    if (dateFrom != null) {
      where.add('occurred_at >= ?');
      args.add(dateFrom.millisecondsSinceEpoch);
    }
    if (dateTo != null) {
      where.add('occurred_at <= ?');
      args.add(dateTo.millisecondsSinceEpoch);
    }
    if (partyId != null) {
      where.add('party_id = ?');
      args.add(partyId);
    }
    final rows = await (await _db).query(
      'local_transaction',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    final all = rows.map(LocalTransaction._fromRow).toList(growable: false);
    if (direction == null) return all;
    return all
        .where((t) => (t.payload['direction'] as String?) == direction)
        .toList(growable: false);
  }

  /// Recent expenses — most-recent first. Used by Expense History.
  Future<List<LocalTransaction>> historyExpenses({
    required String shopId,
    int limit = 50,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) =>
      _historyOfType(
        shopId: shopId,
        typeCode: 'expense',
        limit: limit,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

  Future<List<LocalTransaction>> _historyOfType({
    required String shopId,
    required String typeCode,
    required int limit,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? partyId,
  }) async {
    final where = <String>['shop_id = ?', 'type_code = ?'];
    final args = <Object?>[shopId, typeCode];
    if (dateFrom != null) {
      where.add('occurred_at >= ?');
      args.add(dateFrom.millisecondsSinceEpoch);
    }
    if (dateTo != null) {
      where.add('occurred_at <= ?');
      args.add(dateTo.millisecondsSinceEpoch);
    }
    if (partyId != null) {
      where.add('party_id = ?');
      args.add(partyId);
    }
    final rows = await (await _db).query(
      'local_transaction',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    return rows.map(LocalTransaction._fromRow).toList(growable: false);
  }

  /// Read one transaction by txn_id. Returns null if it hasn't been
  /// synced into the local mirror yet (queued post awaiting drain).
  Future<LocalTransaction?> getTransaction(String txnId) async {
    final rows = await (await _db).query(
      'local_transaction',
      where: 'txn_id = ?',
      whereArgs: [txnId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocalTransaction._fromRow(rows.first);
  }

  /// True when ANY local mirror row exists for this shop. Used by
  /// the first-time-setup boundary to decide whether to render the
  /// blocking "connect to load" card vs. let the screen through.
  Future<bool> hasAnyData(String shopId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT 1 FROM local_shop_item WHERE shop_id = ? LIMIT 1',
      [shopId],
    );
    return rows.isNotEmpty;
  }

  /// LocalTransaction → SaleSummary. Pulls denormalized
  /// party_name + payment_method + voided flags from payload.
  SaleSummary toSaleSummary(LocalTransaction t) => SaleSummary(
        txnId: t.txnId,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(t.occurredAtMs),
        // #385-fixup: server's _build_transactions_payload doesn't
        // include posted_at — only server_updated_at_ms. Fall back to
        // that so the void affordance (which gates on postedAt) shows
        // up once the server has acknowledged the row. Optimistic
        // pre-sync rows still resolve to null (serverUpdatedAtMs=0),
        // which is correct: can't void a sale the server hasn't seen.
        postedAt: t.payload['posted_at'] != null
            ? DateTime.tryParse(t.payload['posted_at'] as String)
            : (t.serverUpdatedAtMs > 0
                ? DateTime.fromMillisecondsSinceEpoch(t.serverUpdatedAtMs)
                : null),
        partyId: t.partyId,
        partyName: t.payload['party_name'] as String?,
        totalAmount: t.total.toDouble(),
        // paid_amount drives the cash/debt split on the receipt. The
        // server payload carries it (migration 0089); the `?? total`
        // fallback only fires for rows synced before that migration —
        // they self-heal on the next full sync. Defaulting to `total`
        // there means a stale credit sale reads as cash until re-sync,
        // which is the lesser evil (it never fabricates a phantom debt
        // on a genuine cash sale).
        paidAmount: (t.payload['paid_amount'] as num?)?.toDouble() ??
            t.total.toDouble(),
        paymentMethodCode: t.payload['payment_method_code'] as String?,
        isVoided: t.isVoided,
        reversalTxnId: t.payload['reversal_txn_id'] as String?,
        voidedAt: t.payload['voided_at'] == null
            ? null
            : DateTime.tryParse(t.payload['voided_at'] as String),
        // The attached bono (receives). document_id keys the local cache (offline
        // + instant); document_path lets View bono sign a Storage URL when the
        // cache is empty — e.g. after a reinstall, where the mirror is the only
        // source. Both ride the sync payload (0110).
        documentId: t.payload['document_id'] as String?,
        documentPath: t.payload['document_path'] as String?,
      );

  /// LocalTransaction → ReceiveSummary (typedef for SaleSummary).
  ReceiveSummary toReceiveSummary(LocalTransaction t) => toSaleSummary(t);

  /// LocalTransaction → PaymentSummary.
  PaymentSummary toPaymentSummary(LocalTransaction t) => PaymentSummary(
        paymentId: t.txnId,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(t.occurredAtMs),
        createdAt: DateTime.fromMillisecondsSinceEpoch(t.occurredAtMs),
        amount: t.total.toDouble(),
        direction: (t.payload['direction'] as String?) ?? 'I',
        partyId: t.partyId,
        partyName: t.payload['party_name'] as String?,
        paymentMethodCode: t.payload['payment_method_code'] as String?,
        notes: t.payload['notes'] as String?,
        isRefund: t.payload['is_refund'] as bool? ?? false,
        // A walk-in cash sale's till-cash leg is stamped `<op>:payment` by
        // post_sale (0087). The server column isn't mirrored, so derive it
        // from the client_op_id the mirror already carries.
        isSettlementLeg: _isSettlementLegOp(t.clientOpId),
      );

  /// True when a mirrored payment row is the till-cash leg of a sale/receive
  /// (post_sale/post_receive stamp it `<base>:payment`, migration 0087).
  static bool _isSettlementLegOp(String? clientOpId) =>
      clientOpId != null && clientOpId.endsWith(':payment');

  /// Optimistically flag a local transaction as voided so the receipt +
  /// history show "voided" immediately, before the queued void_sale drains
  /// and the authoritative server payload syncs back. Stock / receivable
  /// reversal is applied by the server on drain (and reconciled on sync).
  /// Flag a transaction voided in the mirror AND reverse the stock + party
  /// balance the original post moved, so Products and the customers/suppliers
  /// lists reflect the void instantly — especially offline, where nothing
  /// syncs until reconnect (previously they stayed stale, showing the sold
  /// stock as gone and the debt as still owed until the next sync).
  ///
  /// Idempotent: a transaction already flagged voided is a no-op, so a
  /// re-drain or a double-call can never double-restore. And the reversal is
  /// only ever an INTERIM correction — the next items/parties sync sets
  /// absolute truth (which already includes the server's reversing entry), so
  /// any slip self-heals and can never accumulate.
  Future<void> applyOptimisticVoid(String txnId) async {
    final t = await getTransaction(txnId);
    if (t == null || t.isVoided) return;
    final db = await _db;
    await db.update(
      'local_transaction',
      {'is_voided': 1},
      where: 'txn_id = ?',
      whereArgs: [txnId],
    );
    // Best-effort reversal of the projections the post bumped. Wrapped so a
    // malformed payload never blocks the void flag (sync reconciles anyway).
    try {
      final summary = t.payload['lines_summary'];
      final lines = <ProjectionLine>[
        if (summary is List)
          for (final raw in summary)
            if (raw is Map &&
                raw['shop_item_unit_id'] != null &&
                raw['quantity'] is num)
              ProjectionLine(
                shopItemUnitId: raw['shop_item_unit_id'] as String,
                quantity: raw['quantity'] as num,
                // Reverse the original movement: a sale removed stock (restore
                // +1); a receive added it (remove -1).
                direction: t.typeCode == 'receive' ? -1 : 1,
              ),
      ];
      final partyId = t.partyId;
      switch (t.typeCode) {
        case 'sale':
          await applyOptimisticStockForLines(lines: lines);
          // A debt sale charged the customer receivable += total (a cash sale
          // has no party); voiding clears it.
          if (partyId != null) {
            await applyOptimisticPartyPayment(
              partyId: partyId,
              direction: 'I',
              amount: t.total,
            );
          }
        case 'receive':
          await applyOptimisticStockForLines(lines: lines);
          // A receive charged the supplier payable += total; voiding clears it.
          if (partyId != null) {
            await applyOptimisticPartyPayment(
              partyId: partyId,
              direction: 'O',
              amount: t.total,
            );
          }
        case 'payment':
          // A payment reduced the party balance by amount; voiding restores it.
          final direction = t.payload['direction'] as String?;
          if (partyId != null && direction != null) {
            await applyOptimisticPartyCharge(
              partyId: partyId,
              direction: direction,
              amount: t.total,
            );
          }
        // expense: no stock, no party balance — the void flag is enough.
      }
    } catch (_) {
      // Best-effort; the next items/parties sync sets absolute truth.
    }
  }

  /// Read a single payment's detail from the local mirror (offline-first,
  /// mirrors getTransaction + toSaleSummary). Payments live in
  /// `local_transaction` with type_code='payment'; the header fields all
  /// come from the denormalized payload. Allocations are NOT mirrored, so
  /// the caller renders the "Settled" section from its empty state offline.
  /// Returns null when the payment isn't in the mirror.
  Future<PaymentDetail?> getPaymentDetailLocal(String txnId) async {
    final t = await getTransaction(txnId);
    if (t == null || t.typeCode != 'payment') return null;
    final at = DateTime.fromMillisecondsSinceEpoch(t.occurredAtMs);
    return PaymentDetail(
      paymentId: t.txnId,
      occurredAt: at,
      createdAt: at,
      partyId: t.partyId,
      partyName: t.payload['party_name'] as String?,
      direction: (t.payload['direction'] as String?) ?? 'I',
      amount: t.total.toDouble(),
      paymentMethodCode: t.payload['payment_method_code'] as String?,
      notes: t.payload['notes'] as String?,
      isVoided: t.isVoided,
      isRefund: t.payload['is_refund'] as bool? ?? false,
      // Populate the settlement-leg flag (the online get_payment sets it too)
      // so the detail screen hides the standalone VOID on a sale's cash leg.
      isSettlementLeg: _isSettlementLegOp(t.clientOpId),
      clientOpId: t.clientOpId,
    );
  }

  /// The originating sale/receive txn_id for a settlement leg, resolved locally
  /// from its `<base>:payment` client_op_id (the sale shares `<base>`). Null
  /// when the leg has no client_op_id or the sale isn't in the mirror.
  Future<String?> settlementLegSourceTxnId(String? legClientOpId) async {
    if (legClientOpId == null || !legClientOpId.endsWith(':payment')) {
      return null;
    }
    final base = legClientOpId.substring(
      0,
      legClientOpId.length - ':payment'.length,
    );
    final db = await _db;
    final rows = await db.query(
      'local_transaction',
      columns: ['txn_id'],
      where: "client_op_id = ? AND type_code IN ('sale','receive')",
      whereArgs: [base],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['txn_id'] as String;
  }

  /// Read a single expense's detail from the local mirror (offline-first,
  /// mirrors getPaymentDetailLocal). Expenses live in `local_transaction`
  /// with type_code='expense'; all header fields come from the payload.
  /// Returns null when the expense isn't in the mirror.
  Future<ExpenseSummary?> getExpenseDetailLocal(String txnId) async {
    final t = await getTransaction(txnId);
    if (t == null || t.typeCode != 'expense') return null;
    final at = DateTime.fromMillisecondsSinceEpoch(t.occurredAtMs);
    return ExpenseSummary(
      txnId: t.txnId,
      occurredAt: at,
      postedAt: at,
      amount: t.total.toDouble(),
      paymentMethodCode: t.payload['payment_method_code'] as String?,
      categoryId: t.payload['category_id'] as String?,
      categoryName: t.payload['category_name'] as String?,
      notes: t.payload['notes'] as String?,
      isVoided: t.isVoided,
    );
  }

  /// LocalTransaction → ExpenseSummary.
  ExpenseSummary toExpenseSummary(LocalTransaction t) => ExpenseSummary(
        txnId: t.txnId,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(t.occurredAtMs),
        postedAt: DateTime.fromMillisecondsSinceEpoch(t.occurredAtMs),
        amount: t.total.toDouble(),
        paymentMethodCode: t.payload['payment_method_code'] as String?,
        categoryId: t.payload['category_id'] as String?,
        categoryName: t.payload['category_name'] as String?,
        notes: t.payload['notes'] as String?,
      );

  /// Lines for a sale txn, rendered from the denormalized
  /// `lines_summary` array stored in payload_json (server-side
  /// key from `_build_transactions_payload`). Falls back to
  /// `lines` for backwards compat with any older payload shapes
  /// optimistically written before #385. Returns empty list if
  /// the row isn't in the local mirror or carries no lines.
  Future<List<SaleLineDetail>> saleLinesFromLocal(String txnId) async {
    final t = await getTransaction(txnId);
    if (t == null) return const [];
    final raw = t.payload['lines_summary'] ?? t.payload['lines'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => SaleLineDetail.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  }

  /// #385-fixup: receive detail screen reads via this alias.
  /// `ReceiveLineDetail` is a typedef for `SaleLineDetail`, so the
  /// underlying logic and lines_summary payload shape is identical.
  Future<List<ReceiveLineDetail>> receiveLinesFromLocal(String txnId) =>
      saleLinesFromLocal(txnId);

  /// Effective stock for an item, taking in-flight queued posts
  /// into account. `current_stock` from local_shop_item plus the
  /// sum of all projection deltas (negative for sales, positive
  /// for receives).
  Future<num> projectedStock(String shopItemId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        (SELECT current_stock FROM local_shop_item
           WHERE shop_item_id = ?) AS current_stock,
        COALESCE(
          (SELECT SUM(delta) FROM local_stock_projection
             WHERE shop_item_id = ?), 0
        ) AS projection
    ''', [shopItemId, shopItemId]);
    if (rows.isEmpty) return 0;
    final base = (rows.first['current_stock'] as num?) ?? 0;
    final delta = (rows.first['projection'] as num?) ?? 0;
    return base + delta;
  }

  // ---- Writes (called by SyncEngine) ---------------------------------------

  /// Upsert one items_payload (from `get_shop_full_sync` or
  /// `get_shop_items_delta`). Handles items, units, aliases, and
  /// barcodes in one transaction. Tombstones (is_active=false rows
  /// from delta) cascade through as updates — the rows stay in the
  /// mirror so foreign references don't break, just flagged inactive.
  Future<void> applyItemsPayload(Map<String, dynamic> payload) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final raw in (payload['items'] as List? ?? const [])) {
        if (raw is! Map) continue;
        await txn.insert(
          'local_shop_item',
          {
            'shop_item_id': raw['shop_item_id'],
            'shop_id': raw['shop_id'],
            'item_id': raw['item_id'],
            'display_name': raw['display_name'],
            'category_id': raw['category_id'],
            'base_unit_code': raw['base_unit_code'],
            'current_stock': raw['current_stock'],
            'avg_cost': raw['avg_cost'],
            'reorder_threshold': raw['reorder_threshold'],
            // Sale recency (0079): server's combined cross-device values.
            // Replace semantics mean a sync overwrites any optimistic local
            // bump with the authoritative count — by design, no double-count.
            'last_sold_at': raw['last_sold_at_ms'],
            'sale_count': raw['sale_count'] ?? 0,
            'is_active': (raw['is_active'] == true) ? 1 : 0,
            'updated_at': raw['server_updated_at_ms'],
            'server_updated_at': raw['server_updated_at_ms'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final raw in (payload['units'] as List? ?? const [])) {
        if (raw is! Map) continue;
        await txn.insert(
          'local_shop_item_unit',
          {
            'shop_item_unit_id': raw['shop_item_unit_id'],
            'shop_item_id': raw['shop_item_id'],
            'unit_code': raw['unit_code'],
            'packaging_label': raw['packaging_label'],
            'conversion_to_base': raw['conversion_to_base'],
            'sale_price': raw['sale_price'],
            'last_cost': raw['last_cost'],
            // Slice 4: learned usual quantity per packaging (0080).
            'last_sale_qty': raw['last_sale_qty'],
            'last_receive_qty': raw['last_receive_qty'],
            'is_default_sale': (raw['is_default_sale'] == true) ? 1 : 0,
            'is_default_receive': (raw['is_default_receive'] == true) ? 1 : 0,
            'is_active': (raw['is_active'] == true) ? 1 : 0,
            'server_updated_at': raw['server_updated_at_ms'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      // Aliases: delta-sync rows are server snapshots. For full_sync
      // we get every alias; for delta we get only changed rows.
      // Replace semantics are correct in both cases (PK = (shop_item_id, alias)).
      for (final raw in (payload['aliases'] as List? ?? const [])) {
        if (raw is! Map) continue;
        await txn.insert(
          'local_shop_item_alias',
          {
            'shop_item_id': raw['shop_item_id'],
            'alias': raw['alias'],
            'is_display': (raw['is_display'] == true) ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final raw in (payload['barcodes'] as List? ?? const [])) {
        if (raw is! Map) continue;
        await txn.insert(
          'local_shop_item_barcode',
          {
            'barcode': raw['barcode'],
            'shop_item_unit_id': raw['shop_item_unit_id'],
            'is_primary': (raw['is_primary'] == true) ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      // Slice 3: supplier baskets (0080). Replace semantics overwrite any
      // optimistic bump with the authoritative server value.
      for (final raw in (payload['supplier_items'] as List? ?? const [])) {
        if (raw is! Map) continue;
        await txn.insert(
          'local_supplier_item',
          {
            'party_id': raw['party_id'],
            'shop_item_unit_id': raw['shop_item_unit_id'],
            'shop_id': raw['shop_id'],
            'last_unit_cost': raw['last_unit_cost'],
            'last_received_at': raw['last_received_at_ms'],
            'server_updated_at': raw['server_updated_at_ms'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> applyPartiesPayload(Map<String, dynamic> payload) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final raw in (payload['parties'] as List? ?? const [])) {
        if (raw is! Map) continue;
        await txn.insert(
          'local_party',
          {
            'party_id': raw['party_id'],
            'shop_id': raw['shop_id'],
            'name': raw['name'],
            'phone': raw['phone'],
            'type_code': raw['type_code'],
            'receivable': raw['receivable'],
            'payable': raw['payable'],
            'is_active': (raw['is_active'] == true) ? 1 : 0,
            'server_updated_at': raw['server_updated_at_ms'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> applyCategoriesPayload(Map<String, dynamic> payload) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final raw in (payload['expense_categories'] as List? ?? const [])) {
        if (raw is! Map) continue;
        await txn.insert(
          'local_expense_category',
          {
            'category_id': raw['category_id'],
            'shop_id': raw['shop_id'],
            'code': raw['code'],
            'name': raw['name'],
            'is_active': (raw['is_active'] == true) ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final raw in (payload['categories'] as List? ?? const [])) {
        if (raw is! Map) continue;
        await txn.insert(
          'local_category',
          {
            'category_id': raw['id'],
            'shop_id': raw['shop_id'],
            'code': raw['code'],
            'parent_id': raw['parent_id'],
            'name': raw['name'],
            'sort_order': raw['sort_order'] ?? 0,
            'is_active': (raw['is_active'] == true) ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final raw in (payload['units'] as List? ?? const [])) {
        if (raw is! Map) continue;
        await txn.insert(
          'local_unit',
          {
            'code': raw['code'],
            'default_label': raw['default_label'],
            'is_active': (raw['is_active'] == true) ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// #391: applies the unpaid-invoices delta or full-sync payload
  /// to `local_unpaid_invoice`. Rows with `remaining <= 0` are
  /// treated as tombstones — DELETE rather than upsert — so paid-
  /// off invoices vanish from the allocation sheet on next open.
  ///
  /// Server-side `_build_unpaid_invoices_payload` (migration 0075)
  /// includes recently paid-off rows for one delta window so this
  /// dedup completes without a separate tombstone table.
  Future<void> applyUnpaidInvoicesPayload(Map<String, dynamic> payload) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final raw in (payload['unpaid_invoices'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final remaining = (raw['remaining'] as num?)?.toDouble() ?? 0.0;
        final partyId = raw['party_id'] as String?;
        final direction = raw['direction'] as String?;
        final txnId = raw['txn_id'] as String?;
        if (partyId == null || direction == null || txnId == null) continue;
        if (remaining <= 0) {
          // Tombstone — the invoice has been fully paid (or voided).
          await txn.delete(
            'local_unpaid_invoice',
            where: 'party_id = ? AND direction = ? AND txn_id = ?',
            whereArgs: [partyId, direction, txnId],
          );
          continue;
        }
        await txn.insert(
          'local_unpaid_invoice',
          {
            'shop_id': raw['shop_id'],
            'party_id': partyId,
            'direction': direction,
            'txn_id': txnId,
            'occurred_at_ms': (raw['occurred_at_ms'] as num).toInt(),
            'original_amount':
                (raw['original_amount'] as num).toDouble(),
            'already_paid': (raw['already_paid'] as num).toDouble(),
            'remaining': remaining,
            'document_id': raw['document_id'],
            'server_updated_at_ms':
                (raw['server_updated_at_ms'] as num).toInt(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// #391: reads unpaid invoices for the (party, direction) tuple
  /// from the local mirror. Mirrors `ShopApi.listUnpaidInvoices`
  /// shape (`List<UnpaidInvoice>` ordered oldest-first by
  /// occurred_at). The Payment allocation sheet branches on
  /// `useLocalDb(context)` to call either this or the live RPC.
  ///
  /// [includeOptimistic] appends not-yet-synced debt invoices derived
  /// from optimistic `local_transaction` rows (server_updated_at == 0) so
  /// the party page's open-invoices list appears as fast as its sales
  /// list. Left OFF for the payment-allocation path — those rows carry a
  /// placeholder txn_id (= client_op_id) with no server record to allocate
  /// against yet.
  Future<List<UnpaidInvoice>> listUnpaidInvoices({
    required String shopId,
    required String partyId,
    required String direction,
    bool includeOptimistic = false,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'local_unpaid_invoice',
      where: 'shop_id = ? AND party_id = ? AND direction = ?',
      whereArgs: [shopId, partyId, direction],
      orderBy: 'occurred_at_ms ASC, txn_id ASC',
    );
    final invoices = rows
        .map((r) => UnpaidInvoice(
              transactionId: r['txn_id'] as String,
              occurredAt: DateTime.fromMillisecondsSinceEpoch(
                (r['occurred_at_ms'] as num).toInt(),
              ),
              originalAmount: (r['original_amount'] as num).toDouble(),
              alreadyPaid: (r['already_paid'] as num).toDouble(),
              remaining: (r['remaining'] as num).toDouble(),
              documentId: r['document_id'] as String?,
            ))
        .toList();
    if (!includeOptimistic) return invoices;

    // A just-saved credit sale/receive lands in local_transaction
    // (server_updated_at == 0) before the server round-trip populates
    // local_unpaid_invoice. Surface its open portion so the party page
    // updates instantly. These vanish the moment the sale syncs — the
    // optimistic txn is deleted and the real invoice row arrives — so no
    // double-count. Customer (direction 'I') → sale; supplier ('O') →
    // receive.
    final typeCode = direction == 'O' ? 'receive' : 'sale';
    final optimisticRows = await db.query(
      'local_transaction',
      where: 'shop_id = ? AND party_id = ? AND type_code = ? '
          'AND server_updated_at = 0 AND is_voided = 0',
      whereArgs: [shopId, partyId, typeCode],
    );
    for (final r in optimisticRows) {
      final t = LocalTransaction._fromRow(r);
      final total = t.total.toDouble();
      final paid = (t.payload['paid_amount'] as num?)?.toDouble() ?? total;
      final remaining = total - paid;
      if (remaining <= 0) continue; // fully-paid (cash) — not an open invoice
      invoices.add(UnpaidInvoice(
        transactionId: t.txnId,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(t.occurredAtMs),
        originalAmount: total,
        alreadyPaid: paid,
        remaining: remaining,
        documentId: null,
      ));
    }
    invoices.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    return invoices;
  }

  /// #392: assembles a [PartyDetail] entirely from the local mirror so the
  /// customer / supplier page — and the sale / receive / payment links off
  /// it — open while offline. Mirrors the server `get_party_detail` shape:
  /// header (from `local_party`) plus the party's sales, receives and
  /// payments (from `local_transaction`, most-recent first, capped at
  /// [limit] each). Returns null when the party isn't mirrored yet so the
  /// caller can fall back to the live RPC.
  Future<PartyDetail?> getPartyDetailLocal({
    required String shopId,
    required String partyId,
    int limit = 20,
  }) async {
    final db = await _db;
    final headerRows = await db.query(
      'local_party',
      where: 'shop_id = ? AND party_id = ?',
      whereArgs: [shopId, partyId],
      limit: 1,
    );
    if (headerRows.isEmpty) return null;
    final h = headerRows.first;

    Future<List<LocalTransaction>> txnsOfType(String typeCode) async {
      final rows = await db.query(
        'local_transaction',
        where: 'shop_id = ? AND party_id = ? AND type_code = ?',
        whereArgs: [shopId, partyId, typeCode],
        orderBy: 'occurred_at DESC',
        limit: limit,
      );
      return rows.map(LocalTransaction._fromRow).toList(growable: false);
    }

    PartyTxnRow toTxnRow(LocalTransaction t) => PartyTxnRow(
          txnId: t.txnId,
          occurredAt: DateTime.fromMillisecondsSinceEpoch(t.occurredAtMs),
          totalAmount: t.total.toDouble(),
          // paid_amount drives the debt/cash split on the row; carried in
          // the payload (server migration 0089 + optimistic write). The
          // `?? total` fallback only bites pre-0089 rows (self-heal on
          // next full sync).
          paidAmount: (t.payload['paid_amount'] as num?)?.toDouble() ??
              t.total.toDouble(),
          isVoided: t.isVoided,
        );

    final sales =
        (await txnsOfType('sale')).map(toTxnRow).toList(growable: false);
    final receives =
        (await txnsOfType('receive')).map(toTxnRow).toList(growable: false);
    final payments = (await txnsOfType('payment'))
        .map((t) => PartyPaymentRow(
              paymentId: t.txnId,
              occurredAt: DateTime.fromMillisecondsSinceEpoch(t.occurredAtMs),
              amount: t.total.toDouble(),
              direction: (t.payload['direction'] as String?) ?? 'I',
            ))
        .toList(growable: false);

    return PartyDetail(
      header: PartyDetailHeader(
        id: h['party_id'] as String,
        name: h['name'] as String,
        phone: h['phone'] as String?,
        typeCode: h['type_code'] as String,
        receivable: (h['receivable'] as num?)?.toDouble() ?? 0,
        payable: (h['payable'] as num?)?.toDouble() ?? 0,
        isActive: ((h['is_active'] as num?) ?? 1).toInt() == 1,
      ),
      sales: sales,
      receives: receives,
      payments: payments,
    );
  }

  /// #393: reads the product-category picker options from the local
  /// mirror so the item detail / editor / add-item / filter category
  /// dropdown works offline. Mirrors the server `list_categories`
  /// shape (top-level active rows; global first, then sort_order,
  /// then name). The stored `name` is the base label — offline it
  /// won't be locale-resolved, but the picker still functions.
  /// Display name of a single category from the mirror, or null when the id
  /// is null / unknown (treated as "Other" at the call site). Used to give
  /// the offline product reads a real category label.
  Future<String?> _localCategoryName(String? categoryId) async {
    if (categoryId == null) return null;
    final db = await _db;
    final rows = await db.query(
      'local_category',
      columns: ['name'],
      where: 'category_id = ?',
      whereArgs: [categoryId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['name'] as String?;
  }

  Future<List<CategoryOption>> listCategoriesLocal({
    required String shopId,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'local_category',
      where: 'is_active = 1 AND parent_id IS NULL '
          'AND (shop_id IS NULL OR shop_id = ?)',
      whereArgs: [shopId],
      orderBy: 'CASE WHEN shop_id IS NULL THEN 0 ELSE 1 END ASC, '
          'sort_order ASC, name COLLATE NOCASE ASC',
    );
    return rows
        .map((r) => CategoryOption(
              id: r['category_id'] as String,
              code: r['code'] as String,
              name: r['name'] as String,
            ))
        .toList(growable: false);
  }

  Future<void> applyTransactionsPayload(Map<String, dynamic> payload) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final raw in (payload['transactions'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final clientOpId = raw['client_op_id'] as String?;
        // #385: dedupe-and-replace by client_op_id. The mobile app
        // writes an optimistic row at queue-enqueue time with the
        // client_op_id as a placeholder txn_id; when the server's
        // authoritative row arrives here it has a different
        // server-assigned UUID, so a plain INSERT-REPLACE on
        // txn_id wouldn't collide. DELETE the optimistic row
        // inside this same sqflite transaction so history never
        // sees a duplicate or a brief "row missing" flash.
        if (clientOpId != null && clientOpId.isNotEmpty) {
          await txn.delete(
            'local_transaction',
            where: 'client_op_id = ? AND txn_id != ?',
            whereArgs: [clientOpId, raw['txn_id']],
          );
        }
        await txn.insert(
          'local_transaction',
          {
            'txn_id': raw['txn_id'],
            'shop_id': raw['shop_id'],
            'type_code': raw['type_code'],
            'occurred_at': raw['occurred_at_ms'],
            'total': raw['total'],
            'party_id': raw['party_id'],
            'is_voided': (raw['is_voided'] == true) ? 1 : 0,
            'server_updated_at': raw['server_updated_at_ms'],
            'client_op_id': clientOpId,
            'payload_json': jsonEncode(raw),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// #385: writes an optimistic `local_transaction` row at
  /// queue-enqueue time so the cashier sees the sale / receive /
  /// payment / expense in history INSTANTLY instead of waiting
  /// for the queue drain → server insert → realtime → delta-sync
  /// round-trip. The row carries:
  ///
  /// * `txn_id`   = the client-minted [txnId] UUID (migrations 0097-0100),
  ///                so the row keeps ONE stable id across sync and can be
  ///                voided offline before it reaches the server. Falls back
  ///                to [clientOpId] only when a caller omits [txnId] (legacy
  ///                path / pre-0097 rows);
  /// * `client_op_id` = the separate idempotency key, so
  ///                    `applyTransactionsPayload` can dedupe-and-replace
  ///                    when the server row arrives (keyed on client_op_id,
  ///                    independent of the txn_id format);
  /// * `server_updated_at` = 0, signalling "not yet synced from
  ///                          server". `LocalTransaction
  ///                          .isOptimistic` returns true for
  ///                          these.
  /// * `payload_json` = the supplied [payload] map (typically
  ///                    includes `party_name`,
  ///                    `payment_method_code`, `lines_summary`,
  ///                    ...).
  // ---- #390: optimistic admin-side mutation writes -----------------------

  /// Set a packaging's `sale_price`. Null clears it (un-priced).
  Future<void> updateLocalShopItemUnitPrice({
    required String shopItemUnitId,
    required num? salePrice,
  }) async {
    final db = await _db;
    await db.update(
      'local_shop_item_unit',
      {'sale_price': salePrice},
      where: 'shop_item_unit_id = ?',
      whereArgs: [shopItemUnitId],
    );
  }

  /// Toggle default-sale / default-receive on a packaging. When a flag
  /// goes true, clears that flag on any sibling row under the same
  /// `shop_item_id` first — mirrors the server-side single-default
  /// invariant (one default per side per item).
  Future<void> updateLocalShopItemUnitDefaultFlags({
    required String shopItemUnitId,
    required bool isDefaultSale,
    required bool isDefaultReceive,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final parent = await txn.query(
        'local_shop_item_unit',
        columns: ['shop_item_id'],
        where: 'shop_item_unit_id = ?',
        whereArgs: [shopItemUnitId],
        limit: 1,
      );
      if (parent.isEmpty) return;
      final shopItemId = parent.first['shop_item_id'] as String;
      if (isDefaultSale) {
        await txn.update(
          'local_shop_item_unit',
          {'is_default_sale': 0},
          where: 'shop_item_id = ? AND shop_item_unit_id != ?',
          whereArgs: [shopItemId, shopItemUnitId],
        );
      }
      if (isDefaultReceive) {
        await txn.update(
          'local_shop_item_unit',
          {'is_default_receive': 0},
          where: 'shop_item_id = ? AND shop_item_unit_id != ?',
          whereArgs: [shopItemId, shopItemUnitId],
        );
      }
      await txn.update(
        'local_shop_item_unit',
        {
          'is_default_sale': isDefaultSale ? 1 : 0,
          'is_default_receive': isDefaultReceive ? 1 : 0,
        },
        where: 'shop_item_unit_id = ?',
        whereArgs: [shopItemUnitId],
      );
    });
  }

  /// Set / clear category on an item.
  Future<void> updateLocalShopItemCategory({
    required String shopItemId,
    required String? categoryId,
  }) async {
    final db = await _db;
    await db.update(
      'local_shop_item',
      {'category_id': categoryId},
      where: 'shop_item_id = ?',
      whereArgs: [shopItemId],
    );
  }

  /// Optimistic: bump the mirrored base-unit stock by [baseUnitDelta] so the
  /// product list + item detail reflect a just-saved stock adjustment
  /// instantly (the server already has the value; the local mirror would
  /// otherwise lag until the next sync, which overwrites this with truth).
  Future<void> applyOptimisticStockDelta({
    required String shopItemId,
    required num baseUnitDelta,
  }) async {
    final db = await _db;
    await db.rawUpdate(
      'UPDATE local_shop_item SET current_stock = current_stock + ? '
      'WHERE shop_item_id = ?',
      [baseUnitDelta, shopItemId],
    );
  }

  /// Optimistic: mark [shopItemIds] as just-sold so they float to the top of
  /// the Sale item list immediately (bump sale_count, set last_sold_at = now).
  /// The next items-sync overwrites these with the server's combined
  /// cross-device values, so this is a momentary overlay — never a
  /// double-count. Bumps once per distinct item regardless of line count; the
  /// authoritative per-line tally comes from the server.
  Future<void> applyOptimisticSaleRecency({
    required List<String> shopItemIds,
    required int nowMs,
  }) async {
    final ids = shopItemIds.toSet().toList(growable: false);
    if (ids.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE local_shop_item SET sale_count = sale_count + 1, last_sold_at = ? '
      'WHERE shop_item_id IN ($placeholders)',
      [nowMs, ...ids],
    );
  }

  /// Optimistic: mark [shopItemUnitIds] as just-received from [supplierId] so
  /// they lead that supplier's basket immediately. Only `last_received_at` is
  /// touched (cost is preserved on conflict); the next items-sync reconciles to
  /// the server's supplier_item_unit_cost.
  Future<void> applyOptimisticSupplierBasket({
    required String supplierId,
    required String shopId,
    required List<String> shopItemUnitIds,
    required int nowMs,
  }) async {
    final ids = shopItemUnitIds.toSet().toList(growable: false);
    if (ids.isEmpty) return;
    final db = await _db;
    for (final unitId in ids) {
      await db.rawInsert(
        'INSERT INTO local_supplier_item '
        '(party_id, shop_item_unit_id, shop_id, last_received_at, server_updated_at) '
        'VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT(party_id, shop_item_unit_id) '
        'DO UPDATE SET last_received_at = excluded.last_received_at',
        [supplierId, unitId, shopId, nowMs, nowMs],
      );
    }
  }

  /// Optimistic: decrement the mirrored party balance after a payment so the
  /// customers/suppliers LIST reflects it instantly (the list reads these
  /// columns directly; the detail page re-fetches from the server). Mirrors
  /// post_payment's sign math: direction 'I' (customer) reduces receivable,
  /// 'O' (supplier) reduces payable. Clamped at 0; sync reconciles to truth.
  Future<void> applyOptimisticPartyPayment({
    required String partyId,
    required String direction,
    required num amount,
  }) async {
    final db = await _db;
    final col = direction == 'I' ? 'receivable' : 'payable';
    await db.rawUpdate(
      'UPDATE local_party SET $col = MAX(0, $col - ?) WHERE party_id = ?',
      [amount, partyId],
    );
  }

  /// Optimistic: increase a party's outstanding balance when a credit
  /// transaction is saved — supplier payable on a receive, customer receivable
  /// on a debt sale — so the customers/suppliers LIST reflects it instantly.
  /// Direction 'I' = customer receivable, 'O' = supplier payable. The next
  /// parties-sync replaces it with the server value. Inverse of
  /// [applyOptimisticPartyPayment] (use that to revert on a rejected post).
  Future<void> applyOptimisticPartyCharge({
    required String partyId,
    required String direction,
    required num amount,
  }) async {
    final db = await _db;
    final col = direction == 'I' ? 'receivable' : 'payable';
    await db.rawUpdate(
      'UPDATE local_party SET $col = $col + ? WHERE party_id = ?',
      [amount, partyId],
    );
  }

  /// Optimistic: mirror a just-created party (customer/supplier) into
  /// local_party so it shows in the people list + pickers immediately, instead
  /// of waiting for the next parties sync. server_updated_at = 0 marks it
  /// optimistic; the next parties-sync replaces it with the server row.
  Future<void> applyOptimisticPartyCreate({
    required String partyId,
    required String shopId,
    required String name,
    String? phone,
    required String typeCode,
    num receivable = 0,
    num payable = 0,
  }) async {
    final db = await _db;
    await db.insert(
      'local_party',
      {
        'party_id': partyId,
        'shop_id': shopId,
        'name': name,
        'phone': phone,
        'type_code': typeCode,
        'receivable': receivable,
        'payable': payable,
        'is_active': 1,
        'server_updated_at': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---- Optimistic category mirror writes (0076) ------------------------
  // The `code` column is NOT NULL in the mirror but never displayed
  // (the UI shows `name`); we store a local placeholder slug that the
  // server's real code overwrites on the next categories sync.

  static String _localCategoryCode(String name, String fallbackId) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.isEmpty) return 'c_${fallbackId.replaceAll('-', '').substring(0, 8)}';
    return slug;
  }

  Future<void> upsertLocalProductCategory({
    required String categoryId,
    required String shopId,
    required String name,
    bool isActive = true,
  }) async {
    final db = await _db;
    await db.insert(
      'local_category',
      {
        'category_id': categoryId,
        'shop_id': shopId,
        'code': _localCategoryCode(name, categoryId),
        'parent_id': null,
        'name': name,
        'sort_order': 0,
        'is_active': isActive ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> renameLocalProductCategory({
    required String categoryId,
    required String name,
  }) async {
    final db = await _db;
    await db.update('local_category', {'name': name},
        where: 'category_id = ?', whereArgs: [categoryId]);
  }

  Future<void> setLocalProductCategoryActive({
    required String categoryId,
    required bool isActive,
  }) async {
    final db = await _db;
    await db.update('local_category', {'is_active': isActive ? 1 : 0},
        where: 'category_id = ?', whereArgs: [categoryId]);
  }

  Future<void> upsertLocalExpenseCategory({
    required String categoryId,
    required String shopId,
    required String name,
    bool isActive = true,
  }) async {
    final db = await _db;
    await db.insert(
      'local_expense_category',
      {
        'category_id': categoryId,
        'shop_id': shopId,
        'code': _localCategoryCode(name, categoryId),
        'name': name,
        'is_active': isActive ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> renameLocalExpenseCategory({
    required String categoryId,
    required String name,
  }) async {
    final db = await _db;
    await db.update('local_expense_category', {'name': name},
        where: 'category_id = ?', whereArgs: [categoryId]);
  }

  Future<void> setLocalExpenseCategoryActive({
    required String categoryId,
    required bool isActive,
  }) async {
    final db = await _db;
    await db.update('local_expense_category', {'is_active': isActive ? 1 : 0},
        where: 'category_id = ?', whereArgs: [categoryId]);
  }

  /// Soft-delete a packaging — sets is_active=0 + clears default flags.
  /// The Products + Sale grids filter on `is_active = 1`, so the row
  /// disappears from view immediately.
  Future<void> softDisableLocalShopItemUnit({
    required String shopItemUnitId,
  }) async {
    final db = await _db;
    await db.update(
      'local_shop_item_unit',
      {
        'is_active': 0,
        'is_default_sale': 0,
        'is_default_receive': 0,
      },
      where: 'shop_item_unit_id = ?',
      whereArgs: [shopItemUnitId],
    );
  }

  /// Optimistically mirror a just-created packaging so screens that read the
  /// local DB (e.g. Product detail) reflect it immediately. Columns mirror the
  /// items-sync unit upsert; a new extra packaging is active and non-default,
  /// with no cost/learned-qty yet. `server_updated_at = 0` so the next delta
  /// sync's authoritative row (replace semantics) overwrites this.
  /// Optimistically mirror a brand-new shop_item (0095 offline create) so
  /// it shows in the products list + search immediately, before the create
  /// drains. `server_updated_at = 0` marks it optimistic; the next
  /// items-sync replaces it. Pair with [insertLocalShopItemUnit] for its
  /// packaging(s) and [insertLocalShopItemAlias] for the display name.
  Future<void> insertLocalShopItem({
    required String shopItemId,
    required String shopId,
    required String displayName,
    required String baseUnitCode,
    String? categoryId,
  }) async {
    final db = await _db;
    await db.insert(
      'local_shop_item',
      {
        'shop_item_id': shopItemId,
        'shop_id': shopId,
        'item_id': null,
        'display_name': displayName,
        'category_id': categoryId,
        'base_unit_code': baseUnitCode,
        'current_stock': 0,
        'avg_cost': 0,
        'is_active': 1,
        'updated_at': 0,
        'server_updated_at': 0,
        'sale_count': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertLocalShopItemUnit({
    required String shopItemUnitId,
    required String shopItemId,
    required String unitCode,
    required String packagingLabel,
    required num conversionToBase,
    num? salePrice,
  }) async {
    final db = await _db;
    await db.insert(
      'local_shop_item_unit',
      {
        'shop_item_unit_id': shopItemUnitId,
        'shop_item_id': shopItemId,
        'unit_code': unitCode,
        'packaging_label': packagingLabel,
        'conversion_to_base': conversionToBase,
        'sale_price': salePrice,
        'last_cost': null,
        'last_sale_qty': null,
        'last_receive_qty': null,
        'is_default_sale': 0,
        'is_default_receive': 0,
        'is_active': 1,
        'server_updated_at': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Insert (or upsert on natural key) a search alias.
  ///
  /// The local mirror keys aliases on `(shop_item_id, alias)` — the
  /// server uses a synthetic alias_id, but we never need to look one
  /// up locally. INSERT OR REPLACE keeps the retry case (same
  /// client_op_id reaching us twice) idempotent at the local layer.
  Future<void> insertLocalShopItemAlias({
    required String shopItemId,
    required String aliasText,
    bool isDisplay = false,
  }) async {
    final db = await _db;
    await db.insert(
      'local_shop_item_alias',
      {
        'shop_item_id': shopItemId,
        'alias': aliasText,
        'is_display': isDisplay ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (isDisplay) {
      // Also flip the item's display_name optimistically so the
      // products list + detail header reflect the rename without
      // waiting for the delta.
      await db.update(
        'local_shop_item',
        {'display_name': aliasText},
        where: 'shop_item_id = ?',
        whereArgs: [shopItemId],
      );
    }
  }

  /// Remove a search alias by its (shop_item_id, alias_text) natural
  /// key. Screen handlers pass both — the server's alias_id is only
  /// used in the queued ShopApi call.
  Future<void> deleteLocalShopItemAliasByText({
    required String shopItemId,
    required String aliasText,
  }) async {
    final db = await _db;
    await db.delete(
      'local_shop_item_alias',
      where: 'shop_item_id = ? AND alias = ?',
      whereArgs: [shopItemId, aliasText],
    );
  }

  /// Insert a barcode bound to a packaging. The barcode VALUE is the
  /// local PK; INSERT OR REPLACE makes the retry case idempotent. When
  /// `isPrimary`, demote any existing primary on the same packaging.
  Future<void> insertLocalShopItemBarcode({
    required String shopItemUnitId,
    required String barcode,
    bool isPrimary = false,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (isPrimary) {
        await txn.update(
          'local_shop_item_barcode',
          {'is_primary': 0},
          where: 'shop_item_unit_id = ? AND barcode != ?',
          whereArgs: [shopItemUnitId, barcode],
        );
      }
      await txn.insert(
        'local_shop_item_barcode',
        {
          'barcode': barcode,
          'shop_item_unit_id': shopItemUnitId,
          'is_primary': isPrimary ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Delete a barcode by its VALUE (local PK). Screen handlers pass
  /// the value alongside the server-side barcode_id used by the queued
  /// post.
  Future<void> deleteLocalShopItemBarcodeByValue({
    required String barcode,
  }) async {
    final db = await _db;
    await db.delete(
      'local_shop_item_barcode',
      where: 'barcode = ?',
      whereArgs: [barcode],
    );
  }

  /// Promote one barcode to primary, atomically demoting the rest under
  /// the same packaging.
  Future<void> setPrimaryLocalShopItemBarcode({
    required String barcode,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final row = await txn.query(
        'local_shop_item_barcode',
        columns: ['shop_item_unit_id'],
        where: 'barcode = ?',
        whereArgs: [barcode],
        limit: 1,
      );
      if (row.isEmpty) return;
      final shopItemUnitId = row.first['shop_item_unit_id'] as String;
      await txn.update(
        'local_shop_item_barcode',
        {'is_primary': 0},
        where: 'shop_item_unit_id = ? AND barcode != ?',
        whereArgs: [shopItemUnitId, barcode],
      );
      await txn.update(
        'local_shop_item_barcode',
        {'is_primary': 1},
        where: 'barcode = ?',
        whereArgs: [barcode],
      );
    });
  }

  /// Rename + optionally update phone on a party.
  Future<void> renameLocalParty({
    required String partyId,
    required String name,
    String? phone,
  }) async {
    final db = await _db;
    final changes = <String, Object?>{'name': name};
    if (phone != null) changes['phone'] = phone;
    await db.update(
      'local_party',
      changes,
      where: 'party_id = ?',
      whereArgs: [partyId],
    );
  }

  /// Optimistic: hide/restore a party in the mirror. searchParties +
  /// supplierBasket filter is_active, so this removes/restores it immediately.
  Future<void> setLocalPartyActive({
    required String partyId,
    required bool isActive,
  }) async {
    final db = await _db;
    await db.update(
      'local_party',
      {'is_active': isActive ? 1 : 0},
      where: 'party_id = ?',
      whereArgs: [partyId],
    );
  }

  /// Optimistic: hide/restore a whole product in the mirror. searchItems
  /// filters is_active, so this removes/restores it from the grid at once.
  Future<void> setLocalShopItemActive({
    required String shopItemId,
    required bool isActive,
  }) async {
    final db = await _db;
    await db.update(
      'local_shop_item',
      {'is_active': isActive ? 1 : 0},
      where: 'shop_item_id = ?',
      whereArgs: [shopItemId],
    );
  }

  // ---- #385: optimistic transaction write -----------------------------

  Future<void> writeOptimisticTransaction({
    required String clientOpId,
    required String shopId,
    required String typeCode,
    required int occurredAtMs,
    required num total,
    String? partyId,
    required Map<String, dynamic> payload,
    // The client-minted UUID the post RPC will use as the real txn id
    // (offline-void support). Null → fall back to the client_op_id placeholder
    // (legacy behaviour for flows not yet minting a UUID).
    String? txnId,
  }) async {
    final db = await _db;
    final enriched = <String, dynamic>{
      ...payload,
      'client_op_id': clientOpId,
      'server_updated_at_ms': 0,
    };
    await db.insert(
      'local_transaction',
      {
        'txn_id': txnId ?? clientOpId,
        'shop_id': shopId,
        'type_code': typeCode,
        'occurred_at': occurredAtMs,
        'total': total,
        'party_id': partyId,
        'is_voided': 0,
        'server_updated_at': 0,
        'client_op_id': clientOpId,
        'payload_json': jsonEncode(enriched),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Remove an optimistic (still-unsynced) transaction row after the server
  /// HARD-rejected the post — otherwise the rejected sale/receive lingers in
  /// history forever (no server row shares its client_op_id, so delta sync
  /// never replaces it) and a retry would stack a second phantom. Guarded on
  /// `server_updated_at = 0` so a genuinely synced row is never deleted. No-op
  /// if the row is already gone.
  Future<void> deleteOptimisticTransaction({required String txnId}) async {
    final db = await _db;
    await db.delete(
      'local_transaction',
      where: 'txn_id = ? AND server_updated_at = 0',
      whereArgs: [txnId],
    );
  }

  // ---- Sync state ----------------------------------------------------------

  Future<Map<String, ResourceSyncState>> loadSyncState(String shopId) async {
    final rows = await (await _db).query(
      'local_sync_state',
      where: 'shop_id = ?',
      whereArgs: [shopId],
    );
    return {
      for (final r in rows)
        r['resource'] as String: ResourceSyncState(
          resource: r['resource'] as String,
          lastSyncedAtMs: r['last_synced_at'] as int,
          fullSyncDone: (r['full_sync_done'] as int) == 1,
        ),
    };
  }

  Future<void> writeSyncState({
    required String shopId,
    required String resource,
    required int lastSyncedAtMs,
    bool? fullSyncDone,
  }) async {
    final db = await _db;
    if (fullSyncDone == null) {
      // Preserve the existing fullSyncDone bit. Use a manual upsert
      // dance because sqflite's `insert with replace` would clobber.
      final existing = await db.query(
        'local_sync_state',
        where: 'shop_id = ? AND resource = ?',
        whereArgs: [shopId, resource],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert('local_sync_state', {
          'shop_id': shopId,
          'resource': resource,
          'last_synced_at': lastSyncedAtMs,
          'full_sync_done': 0,
        });
      } else {
        await db.update(
          'local_sync_state',
          {'last_synced_at': lastSyncedAtMs},
          where: 'shop_id = ? AND resource = ?',
          whereArgs: [shopId, resource],
        );
      }
      return;
    }
    await db.insert(
      'local_sync_state',
      {
        'shop_id': shopId,
        'resource': resource,
        'last_synced_at': lastSyncedAtMs,
        'full_sync_done': fullSyncDone ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---- Stock projection ----------------------------------------------------

  Future<void> writeProjection({
    required String pendingPostId,
    required String shopItemId,
    required num delta,
  }) async {
    await (await _db).insert(
      'local_stock_projection',
      {
        'pending_post_id': pendingPostId,
        'shop_item_id': shopItemId,
        'delta': delta,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Insert a batch of projection rows for one queued post in a
  /// single transaction. [lines] supplies the units + quantities;
  /// the helper looks up each unit's `shop_item_id` and
  /// `conversion_to_base` from the local mirror, computes the
  /// base-unit delta (positive for receives, negative for sales),
  /// and inserts one row per line. No-op if [lines] is empty.
  Future<void> applyProjectionLines({
    required String pendingPostId,
    required List<ProjectionLine> lines,
  }) async {
    if (lines.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      for (final l in lines) {
        // Look up shop_item_id + conversion from the local unit row.
        final rows = await txn.query(
          'local_shop_item_unit',
          columns: ['shop_item_id', 'conversion_to_base'],
          where: 'shop_item_unit_id = ?',
          whereArgs: [l.shopItemUnitId],
          limit: 1,
        );
        if (rows.isEmpty) continue; // unit not in local mirror — skip
        final shopItemId = rows.first['shop_item_id'] as String;
        final conv = (rows.first['conversion_to_base'] as num).toDouble();
        final baseDelta = l.quantity.toDouble() * conv * l.direction;
        await txn.insert(
          'local_stock_projection',
          {
            'pending_post_id': pendingPostId,
            'shop_item_id': shopItemId,
            'delta': baseDelta,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Optimistic: bump current_stock directly for a just-saved receive (or sale)
  /// so the product list reflects it instantly (the list reads current_stock).
  /// Looks up shop_item_id + conversion per packaging like [applyProjectionLines]
  /// but writes the cached stock directly — the next items-sync replaces it with
  /// the server value, so there's no projection to clean up (unlike the queue
  /// path). [ProjectionLine.direction] is +1 for receive, -1 for sale; pass the
  /// inverse to revert a rejected post.
  Future<void> applyOptimisticStockForLines({
    required List<ProjectionLine> lines,
  }) async {
    if (lines.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      for (final l in lines) {
        final rows = await txn.query(
          'local_shop_item_unit',
          columns: ['shop_item_id', 'conversion_to_base'],
          where: 'shop_item_unit_id = ?',
          whereArgs: [l.shopItemUnitId],
          limit: 1,
        );
        if (rows.isEmpty) continue; // unit not in local mirror — skip
        final shopItemId = rows.first['shop_item_id'] as String;
        final conv = (rows.first['conversion_to_base'] as num).toDouble();
        final baseDelta = l.quantity.toDouble() * conv * l.direction;
        await txn.rawUpdate(
          'UPDATE local_shop_item SET current_stock = current_stock + ? '
          'WHERE shop_item_id = ?',
          [baseDelta, shopItemId],
        );
      }
    });
  }

  Future<void> clearProjectionsForPost(String pendingPostId) async {
    await (await _db).delete(
      'local_stock_projection',
      where: 'pending_post_id = ?',
      whereArgs: [pendingPostId],
    );
  }

  /// #387: nuke every local mirror + projection + sync-state row for
  /// [shopId]. Used by the destructive "Reset local data" action on
  /// the Storage & sync screen. Runs in one sqflite transaction so a
  /// failure midway rolls back the whole wipe — no half-empty state.
  ///
  /// Does NOT touch `pending_post` / `failed_post` (queue rows) or
  /// `cache_entry` (FavoritesCache / TodaySummaryCache /
  /// AuthStateCache). Callers should drain the queue first.
  Future<void> wipeAllLocalData(String shopId) async {
    final db = await _db;
    await db.transaction((txn) async {
      // Order: children before parents (FKs are advisory in sqflite
      // but the order documents intent).
      await txn.delete('local_stock_projection');
      await txn.delete(
        'local_shop_item_alias',
        where: 'shop_item_id IN '
            '(SELECT shop_item_id FROM local_shop_item WHERE shop_id = ?)',
        whereArgs: [shopId],
      );
      await txn.delete(
        'local_shop_item_barcode',
        where: 'shop_item_unit_id IN '
            '(SELECT shop_item_unit_id FROM local_shop_item_unit '
            ' WHERE shop_item_id IN '
            '  (SELECT shop_item_id FROM local_shop_item WHERE shop_id = ?))',
        whereArgs: [shopId],
      );
      await txn.delete(
        'local_shop_item_unit',
        where: 'shop_item_id IN '
            '(SELECT shop_item_id FROM local_shop_item WHERE shop_id = ?)',
        whereArgs: [shopId],
      );
      await txn.delete(
        'local_shop_item',
        where: 'shop_id = ?',
        whereArgs: [shopId],
      );
      await txn.delete(
        'local_party',
        where: 'shop_id = ?',
        whereArgs: [shopId],
      );
      await txn.delete(
        'local_expense_category',
        where: 'shop_id = ?',
        whereArgs: [shopId],
      );
      await txn.delete(
        'local_transaction',
        where: 'shop_id = ?',
        whereArgs: [shopId],
      );
      await txn.delete(
        'local_sync_state',
        where: 'shop_id = ?',
        whereArgs: [shopId],
      );
      // Reference tables (local_unit, local_category) are global —
      // not scoped to shop. Leave them alone; they re-sync via the
      // next full_sync regardless.
    });
  }
}

/// One line of a queued post that affects stock. [direction] is
/// `-1` for sales (subtract from stock) and `+1` for receives
/// (add to stock).
class ProjectionLine {
  const ProjectionLine({
    required this.shopItemUnitId,
    required this.quantity,
    required this.direction,
  });

  final String shopItemUnitId;
  final num quantity;
  final int direction;
}

class LocalShopItemAlias {
  const LocalShopItemAlias({
    required this.shopItemId,
    required this.alias,
    required this.isDisplay,
  });

  final String shopItemId;
  final String alias;
  final bool isDisplay;
}

class LocalShopItemBarcode {
  const LocalShopItemBarcode({
    required this.barcode,
    required this.shopItemUnitId,
    required this.isPrimary,
  });

  final String barcode;
  final String shopItemUnitId;
  final bool isPrimary;
}

class ResourceSyncState {
  const ResourceSyncState({
    required this.resource,
    required this.lastSyncedAtMs,
    required this.fullSyncDone,
  });

  final String resource;
  final int lastSyncedAtMs;
  final bool fullSyncDone;
}
