// Shared widget-test harness: wraps any screen with the same MaterialApp,
// localization delegates, and providers the real app gives it, so each
// screen test can `pumpWidget(wrapWithApp(MyScreen(...)))` without
// boilerplate. Mirrors the production setup in lib/main.dart.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/receive/bono_image_cache.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/expense/expense_controller.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/payment/payment_controller.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/pending_post_dao.dart';
import 'package:dukan/sale/cart_controller.dart';
import 'package:dukan/search/connectivity_status.dart';
import 'package:dukan/shared/fallback_localizations.dart';
import 'package:dukan/shared/locale_controller.dart';
import 'package:dukan/sync/local_repository.dart';

import 'fakes.dart';

/// Wraps [child] in the providers + localization scaffolding the screens
/// expect at runtime.
///
/// Pass [authController] (typically a `FakeAuthController` from
/// `test/shared/fakes.dart`) to inject controller state into screens that
/// read it via `context.read<AuthController>()` / `context.watch<...>()`.
///
/// Pass [locale] to test screens under the Somali locale.
Widget wrapWithApp(
  Widget child, {
  AuthController? authController,
  ShopApi? shopApi,
  CartController? cartController,
  ReceiveController? receiveController,
  PaymentController? paymentController,
  ExpenseController? expenseController,
  LocaleController? localeController,
  OfflineQueueController? offlineQueueController,
  ConfigResolver? configResolver,
  LocalRepository? localRepository,
  ConnectivityStatus? connectivityStatus,
  BonoImageCache? bonoImageCache,
  Locale locale = const Locale('en'),
}) {
  // A bono cache backed by the test in-memory DB so screens that read
  // context.read<BonoImageCache>() (attach, View bono) work.
  final bonoCache =
      bonoImageCache ?? BonoImageCache(database: AppDatabase.instance());
  // Default no-op offline queue so the QueueStatusPill in app bars
  // can render even when a specific test doesn't care about queue
  // behaviour. Executor is a no-op (returns void) so any enqueued
  // post drains successfully on the first attempt without timers
  // piling up. Tests that want explicit failure semantics inject
  // their own controller.
  final queue = offlineQueueController ??
      OfflineQueueController(
        dao: PendingPostDao(AppDatabase.instance()),
        // Drain enqueued posts to the provided (fake) ShopApi so the
        // mutation path (#390) reaches it and tests can assert the RPC
        // fired. Falls back to a no-op when no api is supplied. Tests
        // wanting custom drain/failure semantics inject their own
        // controller and bypass this default.
        executor:
            shopApi != null ? PostExecutor(shopApi).execute : (_) async {},
        // Zero backoff so the retry timer is effectively synchronous
        // and pumpAndSettle drains it without holding pending timers
        // past the test.
        backoff: (_) => Duration.zero,
        // The queue now retries transient failures FOREVER, which would
        // wedge pumpAndSettle on a fake api that always throws. In tests
        // treat every drain failure as terminal so the post parks after
        // one attempt and the tree settles (matches the pre-never-expire
        // effective behaviour). Tests wanting real retry semantics inject
        // their own controller.
        isPermanentError: (_) => true,
      );

  final providers = <SingleChildWidget>[
    ChangeNotifierProvider<LocaleController>.value(
      value: localeController ?? (LocaleController()..setLocale(locale)),
    ),
    if (authController != null)
      ChangeNotifierProvider<AuthController>.value(value: authController),
    if (shopApi != null) Provider<ShopApi>.value(value: shopApi),
    if (cartController != null)
      ChangeNotifierProvider<CartController>.value(value: cartController),
    if (receiveController != null)
      ChangeNotifierProvider<ReceiveController>.value(
        value: receiveController,
      ),
    if (paymentController != null)
      ChangeNotifierProvider<PaymentController>.value(
        value: paymentController,
      ),
    if (expenseController != null)
      ChangeNotifierProvider<ExpenseController>.value(
        value: expenseController,
      ),
    ChangeNotifierProvider<OfflineQueueController>.value(value: queue),
    // #383: only provide ConfigResolver when the test asks for
    // one. With no resolver in scope `useLocalDb` returns false,
    // which is the pre-existing test default (network path).
    // Queue-path tests that need the local-first branch pass
    // their own FakeConfigResolver with use_local_db: true.
    if (configResolver != null)
      ChangeNotifierProvider<ConfigResolver>.value(value: configResolver),
    // Always provide a LocalRepository: production (auth_bootstrap.dart)
    // provides it unconditionally, and the screens' mutation path (#390
    // optimistic mirror writes) reads it regardless of useLocalDb. The
    // default thin FakeLocalRepository forwards reads to the test's
    // FakeShopApi; tests can pass their own to override.
    Provider<LocalRepository>.value(
      value: localRepository ??
          FakeLocalRepository(
            shopApi: (shopApi is FakeShopApi) ? shopApi : FakeShopApi(),
          ),
    ),
    // Search reads this to gate the network fallback. Default online so tests
    // exercise the network branch as before; pass one with online:false to
    // test offline behaviour.
    ChangeNotifierProvider<ConnectivityStatus>.value(
      value: connectivityStatus ?? ConnectivityStatus(),
    ),
    Provider<BonoImageCache>.value(value: bonoCache),
  ];

  return MultiProvider(
    providers: providers,
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FallbackMaterialLocalizationsDelegate(),
        FallbackWidgetsLocalizationsDelegate(),
        FallbackCupertinoLocalizationsDelegate(),
      ],
      home: child,
    ),
  );
}
