import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/scanner/scan_lookup.dart';
import 'package:dukan/sync/local_repository.dart';

import '../shared/fakes.dart';
import '../shared/test_database.dart';

ItemSearchResult _catalog(String name) => ItemSearchResult(
      shopItemId: null,
      itemId: 'g-$name',
      displayName: name,
      baseUnitCode: 'pcs',
      baseUnitLabel: 'pcs',
      defaultShopItemUnitId: null,
      defaultUnitCode: null,
      defaultUnitLabel: null,
      defaultUnitConversionToBase: null,
      defaultUnitSalePrice: null,
      defaultUnitLastCost: null,
      currentStock: null,
      packagingLabel: null,
      isActivated: false,
      rankReason: 'barcode_match',
    );

void main() {
  late LocalRepository repo;
  late FakeShopApi api;

  setUp(() async {
    final db = await openTestDatabase();
    repo = LocalRepository(Future.value(db));
    api = FakeShopApi();
    await repo.applyItemsPayload({
      'items': [
        {
          'shop_item_id': 'si-cola',
          'shop_id': 'shop-1',
          'item_id': null,
          'display_name': 'Cola',
          'category_id': null,
          'base_unit_code': 'bottle',
          'current_stock': 5,
          'avg_cost': 0,
          'reorder_threshold': null,
          'sale_count': 0,
          'last_sold_at_ms': null,
          'is_active': true,
          'server_updated_at_ms': 1700000000000,
        },
      ],
      'units': [
        {
          'shop_item_unit_id': 'siu-cola',
          'shop_item_id': 'si-cola',
          'unit_code': 'bottle',
          'packaging_label': 'bottle',
          'conversion_to_base': 1,
          'sale_price': 100,
          'last_cost': null,
          'is_default_sale': true,
          'is_default_receive': true,
          'is_active': true,
          'server_updated_at_ms': 1700000000000,
        },
      ],
      'aliases': const [],
      'barcodes': [
        {
          'barcode': '5000000000012',
          'shop_item_unit_id': 'siu-cola',
          'is_primary': true,
        },
      ],
    });
  });

  test('local hit → local, network never called', () async {
    var calls = 0;
    api.onSearchItems = (_, _, _, _, _, _) async {
      calls++;
      return const [];
    };
    final r = await resolveScannedCode(
      repo: repo, api: api, online: true,
      shopId: 'shop-1', code: '5000000000012', screen: 'sale', locale: 'en',
    );
    expect(r?.shopItemId, 'si-cola');
    expect(calls, 0);
  });

  test('offline miss → null, network NOT called', () async {
    var calls = 0;
    api.onSearchItems = (_, _, _, _, _, _) async {
      calls++;
      return const [];
    };
    final r = await resolveScannedCode(
      repo: repo, api: api, online: false,
      shopId: 'shop-1', code: '9999999999999', screen: 'sale', locale: 'en',
    );
    expect(r, isNull);
    expect(calls, 0);
  });

  test('online miss → network fallback probe', () async {
    var calls = 0;
    api.onSearchItems = (_, _, _, _, _, _) async {
      calls++;
      return [_catalog('Fanta')];
    };
    final r = await resolveScannedCode(
      repo: repo, api: api, online: true,
      shopId: 'shop-1', code: '9999999999999', screen: 'sale', locale: 'en',
    );
    expect(calls, 1);
    expect(r?.displayName, 'Fanta');
  });

  test('thin client (no repo) → network', () async {
    var calls = 0;
    api.onSearchItems = (_, _, _, _, _, _) async {
      calls++;
      return [_catalog('Fanta')];
    };
    final r = await resolveScannedCode(
      repo: null, api: api, online: true,
      shopId: 'shop-1', code: '5000000000012', screen: 'sale', locale: 'en',
    );
    expect(calls, 1);
    expect(r?.displayName, 'Fanta');
  });
}
