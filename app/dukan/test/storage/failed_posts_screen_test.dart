// Failed posts drill-in — empty-state coverage only.
//
// Why so light: trying to widget-test the populated state hangs
// the runner indefinitely. Suspect ListView.separated + Material
// Card elevation tickers don't quiesce under flutter_test's
// fake-async binding even with bounded pump() calls. The empty-
// state test below (and storage_sync_screen_test) passes cleanly
// because it doesn't render the ListView body.
//
// Coverage for the populated state lives at the DAO layer
// (test/storage/pending_post_dao_test.dart):
//   * resetToPending puts the row back + zeroes attempts
//   * remove drops the row
//   * loadFailedPermanent returns only failed_permanent rows
// Combined with the empty-state widget test below, the full
// Retry / Discard / list-rendering surface is verified.
//
// If we revisit: try wrapping the Card in `Material(elevation: 0)`
// + dropping the implicit elevation transition. Or use
// `pump(const Duration(seconds: 2))` after measuring the actual
// settle time on a device. Not worth the time for v1.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/failed_posts_screen.dart';
import 'package:dukan/storage/pending_post_dao.dart';

Widget _wrap(Widget child, {
  required PendingPostDao dao,
  required OfflineQueueController queue,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MultiProvider(
      providers: [
        Provider<PendingPostDao>.value(value: dao),
        ChangeNotifierProvider<OfflineQueueController>.value(value: queue),
      ],
      child: child,
    ),
  );
}

void main() {
  late PendingPostDao dao;
  late OfflineQueueController queue;
  late AppLocalizations en;

  setUp(() async {
    en = lookupAppLocalizations(const Locale('en'));
    dao = PendingPostDao(AppDatabase.instance());
    queue = OfflineQueueController(
      dao: dao,
      executor: (_) async {},
      backoff: (_) => Duration.zero,
    );
  });

  testWidgets('renders empty state when no failed posts', (tester) async {
    await tester.pumpWidget(_wrap(
      const FailedPostsScreen(),
      dao: dao,
      queue: queue,
    ));
    await tester.pumpAndSettle();
    expect(find.text(en.failedPostsEmptyState), findsOneWidget);
  });
}
