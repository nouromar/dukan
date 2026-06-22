import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/auth/login_screen.dart';
import 'package:dukan/auth/sign_out_flow.dart';
import 'package:dukan/auth/otp_verification_screen.dart';
import 'package:dukan/auth/owner_onboarding_screen.dart';
import 'package:dukan/auth/shop_picker_screen.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/expense/expense_controller.dart';
import 'package:dukan/home/home_screen.dart';
import 'package:dukan/observability/crash_reporter.dart';
import 'package:dukan/payment/payment_controller.dart';
import 'package:dukan/queue/offline_queue_controller.dart';
import 'package:dukan/queue/post_executor.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/cache_dao.dart';
import 'package:dukan/storage/device_config_dao.dart';
import 'package:dukan/storage/pending_post_dao.dart';
import 'package:dukan/storage/shared_prefs_migration.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/realtime_listener.dart';
import 'package:dukan/sync/sync_engine.dart';
import 'package:dukan/config/config_keys.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/sale/cart_controller.dart';
import 'package:dukan/setup/setup_item_onboarding_screen.dart';
import 'package:dukan/setup/shop_type_setup_screen.dart';
import 'package:dukan/shared/friendly_error_screen.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/loading_screen.dart';
import 'package:dukan/shared/locale_controller.dart';

/// Owns the lifecycle of the session-scoped controllers (Auth, ShopApi,
/// Cart, Receive) and exposes them via Provider. Lives ABOVE MaterialApp
/// so every route pushed through the root Navigator inherits the
/// providers automatically — no per-push .value re-exports needed.
///
/// Takes a `builder` that receives the BuildContext under the providers
/// and returns the MaterialApp. Keeps the MaterialApp wiring (locale,
/// theme, delegates) in main.dart while letting the auth-scoped state
/// live here.
class AuthBootstrap extends StatefulWidget {
  const AuthBootstrap({
    required this.supabaseClient,
    required this.builder,
    super.key,
  });

  final SupabaseClient supabaseClient;
  final WidgetBuilder builder;

  @override
  State<AuthBootstrap> createState() => _AuthBootstrapState();
}

class _AuthBootstrapState extends State<AuthBootstrap> {
  late final ShopApi _shopApi;
  late final AuthController _authController;
  late final CartController _cartController;
  late final ReceiveController _receiveController;
  late final PaymentController _paymentController;
  late final ExpenseController _expenseController;
  late final OfflineQueueController _offlineQueueController;
  late final ConfigResolver _configResolver;
  late final PendingPostDao _pendingPostDao;
  late final CacheDao _cacheDao;
  late final LocalRepository _localRepository;
  late final SyncEngine _syncEngine;
  late final RealtimeListener _realtimeListener;
  bool _hadSession = false;
  String? _crashReportedUserId;
  String? _crashReportedShopId;
  String? _configLoadedForShopId;

  @override
  void initState() {
    super.initState();
    _shopApi = ShopApi(widget.supabaseClient);
    _authController =
        AuthController(client: widget.supabaseClient, shopApi: _shopApi)
          ..start();
    _cartController = CartController();
    _receiveController = ReceiveController();
    _paymentController = PaymentController();
    _expenseController = ExpenseController();
    // main.dart waits for AppDatabase.instance() before runApp, so
    // the singleton is guaranteed open by the time we get here.
    // The DAOs accept a Future<AppDatabase> so construction is sync
    // even though the open is async; _initStorage runs the one-shot
    // SharedPreferences migration (idempotent — no-op on second
    // launch) then starts the queue draining.
    final database = AppDatabase.instance();
    _pendingPostDao = PendingPostDao(database);
    _configResolver = ConfigResolver(
      shopApi: _shopApi,
      deviceConfigDao: DeviceConfigDao(database),
      reportError: (error, stack, hint) {
        unawaited(CrashReporter.reportError(error, stack, hint: hint));
      },
    );
    _cacheDao = CacheDao(database, configResolver: _configResolver);
    _localRepository = LocalRepository(database);
    _offlineQueueController = OfflineQueueController(
      dao: _pendingPostDao,
      executor: PostExecutor(_shopApi).execute,
      configResolver: _configResolver,
      // #374: clear projection rows when a queued post drains
      // successfully OR transitions to failed_permanent. The
      // local repo no-ops gracefully if no projections exist
      // (light mode), so this is safe in both flag states.
      onProjectionCleanup: _localRepository.clearProjectionsForPost,
    );
    // #376: realtime debounce + delta poll interval resolve from
    // ConfigResolver so they're tunable per-shop without a build.
    // Defaults baked into the keys match the previous hard-coded
    // values (200 ms / 5 min).
    _syncEngine = SyncEngine(
      shopApi: _shopApi,
      localRepository: _localRepository,
      pendingPostDao: _pendingPostDao,
      realtimeDebounce: Duration(
        milliseconds: _configResolver
            .resolve(ConfigKeys.syncRealtimeDebounceMs),
      ),
      deltaPollInterval: Duration(
        seconds: _configResolver
            .resolve(ConfigKeys.syncDeltaPollIntervalS),
      ),
      reportError: (error, stack, hint) {
        unawaited(CrashReporter.reportError(error, stack, hint: hint));
      },
    );
    _realtimeListener = RealtimeListener(
      client: widget.supabaseClient,
      syncEngine: _syncEngine,
      reportError: (error, stack, hint) {
        unawaited(CrashReporter.reportError(error, stack, hint: hint));
      },
    );
    unawaited(_initStorage(database));
    // Clear in-progress carts/bonos/payments/expenses whenever the
    // session transitions to null (sign-out or session expiry). Stops
    // state from leaking across users sharing the same device.
    _authController.addListener(_onAuthChanged);
  }

