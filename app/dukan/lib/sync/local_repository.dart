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
    ShopItemBarcodeRow;
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

  factory LocalShopItemUnit._fromRow(Map<String, Object?> r) =>
      LocalShopItemUnit(
        shopItemUnitId: r['shop_item_unit_id'] as String,
        shopItemId: r['shop_item_id'] as String,
        unitCode: r['unit_code'] as String,
        packagingLabel: r['packaging_label'] as String,
        conversionToBase: r['conversion_to_base'] as num,
        salePrice: r['sale_price'] as num?,
        lastCost: r['last_cost'] as num?,
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
  }) async {
    final db = await _db;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      // Simple ordered listing — caller (Sale grid) will overlay
      // favorites elsewhere.
      final rows = await db.query(
        'local_shop_item',
        where: 'shop_id = ? AND is_active = 1',
        whereArgs: [shopId],
        orderBy: 'display_name COLLATE NOCASE ASC',
        limit: limit,
      );
      return rows.map(LocalShopItem._fromRow).toList(growable: false);
    }
    // Match either display_name OR any alias. Aliases live in a
    // separate table; UNION-SELECT keeps it to one SQL roundtrip.
    final pattern = '%${trimmed.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final rows = await db.rawQuery('''
      SELECT DISTINCT si.*
        FROM local_shop_item si
        LEFT JOIN local_shop_item_alias a
          ON a.shop_item_id = si.shop_item_id
       WHERE si.shop_id = ?
         AND si.is_active = 1
         AND (si.display_name LIKE ? COLLATE NOCASE
              OR a.alias LIKE ? COLLATE NOCASE)
       ORDER BY si.display_name COLLATE NOCASE ASC
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
    final summary = await toShopItemSummary(item);
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
  Future<ShopItemSummary> toShopItemSummary(LocalShopItem item) async {
    final units = await packagingsForItem(item.shopItemId);
    LocalShopItemUnit? defaultSale;
    LocalShopItemUnit? baseUnit;
    var anyPriceSet = false;
    for (final u in units) {
      if (u.salePrice != null && u.salePrice != 0) anyPriceSet = true;
      if (u.isDefaultSale) defaultSale = u;
      if (u.conversionToBase == 1) baseUnit = u;
    }
    final preferred = defaultSale ?? baseUnit;
    return ShopItemSummary(
      shopItemId: item.shopItemId,
      itemId: item.itemId,
      displayName: item.displayName,
      categoryName: null,
      baseUnitCode: item.baseUnitCode,
      baseUnitLabel: item.baseUnitCode,
      currentStock: item.currentStock.toDouble(),
      reorderThreshold: item.reorderThreshold?.toDouble(),
      unitCount: units.length,
      isActive: item.isActive,
      defaultSalePrice: preferred?.salePrice?.toDouble(),
      anyPriceSet: anyPriceSet,
    );
  }

  /// Parties matching [query] within [shopId] filtered to
  /// [typeCode] ('customer' or 'supplier'). Empty query → first 50
  /// by name.
  Future<List<LocalParty>> searchParties(
    String query, {
    required String shopId,
    required String typeCode,
    int limit = 50,
  }) async {
    final trimmed = query.trim();
    final db = await _db;
    if (trimmed.isEmpty) {
      final rows = await db.query(
        'local_party',
        where: 'shop_id = ? AND type_code = ? AND is_active = 1',
        whereArgs: [shopId, typeCode],
        orderBy: 'name COLLATE NOCASE ASC',
        limit: limit,
      );
      return rows.map(LocalParty._fromRow).toList(growable: false);
    }
    final pattern = '%${trimmed.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final rows = await db.query(
      'local_party',
      where:
          'shop_id = ? AND type_code = ? AND is_active = 1 AND name LIKE ? COLLATE NOCASE',
      whereArgs: [shopId, typeCode, pattern],
      orderBy: 'name COLLATE NOCASE ASC',
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
        postedAt: t.payload['posted_at'] == null
            ? null
            : DateTime.tryParse(t.payload['posted_at'] as String),
        partyId: t.partyId,
        partyName: t.payload['party_name'] as String?,
        totalAmount: t.total.toDouble(),
        paidAmount: (t.payload['paid_amount'] as num?)?.toDouble() ??
            t.total.toDouble(),
        paymentMethodCode: t.payload['payment_method_code'] as String?,
        isVoided: t.isVoided,
        reversalTxnId: t.payload['reversal_txn_id'] as String?,
        voidedAt: t.payload['voided_at'] == null
            ? null
            : DateTime.tryParse(t.payload['voided_at'] as String),
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
      );

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
  /// * `txn_id`   = [clientOpId] as a placeholder (we don't know
  ///                the server-assigned UUID yet);
  /// * `client_op_id` = same, so `applyTransactionsPayload` can
  ///                    dedupe-and-replace when the server row
  ///                    arrives;
  /// * `server_updated_at` = 0, signalling "not yet synced from
  ///                          server". `LocalTransaction
  ///                          .isOptimistic` returns true for
  ///                          these.
  /// * `payload_json` = the supplied [payload] map (typically
  ///                    includes `party_name`,
  ///                    `payment_method_code`, `lines_summary`,
  ///                    ...).
  Future<void> writeOptimisticTransaction({
    required String clientOpId,
    required String shopId,
    required String typeCode,
    required int occurredAtMs,
    required num total,
    String? partyId,
    required Map<String, dynamic> payload,
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
        'txn_id': clientOpId,
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

  Future<void> clearProjectionsForPost(String pendingPostId) async {
    await (await _db).delete(
      'local_stock_projection',
      where: 'pending_post_id = ?',
      whereArgs: [pendingPostId],
    );
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
