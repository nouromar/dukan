import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/search/search_service.dart';
import 'package:dukan/sync/local_repository.dart';

import '../shared/fakes.dart';
import '../shared/test_database.dart';

Map<String, dynamic> _item(String id, String name) => {
      'shop_item_id': id,
      'shop_id': 'shop-1',
      'item_id': null,
      'display_name': name,
      'category_id': null,
      'base_unit_code': 'pcs',
      'current_stock': 5,
      'avg_cost': 0,
      'reorder_threshold': null,
      'sale_count': 0,
      'last_sold_at_ms': null,
      'is_active': true,
      'server_updated_at_ms': 1700000000000,
    };

Map<String, dynamic> _unit(String id, String itemId) => {
      'shop_item_unit_id': id,
      'shop_item_id': itemId,
      'unit_code': 'pcs',
      'packaging_label': 'pcs',
      'conversion_to_base': 1,
      'sale_price': 100,
      'last_cost': null,
      'is_default_sale': true,
      'is_default_receive': true,
      'is_active': true,
      'server_updated_at_ms': 1700000000000,
    };

Map<String, dynamic> _party(String id, String name, String type) => {
      'party_id': id,
      'shop_id': 'shop-1',
      'name': name,
      'phone': null,
      'type_code': type,
      'receivable': 0,
      'payable': 0,
      'is_active': true,
      'server_updated_at_ms': 1700000000000,
    };

// A network-only "global catalog" row (unactivated).
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
      rankReason: 'global',
    );

void main() {
  late LocalRepository repo;
  late FakeShopApi api;

  setUp(() async {
    final db = await openTestDatabase();
    repo = LocalRepository(Future.value(db));
    api = FakeShopApi();
    await repo.applyItemsPayload({
      'items': [_item('si-cola', 'Cola')],
      'units': [_unit('siu-cola', 'si-cola')],
      'aliases': const [],
      'barcodes': const [],
    });
    await repo.applyPartiesPayload({
      'parties': [_party('p-ahmed', 'Ahmed', 'customer')],
    });
  });

  group('runItemSearch', () {
    test('local hit → local, network never called', () async {
      var calls = 0;
      api.onSearchItems = (_, _, _, _, _, _) async {
        calls++;
        return const [];
      };
      final r = await runItemSearch(
        repo: repo, api: api, online: true,
        shopId: 'shop-1', query: 'Cola', screen: 'sale',
      );
      expect(r.map((e) => e.displayName), ['Cola']);
      expect(calls, 0);
    });

    test('local empty + online → network fallback (catalog)', () async {
      var calls = 0;
      api.onSearchItems = (_, _, _, _, _, _) async {
        calls++;
        return [_catalog('Fanta')];
      };
      final r = await runItemSearch(
        repo: repo, api: api, online: true,
        shopId: 'shop-1', query: 'Fanta', screen: 'sale',
      );
      expect(calls, 1);
      expect(r.single.displayName, 'Fanta');
      expect(r.single.isActivated, isFalse);
    });

    test('local empty + offline → empty, network NOT called', () async {
      var calls = 0;
      api.onSearchItems = (_, _, _, _, _, _) async {
        calls++;
        return const [];
      };
      final r = await runItemSearch(
        repo: repo, api: api, online: false,
        shopId: 'shop-1', query: 'Fanta', screen: 'sale',
      );
      expect(r, isEmpty);
      expect(calls, 0);
    });

    test('thin client (no repo) → network', () async {
      var calls = 0;
      api.onSearchItems = (_, _, _, _, _, _) async {
        calls++;
        return [_catalog('Cola')];
      };
      final r = await runItemSearch(
        repo: null, api: api, online: true,
        shopId: 'shop-1', query: 'Cola', screen: 'sale',
      );
      expect(calls, 1);
      expect(r.single.displayName, 'Cola');
    });

    test('thin client + offline → empty, no doomed request', () async {
      var calls = 0;
      api.onSearchItems = (_, _, _, _, _, _) async {
        calls++;
        return [_catalog('Cola')];
      };
      final r = await runItemSearch(
        repo: null, api: api, online: false,
        shopId: 'shop-1', query: 'Cola', screen: 'sale',
      );
      expect(r, isEmpty);
      expect(calls, 0);
    });

    test('discover → network-first even with local hits; local when offline',
        () async {
      api.onSearchItems = (_, _, _, _, _, _) async => [_catalog('Cola Zero')];
      final online = await runItemSearch(
        repo: repo, api: api, online: true,
        shopId: 'shop-1', query: 'Cola', screen: 'sale', discover: true,
      );
      expect(online.single.displayName, 'Cola Zero'); // catalog, not local

      final offline = await runItemSearch(
        repo: repo, api: api, online: false,
        shopId: 'shop-1', query: 'Cola', screen: 'sale', discover: true,
      );
      expect(offline.map((e) => e.displayName), ['Cola']); // local fallback
    });
  });

  group('runPartySearch', () {
    test('local hit → local, no network', () async {
      var calls = 0;
      api.onSearchParties = (_, _, _, _) async {
        calls++;
        return const [];
      };
      final r = await runPartySearch(
        repo: repo, api: api, online: true,
        shopId: 'shop-1', query: 'Ahmed', typeCode: 'customer',
      );
      expect(r.map((e) => e.name), ['Ahmed']);
      expect(calls, 0);
    });

    test('local empty + online → network; offline → empty', () async {
      var calls = 0;
      api.onSearchParties = (_, _, _, _) async {
        calls++;
        return const [
          PartySearchResult(
            id: 'p-x', name: 'Zara', phone: null,
            typeCode: 'customer', receivable: 0, payable: 0,
          ),
        ];
      };
      final online = await runPartySearch(
        repo: repo, api: api, online: true,
        shopId: 'shop-1', query: 'Zara', typeCode: 'customer',
      );
      expect(calls, 1);
      expect(online.single.name, 'Zara');

      calls = 0;
      final offline = await runPartySearch(
        repo: repo, api: api, online: false,
        shopId: 'shop-1', query: 'Zara', typeCode: 'customer',
      );
      expect(offline, isEmpty);
      expect(calls, 0);
    });
  });
}
