import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/app/auth_bootstrap.dart' show AuthBootstrap, AuthRouter;
import 'package:dukan/config/app_config.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/observability/crash_reporter.dart';
import 'package:dukan/observability/timing.dart';
import 'package:dukan/shared/fallback_localizations.dart';
import 'package:dukan/shared/locale_controller.dart';
import 'package:dukan/shared/supabase_config_screen.dart';
import 'package:dukan/shared/typography.dart';
import 'package:dukan/storage/app_database.dart';

Future<void> main() async {
  // ensureInitialized must run before any plugin call (Supabase touches
  // shared_preferences for its session store). Sync + idempotent, so
  // calling it at the very top is the safest place.
  WidgetsFlutterBinding.ensureInitialized();
  // Cold-start clock. No-op in release; _TodayCard mount calls
  // endFlow when the cashier first sees the Home content.
  Timing.startFlow('cold.start');
  final appConfig = AppConfig.fromEnvironment();

  // Kick off Supabase init concurrently with Sentry init. Both make
  // independent HTTP handshakes; serializing them costs ~500–1000 ms
  // on hosted/network paths. We do NOT await this future here — it's
  // awaited inside appRunner (Sentry branch) or below (no-Sentry
  // branch) so both branches overlap the two awaits.
  final Future<void> supabaseFuture = appConfig.hasSupabase
      ? Supabase.initialize(
          url: appConfig.supabaseUrl,
          anonKey: appConfig.supabaseAnonKey,
        )
      : Future<void>.value();

  // Open the local sqflite DB alongside Supabase init so they
  // overlap. Both are filesystem/disk-bound and independent of each
  // other; serializing would add ~50 ms to cold start.
  final Future<void> databaseFuture =
      AppDatabase.instance().then((_) {}).catchError((error, stackTrace) {
    // A failed DB open is non-fatal — the queue + caches simply
    // won't work this session. Live RPCs still succeed.
    CrashReporter.reportError(error, stackTrace, hint: 'main.openDatabase');
  });

  // Resolve Supabase init + DB open concurrently, but OFF the first-paint
  // path: runApp shows a splash immediately and swaps to the real app when
  // these complete. On a "cold after a while" launch, Supabase.initialize
  // does an expired-token refresh round-trip — keeping that off the
  // pre-runApp barrier means the cashier sees branded UI instantly instead of
  // a frozen blank screen while the network call (and its timeout) resolves.
  final Future<void> initFuture =
      Future.wait([supabaseFuture, databaseFuture]);

  if (appConfig.hasSentry) {
    await SentryFlutter.init(
      (options) {
        options.dsn = appConfig.sentryDsn;
        // Empty strings here are silently fine — Sentry just won't surface
        // those fields in the dashboard.
        options.environment = appConfig.appEnvironment;
        if (appConfig.appVersion.isNotEmpty) {
          options.release = 'dukan@${appConfig.appVersion}';
        }
        // Performance tracing off by default — it adds network noise the
        // pilot shops can't afford. Re-enable per environment if needed.
        options.tracesSampleRate = 0.0;
        // PII guard: even though we set user.id ourselves below, double
        // up here so the SDK never auto-attaches IP / cookies / etc.
        options.sendDefaultPii = false;
      },
      appRunner: () {
        CrashReporter.install(enabled: true);
        runApp(_AppBootstrap(appConfig: appConfig, initFuture: initFuture));
      },
    );
  } else {
    runApp(_AppBootstrap(appConfig: appConfig, initFuture: initFuture));
  }
}

/// Paints instantly: shows a branded splash while Supabase init + DB open
/// resolve in the background, then swaps to the real app. This keeps the
/// expired-token refresh inside Supabase.initialize off the first-paint path
/// so cold start never shows a frozen screen.
class _AppBootstrap extends StatelessWidget {
  const _AppBootstrap({required this.appConfig, required this.initFuture});

  final AppConfig appConfig;
  final Future<void> initFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashApp();
        }
        return DukanApp(
          supabaseClient:
              appConfig.hasSupabase ? Supabase.instance.client : null,
        );
      },
    );
  }
}

/// Minimal, self-contained splash (no session providers / no localization
/// needed) shown for the brief window before Supabase + the DB are ready.
class _SplashApp extends StatelessWidget {
  const _SplashApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF005C46),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
    );
  }
}

class DukanApp extends StatelessWidget {
  const DukanApp({super.key, this.supabaseClient});

  final SupabaseClient? supabaseClient;

  @override
  Widget build(BuildContext context) {
    // LocaleController is provided at the root so both the supabase-config
    // path (no auth) and the AuthBootstrap path can read it. The
    // session-scoped controllers (Auth, ShopApi, Cart, Receive) live inside
    // AuthBootstrap, which is ABOVE MaterialApp — so pushed routes
    // inherit them automatically and no per-push .value re-exports are
    // needed.
    return ChangeNotifierProvider(
      create: (_) => LocaleController(),
      child: supabaseClient == null
          ? _MaterialAppShell(home: const SupabaseConfigScreen())
          : AuthBootstrap(
              supabaseClient: supabaseClient!,
              builder: (_) => const _MaterialAppShell(home: AuthRouter()),
            ),
    );
  }

}

/// Pulls MaterialApp out into a tiny shell so it can be embedded under
/// either the supabase-config path or AuthBootstrap without duplicating
/// the locale + theme + delegates wiring.
class _MaterialAppShell extends StatelessWidget {
  const _MaterialAppShell({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleController>().locale;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        // Somali isn't in the Global*Localizations supported set, so
        // fall back to Flutter's built-in English defaults for framework
        // chrome (tooltips, dialog buttons). App copy still comes from
        // AppLocalizations.
        FallbackMaterialLocalizationsDelegate(),
        FallbackWidgetsLocalizationsDelegate(),
        FallbackCupertinoLocalizationsDelegate(),
      ],
      theme: _buildTheme(),
      home: home,
    );
  }

  ThemeData _buildTheme() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF005C46),
      brightness: Brightness.light,
    ).copyWith(surface: const Color(0xFFF8FAF7)),
    scaffoldBackgroundColor: const Color(0xFFF8FAF7),
    // Every declared fontSize goes through `kFontScale` so a single
    // constant tunes the whole app. See lib/shared/typography.dart.
    textTheme: const TextTheme(
      titleLarge: TextStyle(fontSize: 24 * kFontScale, fontWeight: FontWeight.w800),
      titleMedium: TextStyle(fontSize: 19 * kFontScale, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(fontSize: 18 * kFontScale),
      bodyMedium: TextStyle(fontSize: 16 * kFontScale),
      labelLarge: TextStyle(fontSize: 18 * kFontScale, fontWeight: FontWeight.w800),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(56, 64),
        textStyle: const TextStyle(fontSize: 20 * kFontScale, fontWeight: FontWeight.w900),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(56, 64),
        textStyle: const TextStyle(fontSize: 20 * kFontScale, fontWeight: FontWeight.w900),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
  );
}
