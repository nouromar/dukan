// Tests for #374 LocalRepository → public DTO converters.
// These are the seams every daily-flow screen consumes when
// offline_mode = full, so we lock in the field-for-field mapping
// here rather than re-asserting it per screen test.

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/storage/app_database.dart';
import 'package:dukan/sync/local_repository.dart';

import '../shared/test_database.dart';

void main() {
  late AppDatabase database;
  late LocalRepository repo;

  setUp(() async {
    database = await openTestDatabase();
    repo = LocalRepository(Future.value(database));
  });

  tearDown(() async {
    await database.close();
  });

  group('toItemSearchResult', () {
    test('Sale screen picks is_default_sale packaging', () async {
      await repo.applyItemsPayload(_riceWithTwoPackagings());
      final item = (await repo.searchItems('rice', shopId: 'shop-1')).single;
      final r = await repo.toItemSearchResult(item, screen: 'sale');
      expect(r.defaultShopItemUnitId, 'siu-bag');
      expect(r.defaultUnitSalePrice, 80000);
      expect(r.defaultUnitConversionToBase, 5);
      expect(r.currentStock, 100);
      expect(r.isActivated, isTrue);
    });

    test('Receive screen picks is_default_receive packaging', () async {
      await repo.applyItemsPayload(_riceWithTwoPackagings());
      final item = (await repo.searchItems('rice', shopId: 'shop-1')).single;
      final r = await repo.toItemSearchResult(item, screen: 'receive');
      expect(r.defaultShopItemUnitId, 'siu-base');
      expect(r.defaultUnitConversionToBase, 1);
    });
  });

  test('toShopItemSummary derives anyPriceSet + defaultSalePrice', () async {
    await repo.applyItemsPayload(_riceWithTwoPackagings());
    final item = (await repo.searchItems('rice', shopId: 'shop-1')).single;
    final s = await repo.toShopItemSummary(item);
    expect(s.shopItemId, 'si-1');
    expect(s.unitCount, 2);
    expect(s.anyPriceSet, isTrue);
    // default sale packaging has price 80000.
    expect(s.defaultSalePrice, 80000);
    expect(s.currentStock, 100);
  });

  test('toShopItemSummary handles items with no priced packaging', () async {
    await repo.applyItemsPayload({
      'items': [
        {
          'shop_item_id': 'si-2',
          'shop_id': 'shop-1',
          'item_id': null,
          'display_name': 'Tea',
          'category_id': null,
          'base_unit_code': 'g',
          'current_stock': 0,
          'avg_cost': 0,
          'reorder_threshold': null,
          'is_active': true,
          'server_updated_at_ms': 1700000000000,
        }
      ],
      'units': [
        {
          'shop_item_unit_id': 'siu-tea-base',
          'shop_item_id': 'si-2',
          'unit_code': 'g',
          'packaging_label': 'g',
          'conversion_to_base': 1,
          'sale_price': null,
          'last_cost': null,
          'is_default_sale': true,
          'is_default_receive': true,
          'is_active': true,
          'server_updated_at_ms': 1700000000000,
        }
      ],
      'aliases': [],
      'barcodes': [],
    });
    final item = (await repo.searchItems('tea', shopId: 'shop-1')).single;
    final s = await repo.toShopItemSummary(item);
    expect(s.anyPriceSet, isFalse);
    expect(s.defaultSalePrice, isNull);
  });

  test('toPartySearchResult preserves balances + type code', () async {
    await repo.applyPartiesPayload({
      'parties': [
        {
          'party_id': 'p-1',
          'shop_id': 'shop-1',
          'name': 'Hodan',
          'phone': '+252611112222',
          'type_code': 'customer',
          'receivable': 1500,
          'payable': 0,
          'is_active': true,
          'server_updated_at_ms': 1700000000000,
        }
      ],
    });
    final p =
        (await repo.searchParties('hodan', shopId: 'shop-1', typeCode: 'customer'))
            .single;
    final r = repo.toPartySearchResult(p);
    expect(r.id, 'p-1');
    expect(r.name, 'Hodan');
    expect(r.receivable, 1500);
    expect(r.payable, 0);
    expect(r.typeCode, 'customer');
  });

  test('getShopItemDetail composes header + units + aliases + barcodes',
      () async {
    await repo.applyItemsPayload(_riceWithTwoPackagings());
    final detail = await repo.getShopItemDetail('si-1');
    expect(detail, isNotNull);
    expect(detail!.header.shopItemId, 'si-1');
    expect(detail.units.length, 2);
    expect(detail.aliases.any((a) => a.aliasText == 'bariis'), isTrue);
    expect(detail.barcodes.any((b) => b.barcode == '123456'), isTrue);
  });

  test('allActiveParties skips inactive + filters by type', () async {
    await repo.applyPartiesPayload({
      'parties': [
        {
          'party_id': 'p-1',
          'shop_id': 'shop-1',
          'name': 'Customer A',
          'phone': null,
          'type_code': 'customer',
          'receivable': 0,
          'payable': 0,
          'is_active': true,
          'server_updated_at_ms': 1700000000000,
        },
        {
          'party_id': 'p-2',
          'shop_id': 'shop-1',
          'name': 'Inactive Customer',
          'phone': null,
          'type_code': 'customer',
          'receivable': 0,
          'payable': 0,
          'is_active': false,
          'server_updated_at_ms': 1700000000000,
        },
        {
          'party_id': 'p-3',
          'shop_id': 'shop-1',
          'name': 'Supplier A',
          'phone': null,
          'type_code': 'supplier',
          'receivable': 0,
          'payable': 0,
          'is_active': true,
          'server_updated_at_ms': 1700000000000,
        },
      ],
    });
    final customers =
        await repo.allActiveParties('shop-1', typeCode: 'customer');
    expect(customers.map((p) => p.partyId), ['p-1']);
    final suppliers =
        await repo.allActiveParties('shop-1', typeCode: 'supplier');
    expect(suppliers.map((p) => p.partyId), ['p-3']);
  });

  test('allActiveItems ignores inactive rows', () async {
    await repo.applyItemsPayload({
      'items': [
        {
          'shop_item_id': 'si-a',
          'shop_id': 'shop-1',
          'item_id': null,
          'display_name': 'Active',
          'category_id': null,
          'base_unit_code': 'kg',
          'current_stock': 1,
          'avg_cost': 0,
          'reorder_threshold': null,
          'is_active': true,
          'server_updated_at_ms': 1700000000000,
        },
        {
          'shop_item_id': 'si-b',
          'shop_id': 'shop-1',
          'item_id': null,
          'display_name': 'Inactive',
          'category_id': null,
          'base_unit_code': 'kg',
          'current_stock': 0,
          'avg_cost': 0,
          'reorder_threshold': null,
          'is_active': false,
          'server_updated_at_ms': 1700000000000,
        },
      ],
      'units': [],
      'aliases': [],
      'barcodes': [],
    });
    final active = await repo.allActiveItems('shop-1');
    expect(active.map((i) => i.shopItemId), ['si-a']);
  });
}

