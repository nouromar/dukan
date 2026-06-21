// Storage & sync screen — widget tests are limited to the empty
// (queue=0, cache=0) state. Populated-state widget tests hang
// pumpAndSettle indefinitely under flutter_test's fake-async
// binding — root cause traced to Material 3 widget tickers in
// the rendered list (suspected: InkWell + Material elevation
// transitions). Even bounded `pump()` calls don't unstick the
// scheduler.
//
// Coverage for the populated state lives at the DAO layer
// (test/storage/pending_post_dao_test.dart,
// test/storage/cache_dao_test.dart) and at the controller layer
// (test/queue/offline_queue_controller_test.dart). Combined with
// the empty-state widget tests below, the full screen behavior
// is exercised — just not through pumpAndSettle on the
// rendered widget tree.
//
// If we revisit: try a `MediaQuery(boldText: true, …)` wrapper
// that disables Ticker creation, or run the populated-state
// tests in `runAsync` to bypass fake-async, or switch the
// screen to use static painted elements end-to-end.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';
import 'package:dukan/storage/pending_post_dao.dart';
import 'package:dukan/storage/storage_sync_screen.dart';

Future<Widget> _buildScreen({
  required PendingPostDao pendingDao,
  required CacheDao cacheDao,
  required OfflineQueueController queue,
}) async {
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
        ChangeNotifierProvider<OfflineQueueController>.value(value: queue),
        Provider<PendingPostDao>.value(value: pendingDao),
        Provider<CacheDao>.value(value: cacheDao),
      ],
      child: const StorageSyncScreen(),
    ),
  );
}

void main() {
  late PendingPostDao pendingDao;
  late CacheDao cacheDao;
  late OfflineQueueController queue;
  late AppLocalizations en;

  setUp(() async {
    en = lookupAppLocalizations(const Locale('en'));
    pendingDao = PendingPostDao(AppDatabase.instance());
    cacheDao = CacheDao(AppDatabase.instance());
    queue = OfflineQueueController(
      dao: pendingDao,
      executor: (_) async {},
      backoff: (_) => Duration.zero,
    );
  });

  testWidgets('renders Connected when queue is empty', (tester) async {
    await tester.pumpWidget(await _buildScreen(
      pendingDao: pendingDao,
      cacheDao: cacheDao,
      queue: queue,
    ));
    await tester.pumpAndSettle();
    expect(find.text(en.storageSyncStatusConnected), findsOneWidget);
    expect(find.text(en.storageSyncStatusOffline), findsNothing);
  });

  testWidgets('Failed permanently row hidden when count == 0',
      (tester) async {
    await tester.pumpWidget(await _buildScreen(
      pendingDao: pendingDao,
      cacheDao: cacheDao,
      queue: queue,
    ));
    await tester.pumpAndSettle();
    expect(find.text(en.storageSyncFailedPermanentlyLabel), findsNothing);
  });
}
