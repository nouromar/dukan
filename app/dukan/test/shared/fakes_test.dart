import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('FakeShopApi returns canned default reference lists', () async {
    final api = FakeShopApi();
    final languages = await api.listLanguages();
    final currencies = await api.listCurrencies();
    expect(languages.map((l) => l.code), containsAll(['en', 'so']));
    expect(currencies.map((c) => c.code), containsAll(['USD', 'SLSH']));
  });

  test('FakeAuthController.cancelOtp only fires when there is a pending phone', () {
    final controller = FakeAuthController();
    var notified = 0;
    controller.addListener(() => notified++);

    controller.cancelOtp();
    expect(notified, 0, reason: 'no-op cancel should not notify');

    controller.setPendingPhone('+252612345678');
    expect(notified, 1);

    controller.cancelOtp();
    expect(notified, 2);
    expect(controller.pendingPhone, isNull);
  });

  test('FakeShopApi.searchItems replays the installed callback', () async {
    final api = FakeShopApi();
    String? capturedShop;
    String? capturedQuery;
    api.onSearchItems = (shopId, query, limit, screen) async {
      capturedShop = shopId;
      capturedQuery = query;
      return [fakeActivatedItem(), fakeCatalogCandidate()];
    };

    final results = await api.searchItems(
      shopId: 'shop-1',
      query: 'rice',
    );

    expect(capturedShop, 'shop-1');
    expect(capturedQuery, 'rice');
    expect(results, hasLength(2));
    expect(results.first.isActivated, isTrue);
    expect(results.last.isActivated, isFalse);
  });

  test('FakeAuthController.signOut clears state and notifies', () async {
    final controller = FakeAuthController(
      shops: [fakeShop()],
      selectedShop: fakeShop(),
      pendingPhone: '+252612345678',
    );
    var notified = 0;
    controller.addListener(() => notified++);

    await controller.signOut();

    expect(controller.shops, isEmpty);
    expect(controller.selectedShop, isNull);
    expect(controller.pendingPhone, isNull);
    expect(notified, greaterThanOrEqualTo(1));
  });

  test('fakeShop / fakeTemplate / fakeActivatedItem produce reasonable defaults', () {
    expect(fakeShop().setupStatus, 'ready');
    expect(fakeShop(setupStatus: 'not_started').setupStatus, 'not_started');
    expect(fakeTemplate().code, 'grocery');
    expect(fakeActivatedItem().isActivated, isTrue);
    expect(fakeCatalogCandidate().isActivated, isFalse);
    expect(fakeCatalogCandidate().itemId, isNull);
  });
}