Map<String, dynamic> _riceWithTwoPackagings() => {
      'items': [
        {
          'shop_item_id': 'si-1',
          'shop_id': 'shop-1',
          'item_id': null,
          'display_name': 'Rice',
          'category_id': null,
          'base_unit_code': 'kg',
          'current_stock': 100,
          'avg_cost': 0,
          'reorder_threshold': null,
          'is_active': true,
          'server_updated_at_ms': 1700000000000,
        }
      ],
      'units': [
        {
          'shop_item_unit_id': 'siu-base',
          'shop_item_id': 'si-1',
          'unit_code': 'kg',
          'packaging_label': 'kg',
          'conversion_to_base': 1,
          'sale_price': 18000,
          'last_cost': null,
          'is_default_sale': false,
          'is_default_receive': true,
          'is_active': true,
          'server_updated_at_ms': 1700000000000,
        },
        {
          'shop_item_unit_id': 'siu-bag',
          'shop_item_id': 'si-1',
          'unit_code': 'bag',
          'packaging_label': 'Rice — 5kg',
          'conversion_to_base': 5,
          'sale_price': 80000,
          'last_cost': 50000,
          'is_default_sale': true,
          'is_default_receive': false,
          'is_active': true,
          'server_updated_at_ms': 1700000000000,
        },
      ],
      'aliases': [
        {'shop_item_id': 'si-1', 'alias': 'bariis', 'is_display': false},
      ],
      'barcodes': [
        {
          'barcode': '123456',
          'shop_item_unit_id': 'siu-bag',
          'is_primary': true,
        }
      ],
    };
