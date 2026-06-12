import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/shared/friendly_error_screen.dart';

import 'wrap.dart';

void main() {
  testWidgets(
    'FriendlyErrorScreen surfaces title, message, retry, and sign-out',
    (tester) async {
      final en = lookupAppLocalizations(const Locale('en'));
      var retryCount = 0;
      var signOutCount = 0;

      await tester.pumpWidget(
        wrapWithApp(
          FriendlyErrorScreen(
            title: 'Cannot reach server',
            message: 'Check your internet connection.',
            onRetry: () => retryCount++,
            onSignOut: () => signOutCount++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Title appears in both the app bar and the body.
      expect(find.text('Cannot reach server'), findsWidgets);
      expect(find.text('Check your internet connection.'), findsOneWidget);
      expect(find.text(en.tryAgain), findsOneWidget);

      await tester.tap(find.text(en.tryAgain));
      await tester.pump();
      expect(retryCount, 1);

      await tester.tap(find.byTooltip(en.signOut));
      await tester.pump();
      expect(signOutCount, 1);
    },
  );
}