  /// Run the one-shot SharedPreferences migration if needed, then
  /// kick off the queue drain. Errors are reported to Sentry but
  /// never block app startup — screens stay usable even if local
  /// storage is borked (live RPCs still work).
  Future<void> _initStorage(Future<AppDatabase> databaseFuture) async {
    try {
      final migration = SharedPrefsMigration(
        pendingPostDao: PendingPostDao(databaseFuture),
        cacheDao: CacheDao(databaseFuture),
        deviceConfigDao: DeviceConfigDao(databaseFuture),
        fallbackOriginalActorUserId:
            widget.supabaseClient.auth.currentUser?.id,
        reportError: (error, stack, ctx) {
          unawaited(CrashReporter.reportError(error, stack, hint: ctx));
        },
      );
      await migration.runIfNeeded();
      await _offlineQueueController.start();
    } catch (error, stackTrace) {
      unawaited(CrashReporter.reportError(
        error,
        stackTrace,
        hint: 'auth_bootstrap.initStorage',
      ));
    }
  }

  void _onAuthChanged() {
    final hasSession = _authController.session != null;
    if (_hadSession && !hasSession) {
      _cartController.clearAll();
      _receiveController.clearAll();
      _paymentController.clearAll();
      _expenseController.clearAll();
      _configResolver.reset();
      _configLoadedForShopId = null;
      _syncEngine.stop();
      unawaited(_realtimeListener.stop());
    }
    _hadSession = hasSession;
    _syncCrashReporter();
    _maybeReloadConfig();
  }

  /// Refresh the hierarchical config whenever the selected shop
  /// changes (initial load, shop switch, sign-in). Defaults are
  /// already in place; the load brings in org-scoped + device-scoped
  /// overrides. Failures are non-fatal — see ConfigResolver.
  void _maybeReloadConfig() {
    final shop = _authController.selectedShop;
    if (shop == null) {
      _configLoadedForShopId = null;
      return;
    }
    if (_configLoadedForShopId == shop.id) return;
    _configLoadedForShopId = shop.id;
    unawaited(_loadConfigAndMaybeStartSync(shop.id));
  }

  /// Load the hierarchical config then start the sync engine if the
  /// resolved `offline_mode` is `full`. Errors in config load are
  /// non-fatal (defaults still resolve); a failing sync start is
  /// reported but doesn't block the screen — light-mode reads still
  /// work because the existing CacheDao + ShopApi paths are intact.
  Future<void> _loadConfigAndMaybeStartSync(String shopId) async {
    await _configResolver.loadForSession(shopId: shopId);
    final mode = _configResolver.resolve(ConfigKeys.offlineMode);
    if (mode == 'full') {
      try {
        await _syncEngine.start(shopId);
        // #374: subscribe to postgres_changes for the active shop
        // so other devices' writes (and admin-portal edits) land
        // in the local mirror in near real-time. SyncEngine
        // already handles self-echo + 200ms debounce; the
        // listener just forwards.
        await _realtimeListener.start(shopId);
      } catch (error, stack) {
        // fullSync rethrows on cold-no-local failure. Log + swallow:
        // screens still render via the existing network path.
        unawaited(CrashReporter.reportError(
          error,
          stack,
          hint: 'auth_bootstrap.syncEngine.start',
        ));
      }
    }
  }

