import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/shared/loading_screen.dart';

import 'wrap.dart';

void main() {
  testWidgets('LoadingScreen renders the app title + a progress indicator',
      (tester) async {
    final en = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(wrapWithApp(const LoadingScreen()));
    await tester.pump();

    expect(find.text(en.appTitle), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
