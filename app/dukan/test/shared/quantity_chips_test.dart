import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/shared/quantity_chips.dart';

void main() {
  testWidgets('folds the learned qty into the sorted defaults + marks it',
      (tester) async {
    num? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QuantityChips(learnedQty: 3, onSelected: (v) => picked = v),
      ),
    ));

    // Defaults 1,2,5 + learned 3, sorted → 1,2,3,5.
    for (final n in ['1', '2', '3', '5']) {
      expect(find.widgetWithText(ActionChip, n), findsOneWidget);
    }
    // The learned chip carries the history mark.
    expect(find.byIcon(Icons.history), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, '3'));
    expect(picked, 3);
  });

  testWidgets('without a learned qty shows just the defaults, no mark',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: QuantityChips(onSelected: (_) {})),
    ));

    expect(find.byType(ActionChip), findsNWidgets(3)); // 1, 2, 5
    expect(find.byIcon(Icons.history), findsNothing);
  });
}