  // Push the current session's user + selected shop into Sentry scope
  // so subsequent error events are attributable. We only send IDs —
  // never phone numbers, names, or anything else identifying. Diffs
  // against the last reported pair so we don't churn the SDK on every
  // notification (the AuthController fires for many non-identity
  // changes — shop list refresh, loading flags, etc.).
  void _syncCrashReporter() {
    final userId = _authController.session?.user.id;
    final shopId = _authController.selectedShop?.id;
    if (userId == _crashReportedUserId && shopId == _crashReportedShopId) {
      return;
    }
    _crashReportedUserId = userId;
    _crashReportedShopId = shopId;
    if (userId == null) {
      CrashReporter.clearUser();
    } else {
      CrashReporter.setUser(userId: userId, shopId: shopId);
    }
  }

  @override
  void dispose() {
    _authController.removeListener(_onAuthChanged);
    unawaited(_realtimeListener.dispose());
    _syncEngine.dispose();
    _offlineQueueController.dispose();
    _expenseController.dispose();
    _paymentController.dispose();
    _receiveController.dispose();
    _cartController.dispose();
    _authController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: _authController),
        Provider<ShopApi>.value(value: _shopApi),
        ChangeNotifierProvider<CartController>.value(value: _cartController),
        ChangeNotifierProvider<ReceiveController>.value(
          value: _receiveController,
        ),
        ChangeNotifierProvider<PaymentController>.value(
          value: _paymentController,
        ),
        ChangeNotifierProvider<ExpenseController>.value(
          value: _expenseController,
        ),
        ChangeNotifierProvider<OfflineQueueController>.value(
          value: _offlineQueueController,
        ),
        ChangeNotifierProvider<ConfigResolver>.value(value: _configResolver),
        Provider<PendingPostDao>.value(value: _pendingPostDao),
        Provider<CacheDao>.value(value: _cacheDao),
        Provider<LocalRepository>.value(value: _localRepository),
        ChangeNotifierProvider<SyncEngine>.value(value: _syncEngine),
      ],
      child: Builder(builder: widget.builder),
    );
  }
}

class AuthRouter extends StatelessWidget {
  const AuthRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    // Settings is now the single source of truth for language once a
    // shop is selected. Push the shop's default_language_code into the
    // root LocaleController on every auth notification so changing
    // shops or saving Settings flips the UI without a separate
    // listener wiring. setLocale is a no-op when the value matches, so
    // the pre-auth toggle's choice is only overridden once a shop
    // actually loads.
    final shop = auth.selectedShop;
    if (shop != null) {
      final locale = context.read<LocaleController>();
      final target = Locale(shop.defaultLanguageCode);
      if (locale.locale != target) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          locale.setLocale(target);
        });
      }
    }

    if (!auth.initialized) {
      return const LoadingScreen();
    }

    if (auth.session == null) {
      final hasPending = auth.pendingPhone != null || auth.pendingEmail != null;
      return hasPending
          ? const OtpVerificationScreen()
          : const LoginScreen();
    }

    // Only fall back to the LoadingScreen when there's nothing cached
    // to render. After #329 the SWR auth cache populates `auth.shops`
    // + `auth.selectedShop` synchronously on warm-cache cold starts;
    // the unawaited background loadShops then flips `shopsLoading` to
    // true. Without the guard below the AuthRouter would flash back to
    // LoadingScreen for the duration of that background fetch, then
    // back to HomeScreen — visible as a "double flash" on launch.
    if (auth.shopsLoading && auth.shops.isEmpty) {
      return const LoadingScreen();
    }

    // Same guard: if the background refresh fails but we already have
    // cached shops, keep rendering them rather than masking the whole
    // screen with the error UI. (A future enhancement could surface a
    // small "couldn't refresh" banner; for now the cached state is the
    // right user-facing default.)
    if (auth.shopLoadFailed && auth.shops.isEmpty) {
      return FriendlyErrorScreen(
        title: tr(context).shopLoadFailedTitle,
        message: tr(context).shopLoadFailedMessage,
        onRetry: () => auth.loadShops(),
        onSignOut: () => confirmSignOut(context),
      );
    }

    if (auth.shops.isEmpty) {
      return const OwnerOnboardingScreen();
    }

    final selectedShop = auth.selectedShop;
    if (selectedShop == null) {
      return const ShopPickerScreen();
    }

    if (!selectedShop.isReady) {
      return ShopTypeSetupScreen(shop: selectedShop);
    }

    // Optional item-onboarding step — appears once, never blocks
    // selling. AuthRouter watches selectedShop; after the screen calls
    // dismissOnboarding + refreshSelectedShop, isOnboardingPending
    // flips to false and we fall through to HomeScreen.
    if (selectedShop.isOnboardingPending) {
      return SetupItemOnboardingScreen(shop: selectedShop);
    }

    return HomeScreen(
      shop: selectedShop,
      onSignOut: () => confirmSignOut(context),
    );
  }
}
