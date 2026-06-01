import 'package:dukan/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Dukan prototype opens', (tester) async {
    await tester.pumpWidget(const DukanApp());
    await tester.pumpAndSettle();
    expect(find.text('Dukan'), findsWidgets);
  });
}
