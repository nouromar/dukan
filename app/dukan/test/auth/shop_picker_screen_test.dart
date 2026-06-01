import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/auth/shop_picker_screen.dart';

import '../shared/fakes.dart';
import '../shared/wrap.dart';

void main() {
  late FakeAuthController auth;

  setUp(() {
    auth = FakeAuthController();
  });

  Future<void> pumpPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(const ShopPickerScreen(), authController: auth),
    );
  }

  testWidgets('lists every shop the controller exposes', (tester) async {
    auth.setShops([
      fakeShop(id: 's1', name: 'Hodan Shop'),
      fakeShop(id: 's2', name: 'Asal Shop'),
    ]);

    await pumpPicker(tester);

    expect(find.text('Hodan Shop'), findsOneWidget);
    expect(find.text('Asal Shop'), findsOneWidget);
  });

  testWidgets('tapping a shop sets it as the selected shop', (tester) async {
    final hodan = fakeShop(id: 's1', name: 'Hodan Shop');
    final asal = fakeShop(id: 's2', name: 'Asal Shop');
    auth.setShops([hodan, asal]);
    // setSelectedShop(null) so getter does not auto-pick the only shop.
    auth.setSelectedShop(null);

    await pumpPicker(tester);
    await tester.tap(find.text('Asal Shop'));
    await tester.pumpAndSettle();

    expect(auth.selectedShop?.id, 's2');
  });
}
