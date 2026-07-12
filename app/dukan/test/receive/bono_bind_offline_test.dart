import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/receive/bono_bind_item_sheet.dart';
import 'package:dukan/search/connectivity_status.dart';
import 'package:dukan/sync/local_repository.dart';

import '../shared/fakes.dart';
import '../shared/test_database.dart';
import '../shared/wrap.dart';

void main() {
  testWidgets(
    'offline: bono bind picker shows local matches (was network-only → blank)',
    (tester) async {
      final db = await openTestDatabase();
      final repo = LocalRepository(Future.value(db));
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
        'barcodes': const [],
      });

      final api = FakeShopApi();
      var searchCalled = false;
      api.onSearchItems = (_, _, _, _, _, _) async {
        searchCalled = true;
        return const <ItemSearchResult>[];
      };
      final shop = fakeShop();

      await tester.pumpWidget(
        wrapWithApp(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showBonoBindItemPicker(
                    context,
                    shop: shop,
                    initialQuery: 'Cola',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          shopApi: api,
          localRepository: repo,
          configResolver:
              FakeConfigResolver(values: const {'use_local_db': true}),
          connectivityStatus: ConnectivityStatus(online: false),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The local item is listed even though we're offline and the network
      // search is stubbed empty — the offline hole is closed.
      expect(find.text('Cola'), findsAtLeastNWidgets(1));
      expect(searchCalled, isFalse,
          reason: 'offline bind must resolve from the mirror, not the network');
    },
  );
}
