import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wrap.dart';

void main() {
  testWidgets('wrapWithApp boots a screen with localization + locale switch', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(
        const Scaffold(body: Text('hello')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('wrapWithApp honours Somali locale', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        const Scaffold(body: Text('hello')),
        locale: const Locale('so'),
      ),
    );
    await tester.pumpAndSettle();
    // The widget tree should mount cleanly under the Somali locale even
    // though Flutter's Global*Localizations don't include it. Regression
    // guard against the "No MaterialLocalizations found" crash.
    expect(find.text('hello'), findsOneWidget);
  });
}
