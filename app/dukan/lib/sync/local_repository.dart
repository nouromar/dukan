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
        shopItemId: r['shop_item_id'] as String,
        shopId: r['shop_id'] as String,
        itemId: r['item_id'] as String?,
        displayName: r['display_name'] as String,
        categoryId: r['category_id'] as String?,
        baseUnitCode: r['base_unit_code'] as String,
        currentStock: r['current_stock'] as num,
        avgCost: r['avg_cost'] as num,
        reorderThreshold: r['reorder_threshold'] as num?,
        isActive: (r['is_active'] as int) == 1,
        serverUpdatedAtMs: r['server_updated_at'] as int,
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
        isDefaultSale: (r['is_default_sale'] as int) == 1,
        isDefaultReceive: (r['is_default_receive'] as int) == 1,
        isActive: (r['is_active'] as int) == 1,
        serverUpdatedAtMs: r['server_updated_at'] as int,
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
        isActive: (r['is_active'] as int) == 1,
        serverUpdatedAtMs: r['server_updated_at'] as int,
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
        isActive: (r['is_active'] as int) == 1,
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
  /// lines summary). Mirrors what `get_transactions_delta` returns
  /// for a single row.
  final Map<String, dynamic> payload;

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
      occurredAtMs: r['occurred_at'] as int,
      total: r['total'] as num,
      partyId: r['party_id'] as String?,
      isVoided: (r['is_voided'] as int) == 1,
      serverUpdatedAtMs: r['server_updated_at'] as int,
      payload: payload,
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
  }) async {
    final rows = await (await _db).query(
      'local_transaction',
      where: 'shop_id = ? AND type_code = ?',
      whereArgs: [shopId, 'sale'],
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    return rows.map(LocalTransaction._fromRow).toList(growable: false);
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
            'payload_json': jsonEncode(raw),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
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

  Future<void> clearProjectionsForPost(String pendingPostId) async {
    await (await _db).delete(
      'local_stock_projection',
      where: 'pending_post_id = ?',
      whereArgs: [pendingPostId],
    );
  }
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
