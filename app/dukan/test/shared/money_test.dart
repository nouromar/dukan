import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/shared/money.dart';

ShopSummary _shop({required String symbol, required int decimals}) =>
    ShopSummary(
      id: 's',
      name: 'Shop',
      setupStatus: 'ready',
      currencyCode: 'X',
      currencySymbol: symbol,
      currencyDecimals: decimals,
      defaultLanguageCode: 'en',
      timezone: 'UTC',
      onboardingDismissedAt: null,
    );

void main() {
  test('formatMoney respects currency decimals + symbol spacing', () {
    // 2-decimal, single-char symbol → adjacent.
    expect(formatMoney(1.5, _shop(symbol: r'$', decimals: 2)), r'$1.50');
    // 0-decimal shillings, multi-char symbol → space, and NO ".00".
    expect(formatMoney(5000, _shop(symbol: 'Sh.So', decimals: 0)), 'Sh.So 5000');
    expect(formatMoney(5000, _shop(symbol: 'SLSH', decimals: 0)), 'SLSH 5000');
  });

  test('currencyDecimals defaults to 2 when not provided', () {
    const shop = ShopSummary(
      id: 's',
      name: 'Shop',
      setupStatus: 'ready',
      currencyCode: 'USD',
      currencySymbol: r'$',
      defaultLanguageCode: 'en',
      timezone: 'UTC',
      onboardingDismissedAt: null,
    );
    expect(shop.currencyDecimals, 2);
    expect(formatMoney(2, shop), r'$2.00');
  });
}
