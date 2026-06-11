class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.sentryDsn,
    required this.appEnvironment,
    required this.appVersion,
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    sentryDsn: String.fromEnvironment('SENTRY_DSN'),
    appEnvironment: String.fromEnvironment('APP_ENVIRONMENT'),
    appVersion: String.fromEnvironment('APP_VERSION'),
  );

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String sentryDsn;
  final String appEnvironment;
  final String appVersion;

  bool get hasSupabase =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  bool get hasSentry => sentryDsn.trim().isNotEmpty;
}
