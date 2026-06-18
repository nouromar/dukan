import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_state_cache.dart';
import 'package:dukan/scanner/scanner_settings.dart';

ShopSummary _shop({
  String id = 'shop-a',
  String name = 'Main Shop',
  String setupStatus = 'ready',
  String currencyCode = 'USD',
  String currencySymbol = r'$',
  DateTime? dismissed,
  ScannerSettings? scanner,
}) {
  return ShopSummary(
    id: id,
    name: name,
    setupStatus: setupStatus,
    currencyCode: currencyCode,
    currencySymbol: currencySymbol,
    defaultLanguageCode: 'en',
    timezone: 'Africa/Mogadishu',
    onboardingDismissedAt: dismissed,
    scannerSettings: scanner ?? ScannerSettings.defaults,
  );
}

void main() {
  test('get returns null when nothing cached for the user', () async {
    expect(await AuthStateCache.get('user-1'), isNull);
  });

  test('put then get round-trips the shop list + selection', () async {
    final shopA = _shop(id: 'a', name: 'Alpha');
    final shopB = _shop(id: 'b', name: 'Beta', currencyCode: 'SLSH', currencySymbol: 'SLSH');
    await AuthStateCache.put(
      'user-1',
      shops: [shopA, shopB],
      currencySymbols: const {'USD': r'$', 'SLSH': 'SLSH'},
      selectedShopId: 'b',
    );
    final got = await AuthStateCache.get('user-1');
    expect(got, isNotNull);
    expect(got!.shops, hasLength(2));
    expect(got.shops[0].id, 'a');
    expect(got.shops[0].name, 'Alpha');
    expect(got.shops[0].currencySymbol, r'$');
    expect(got.shops[1].id, 'b');
    expect(got.shops[1].currencyCode, 'SLSH');
    expect(got.shops[1].currencySymbol, 'SLSH');
    expect(got.selectedShopId, 'b');
  });

  test('cache is per-user (no cross-leak)', () async {
    await AuthStateCache.put(
      'user-1',
      shops: [_shop(id: 'a', name: 'User 1 Shop')],
      currencySymbols: const {'USD': r'$'},
    );
    await AuthStateCache.put(
      'user-2',
      shops: [_shop(id: 'z', name: 'User 2 Shop')],
      currencySymbols: const {'USD': r'$'},
    );
    final got1 = await AuthStateCache.get('user-1');
    final got2 = await AuthStateCache.get('user-2');
    expect(got1!.shops.single.name, 'User 1 Shop');
    expect(got2!.shops.single.name, 'User 2 Shop');
  });

  test('put with empty shops is a no-op (nothing to render-fast)', () async {
    await AuthStateCache.put(
      'user-1',
      shops: const [],
      currencySymbols: const {'USD': r'$'},
    );
    expect(await AuthStateCache.get('user-1'), isNull);
  });

  test('clear removes the entry for one user only', () async {
    await AuthStateCache.put(
      'user-1',
      shops: [_shop()],
      currencySymbols: const {'USD': r'$'},
    );
    await AuthStateCache.put(
      'user-2',
      shops: [_shop(id: 'x')],
      currencySymbols: const {'USD': r'$'},
    );
    await AuthStateCache.clear('user-1');
    expect(await AuthStateCache.get('user-1'), isNull);
    expect(await AuthStateCache.get('user-2'), isNotNull);
  });

  test('corrupt JSON is dropped silently and returns null', () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'auth_state:user-1': 'not json'},
    );
    expect(await AuthStateCache.get('user-1'), isNull);
    expect(await AuthStateCache.get('user-1'), isNull);
  });

  test('scanner_settings survive the round-trip', () async {
    final shop = _shop(
      scanner: const ScannerSettings(
        rearmMs: 1234,
        hidMaxInterKeyGapMs: 77,
        hidMaxBurstWindowMs: 333,
        hidMinBurstLength: 6,
      ),
    );
    await AuthStateCache.put(
      'user-1',
      shops: [shop],
      currencySymbols: const {'USD': r'$'},
    );
    final got = await AuthStateCache.get('user-1');
    final scanner = got!.shops.single.scannerSettings;
    expect(scanner.rearmMs, 1234);
    expect(scanner.hidMaxInterKeyGapMs, 77);
    expect(scanner.hidMaxBurstWindowMs, 333);
    expect(scanner.hidMinBurstLength, 6);
  });
}
