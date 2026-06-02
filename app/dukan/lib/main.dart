import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/app/auth_bootstrap.dart' show AuthBootstrap, AuthRouter;
import 'package:dukan/config/app_config.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/shared/fallback_localizations.dart';
import 'package:dukan/shared/locale_controller.dart';
import 'package:dukan/shared/supabase_config_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appConfig = AppConfig.fromEnvironment();
  SupabaseClient? supabaseClient;

  if (appConfig.hasSupabase) {
    await Supabase.initialize(
      url: appConfig.supabaseUrl,
      anonKey: appConfig.supabaseAnonKey,
    );
    supabaseClient = Supabase.instance.client;
  }

  runApp(DukanApp(supabaseClient: supabaseClient));
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
    textTheme: const TextTheme(
      titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      titleMedium: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(fontSize: 18),
      bodyMedium: TextStyle(fontSize: 16),
      labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(56, 64),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(56, 64),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
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
