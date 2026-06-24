// Shared widget-test harness: wraps any screen with the same MaterialApp,
// localization delegates, and providers the real app gives it, so each
// screen test can `pumpWidget(wrapWithApp(MyScreen(...)))` without
// boilerplate. Mirrors the production setup in lib/main.dart.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/expense/expense_controller.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/payment/payment_controller.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/pending_post_dao.dart';
import 'package:dukan/sale/cart_controller.dart';
import 'package:dukan/shared/fallback_localizations.dart';
import 'package:dukan/shared/locale_controller.dart';

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
  Locale locale = const Locale('en'),
}) {
  // Default no-op offline queue so the QueueStatusPill in app bars
  // can render even when a specific test doesn't care about queue
  // behaviour. Executor is a no-op (returns void) so any enqueued
  // post drains successfully on the first attempt without timers
  // piling up. Tests that want explicit failure semantics inject
  // their own controller.
  final queue = offlineQueueController ??
      OfflineQueueController(
        dao: PendingPostDao(AppDatabase.instance()),
        executor: (_) async {},
        // Zero backoff so the retry timer is effectively synchronous
        // and pumpAndSettle drains it without holding pending timers
        // past the test.
        backoff: (_) => Duration.zero,
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
