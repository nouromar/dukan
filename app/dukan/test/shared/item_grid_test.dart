import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/shared/item_grid.dart';

Future<SliverGridDelegate> pumpDelegate(
    WidgetTester tester, double textScale) async {
  late SliverGridDelegate delegate;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Builder(
        builder: (context) {
          delegate = itemGridDelegate(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return delegate;
}

void main() {
  testWidgets('itemGridDelegate is width-responsive (max-extent), not a fixed '
      'column count', (tester) async {
    final d = await pumpDelegate(tester, 1.0);
    expect(d, isA<SliverGridDelegateWithMaxCrossAxisExtent>());
    final m = d as SliverGridDelegateWithMaxCrossAxisExtent;
    // Column count derives from width via maxCrossAxisExtent (2 on a narrow
    // phone, 3+ on a wider one) rather than a hard-coded 2.
    expect(m.maxCrossAxisExtent, 190);
    expect(m.mainAxisExtent, 110); // baseline tile height at 1.0 scale
  });

  testWidgets('tile height grows with the OS font scale, clamped at 1.6x',
      (tester) async {
    final base = (await pumpDelegate(tester, 1.0))
        as SliverGridDelegateWithMaxCrossAxisExtent;
    final big = (await pumpDelegate(tester, 2.0))
        as SliverGridDelegateWithMaxCrossAxisExtent;
    expect(big.mainAxisExtent, greaterThan(base.mainAxisExtent!));
    // A huge accessibility font is clamped so tiles don't fill the screen.
    expect(big.mainAxisExtent, closeTo(110 * 1.6, 0.01));
  });
}
