import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/shared/expandable_line_list.dart';

ExpandableLineList _list({
  required int count,
  required double maxHeight,
  bool fill = false,
  VoidCallback? onExpand,
}) {
  return ExpandableLineList(
    itemCount: count,
    maxHeight: maxHeight,
    fill: fill,
    onExpandRequested: onExpand,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
  );
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      height: 200,
      child: Column(children: [child]),
    ),
  ),
);

void main() {
  testWidgets('overflow cue appears when content exceeds the cap', (
    tester,
  ) async {
    // 10 rows × 60dp = 600 > 120 cap → scrollable → cue.
    await tester.pumpWidget(_host(_list(count: 10, maxHeight: 120)));
    await tester.pump(); // let the post-frame overflow re-check + setState run
    await tester.pump();
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
  });

  testWidgets('no overflow cue when everything fits the cap', (tester) async {
    // 1 row × 60dp < 120 cap → not scrollable → no cue.
    await tester.pumpWidget(_host(_list(count: 1, maxHeight: 120)));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
  });

  testWidgets('tapping the cue fires onExpandRequested (grow to full)', (
    tester,
  ) async {
    var expanded = false;
    await tester.pumpWidget(
      _host(_list(count: 10, maxHeight: 120, onExpand: () => expanded = true)),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    expect(expanded, isTrue);
  });

  testWidgets('fill mode renders as Expanded without overflow', (tester) async {
    // fill:true → Expanded inside the 200dp Column; 10×60 overflows so it
    // scrolls, but there must be no RenderFlex overflow.
    await tester.pumpWidget(
      _host(_list(count: 10, maxHeight: 100, fill: true)),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ExpandableLineList), findsOneWidget);
  });
}
