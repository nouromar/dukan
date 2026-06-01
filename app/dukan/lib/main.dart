import 'dart:math' as math;

import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/config/app_config.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/mock/mock_data.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  runApp(DukanPrototype(supabaseClient: supabaseClient));
}

class _FallbackMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _FallbackMaterialLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      DefaultMaterialLocalizations.load(locale);
  @override
  bool shouldReload(_FallbackMaterialLocalizationsDelegate old) => false;
}

class _FallbackWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _FallbackWidgetsLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      DefaultWidgetsLocalizations.load(locale);
  @override
  bool shouldReload(_FallbackWidgetsLocalizationsDelegate old) => false;
}

class _FallbackCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _FallbackCupertinoLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      DefaultCupertinoLocalizations.load(locale);
  @override
  bool shouldReload(_FallbackCupertinoLocalizationsDelegate old) => false;
}

class LocaleController extends ChangeNotifier {
  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  void setLocale(Locale locale) {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
  }
}

class DukanPrototype extends StatelessWidget {
  const DukanPrototype({super.key, this.supabaseClient});

  final SupabaseClient? supabaseClient;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LocaleController(),
      child: Consumer<LocaleController>(
        builder: (context, controller, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (context) => L10n.of(context).appTitle,
          locale: controller.locale,
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: const [
            L10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            // Somali is not in the Global*Localizations supported set, so
            // fall back to the built-in English defaults for framework chrome
            // (tooltips, dialog buttons). App copy still comes from L10n.
            _FallbackMaterialLocalizationsDelegate(),
            _FallbackWidgetsLocalizationsDelegate(),
            _FallbackCupertinoLocalizationsDelegate(),
          ],
          theme: ThemeData(
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
                textStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                minimumSize: const Size(56, 64),
                textStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
            ),
          ),
          home: supabaseClient == null
              ? const SupabaseConfigScreen()
              : AuthBootstrap(supabaseClient: supabaseClient!),
        ),
      ),
    );
  }
}

typedef L10n = AppLocalizations;

L10n tr(BuildContext context) => L10n.of(context);

String money(num value) => value == value.roundToDouble()
    ? '\$${value.toStringAsFixed(0)}'
    : '\$${value.toStringAsFixed(2)}';

double parseAmount(String text) =>
    double.tryParse(text.replaceAll(',', '.')) ?? 0;

class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final current = context.watch<LocaleController>().locale.languageCode;
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: 'en', label: Text(tr(context).languageEnglish)),
        ButtonSegment(value: 'so', label: Text(tr(context).languageSomali)),
      ],
      selected: {current},
      onSelectionChanged: (selected) =>
          context.read<LocaleController>().setLocale(Locale(selected.first)),
      style: ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.padded,
        minimumSize: WidgetStateProperty.all(const Size(56, 48)),
      ),
    );
  }
}

PreferredSizeWidget dukanAppBar(
  BuildContext context,
  String title, {
  List<Widget> actions = const [],
}) => AppBar(
  title: Text(title),
  actions: [
    ...actions,
    const Padding(
      padding: EdgeInsetsDirectional.only(end: 12),
      child: LanguageToggle(),
    ),
  ],
);

class SupabaseConfigScreen extends StatelessWidget {
  const SupabaseConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.appTitle),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(
              Icons.cloud_off,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              l.supabaseConfigTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l.supabaseConfigMessage,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(l.supabaseConfigCommand),
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => push(context, const HomeScreen()),
              child: Text(l.openPrototype),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthBootstrap extends StatefulWidget {
  const AuthBootstrap({required this.supabaseClient, super.key});

  final SupabaseClient supabaseClient;

  @override
  State<AuthBootstrap> createState() => _AuthBootstrapState();
}

class _AuthBootstrapState extends State<AuthBootstrap> {
  late final AuthController _authController;

  @override
  void initState() {
    super.initState();
    _authController = AuthController(widget.supabaseClient)..start();
  }

  @override
  void dispose() {
    _authController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthController>.value(
      value: _authController,
      child: const AuthRouter(),
    );
  }
}

class AuthRouter extends StatelessWidget {
  const AuthRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    if (!auth.initialized) {
      return const LoadingScreen();
    }

    if (auth.session == null) {
      return auth.pendingPhone != null
          ? const OtpVerificationScreen()
          : const PhoneLoginScreen();
    }

    if (auth.shopsLoading) {
      return const LoadingScreen();
    }

    if (auth.shopLoadFailed) {
      return FriendlyErrorScreen(
        title: tr(context).shopLoadFailedTitle,
        message: tr(context).shopLoadFailedMessage,
        onRetry: () => auth.loadShops(),
        onSignOut: () => auth.signOut(),
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

    return HomeScreen(shop: selectedShop, onSignOut: () => auth.signOut());
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.appTitle),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class FriendlyErrorScreen extends StatelessWidget {
  const FriendlyErrorScreen({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onSignOut,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(
        context,
        title,
        actions: [
          IconButton(
            tooltip: l.signOut,
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(
              Icons.wifi_off,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l.tryAgain),
            ),
          ],
        ),
      ),
    );
  }
}

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phoneController = TextEditingController(text: '+252');
  bool _sending = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() => _sending = true);
    try {
      await context.read<AuthController>().sendOtp(_phoneController.text);
    } on AuthInputException catch (error) {
      if (mounted) {
        _showError(context, _authInputErrorMessage(context, error.issue));
      }
    } on AuthException {
      if (mounted) {
        _showError(context, tr(context).sendOtpFailedMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.loginTitle),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(
              Icons.phone_android,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              l.loginHeadline,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l.loginBody,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: l.phoneNumberLabel),
              onSubmitted: (_) => _sending ? null : _sendOtp(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _sending ? null : _sendOtp,
              child: _sending
                  ? const CircularProgressIndicator()
                  : Text(l.sendOtpButton),
            ),
          ],
        ),
      ),
    );
  }
}

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _otpController = TextEditingController();
  bool _verifying = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    setState(() => _verifying = true);
    try {
      await context.read<AuthController>().verifyOtp(_otpController.text);
    } on AuthInputException catch (error) {
      if (mounted) {
        _showError(context, _authInputErrorMessage(context, error.issue));
      }
    } on AuthException {
      if (mounted) {
        _showError(context, tr(context).verifyOtpFailedMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final pendingPhone = context.watch<AuthController>().pendingPhone;
    return Scaffold(
      appBar: dukanAppBar(context, l.verifyOtpTitle),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              l.verifyOtpHeadline,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l.verifyOtpBody(pendingPhone ?? ''),
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: l.otpCodeLabel),
              onSubmitted: (_) => _verifying ? null : _verifyOtp(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _verifying ? null : _verifyOtp,
              child: _verifying
                  ? const CircularProgressIndicator()
                  : Text(l.verifyOtpButton),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _verifying
                  ? null
                  : () => context.read<AuthController>().cancelOtp(),
              child: Text(l.changePhoneButton),
            ),
          ],
        ),
      ),
    );
  }
}

class OwnerOnboardingScreen extends StatefulWidget {
  const OwnerOnboardingScreen({super.key});

  @override
  State<OwnerOnboardingScreen> createState() => _OwnerOnboardingScreenState();
}

class _OwnerOnboardingScreenState extends State<OwnerOnboardingScreen> {
  final _businessNameController = TextEditingController();
  final _shopNameController = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _businessNameController.dispose();
    _shopNameController.dispose();
    super.dispose();
  }

  Future<void> _createShop() async {
    setState(() => _creating = true);
    try {
      await context.read<AuthController>().createFirstShop(
        businessName: _businessNameController.text,
        shopName: _shopNameController.text,
      );
    } on AuthInputException catch (error) {
      if (mounted) {
        _showError(context, _authInputErrorMessage(context, error.issue));
      }
    } on PostgrestException {
      if (mounted) {
        _showError(context, tr(context).createShopFailedMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(
        context,
        l.ownerOnboardingTitle,
        actions: [
          IconButton(
            tooltip: l.signOut,
            onPressed: () => context.read<AuthController>().signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              l.ownerOnboardingHeadline,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l.ownerOnboardingBody,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _businessNameController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: l.businessNameLabel),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _shopNameController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: l.shopNameLabel),
              onSubmitted: (_) => _creating ? null : _createShop(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _creating ? null : _createShop,
              child: _creating
                  ? const CircularProgressIndicator()
                  : Text(l.createShopButton),
            ),
          ],
        ),
      ),
    );
  }
}

class ShopPickerScreen extends StatelessWidget {
  const ShopPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final auth = context.watch<AuthController>();
    return Scaffold(
      appBar: dukanAppBar(
        context,
        l.chooseShopTitle,
        actions: [
          IconButton(
            tooltip: l.signOut,
            onPressed: () => context.read<AuthController>().signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: auth.shops.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final shop = auth.shops[index];
            return Card(
              child: ListTile(
                minVerticalPadding: 18,
                title: Text(
                  shop.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(l.shopSetupStatus(shop.setupStatus)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.read<AuthController>().selectShop(shop),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ShopTypeSetupScreen extends StatefulWidget {
  const ShopTypeSetupScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<ShopTypeSetupScreen> createState() => _ShopTypeSetupScreenState();
}

class _ShopTypeSetupScreenState extends State<ShopTypeSetupScreen> {
  late Future<List<TemplateOption>> _future;
  String? _selectedId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AuthController>().listAvailableTemplates();
  }

  Future<void> _continue() async {
    final id = _selectedId;
    if (id == null) return;
    setState(() => _busy = true);
    final l = tr(context);
    final auth = context.read<AuthController>();
    try {
      await auth.applyTemplate(shopId: widget.shop.id, templateId: id);
      if (!mounted) return;
      await auth.completeSetup(shopId: widget.shop.id);
      // AuthRouter watches selectedShop.setupStatus and rebuilds into
      // HomeScreen automatically — nothing to navigate here.
    } on PostgrestException {
      if (mounted) {
        _showError(context, l.applyTemplateFailedMessage);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resume() async {
    setState(() => _busy = true);
    final l = tr(context);
    try {
      await context.read<AuthController>().completeSetup(
        shopId: widget.shop.id,
      );
    } on PostgrestException {
      if (mounted) {
        _showError(context, l.completeSetupFailedMessage);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final templateApplied = widget.shop.isTemplateApplied;

    return Scaffold(
      appBar: dukanAppBar(
        context,
        l.setupStepTemplateTitle,
        actions: [
          IconButton(
            tooltip: l.signOut,
            onPressed: () => context.read<AuthController>().signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: templateApplied
            ? _ResumeBody(
                shopName: widget.shop.name,
                busy: _busy,
                onFinish: _resume,
              )
            : _PickerBody(
                future: _future,
                selectedId: _selectedId,
                busy: _busy,
                onSelect: (v) => setState(() => _selectedId = v),
                onContinue: _continue,
              ),
      ),
    );
  }
}

class _PickerBody extends StatelessWidget {
  const _PickerBody({
    required this.future,
    required this.selectedId,
    required this.busy,
    required this.onSelect,
    required this.onContinue,
  });

  final Future<List<TemplateOption>> future;
  final String? selectedId;
  final bool busy;
  final ValueChanged<String?> onSelect;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            l.setupStepTemplateBody,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        Expanded(
          child: FutureBuilder<List<TemplateOption>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l.applyTemplateFailedMessage,
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final options = snapshot.data ?? const <TemplateOption>[];
              if (options.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l.templatesEmptyMessage,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                );
              }
              return RadioGroup<String>(
                groupValue: selectedId,
                onChanged: (v) {
                  if (busy) return;
                  onSelect(v);
                },
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final opt = options[i];
                    final selected = selectedId == opt.id;
                    return Card(
                      elevation: selected ? 3 : 1,
                      child: RadioListTile<String>(
                        value: opt.id,
                        title: Text(
                          opt.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton(
            onPressed: selectedId == null || busy ? null : onContinue,
            child: busy
                ? const CircularProgressIndicator()
                : Text(l.applyTemplateButton),
          ),
        ),
      ],
    );
  }
}

class _ResumeBody extends StatelessWidget {
  const _ResumeBody({
    required this.shopName,
    required this.busy,
    required this.onFinish,
  });

  final String shopName;
  final bool busy;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l.setupStepTemplateDone(shopName),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.setupStepFinishBody,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton(
            onPressed: busy ? null : onFinish,
            child: busy
                ? const CircularProgressIndicator()
                : Text(l.setupStepFinishButton),
          ),
        ),
      ],
    );
  }
}


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _timezoneController;
  late String _currencyCode;
  late String _languageCode;
  late Future<_SettingsReferenceData> _refsFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.shop.name);
    _timezoneController = TextEditingController(text: widget.shop.timezone);
    _currencyCode = widget.shop.currencyCode;
    _languageCode = widget.shop.defaultLanguageCode;
    final auth = context.read<AuthController>();
    _refsFuture = Future.wait([auth.listCurrencies(), auth.listLanguages()])
        .then(
          (results) => _SettingsReferenceData(
            currencies: results[0],
            languages: results[1],
          ),
        );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final l = tr(context);
    try {
      await context.read<AuthController>().updateShopDefaults(
        shopId: widget.shop.id,
        name: _nameController.text,
        currencyCode: _currencyCode,
        defaultLanguageCode: _languageCode,
        timezone: _timezoneController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settingsSavedToast)),
      );
      Navigator.of(context).pop();
    } on PostgrestException {
      if (mounted) {
        _showError(context, l.settingsSaveFailedMessage);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.settingsTitle),
      body: SafeArea(
        child: FutureBuilder<_SettingsReferenceData>(
          future: _refsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return Center(child: Text(l.settingsSaveFailedMessage));
            }
            final refs = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l.settingsShopNameLabel),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _currencyCode,
                  decoration: InputDecoration(
                    labelText: l.settingsCurrencyLabel,
                  ),
                  items: [
                    for (final c in refs.currencies)
                      DropdownMenuItem(
                        value: c.code,
                        child: Text('${c.code} (${c.label})'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _currencyCode = value);
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _languageCode,
                  decoration: InputDecoration(
                    labelText: l.settingsLanguageLabel,
                  ),
                  items: [
                    for (final lang in refs.languages)
                      DropdownMenuItem(
                        value: lang.code,
                        child: Text(lang.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _languageCode = value);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _timezoneController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: l.settingsTimezoneLabel,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : Text(l.settingsSaveButton),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SettingsReferenceData {
  const _SettingsReferenceData({
    required this.currencies,
    required this.languages,
  });

  final List<ReferenceOption> currencies;
  final List<ReferenceOption> languages;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.shop, this.onSignOut});

  final ShopSummary? shop;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(
        context,
        l.appTitle,
        actions: [
          if (shop != null)
            IconButton(
              tooltip: l.openSettings,
              onPressed: () {
                final auth = context.read<AuthController>();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider<AuthController>.value(
                      value: auth,
                      child: SettingsScreen(shop: shop!),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.settings),
            ),
          if (onSignOut != null)
            IconButton(
              tooltip: l.signOut,
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final buttonAreaHeight = math.min(
                360.0,
                constraints.maxHeight * 0.58,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.homeHint,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (shop != null) ...[
                    const SizedBox(height: 12),
                    Chip(
                      avatar: const Icon(Icons.storefront),
                      label: Text(l.activeShopLabel(shop!.name)),
                    ),
                  ],
                  const Spacer(),
                  SizedBox(
                    height: buttonAreaHeight,
                    child: GridView.count(
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 1.55,
                      children: [
                        HomeAction(
                          icon: Icons.point_of_sale,
                          label: l.sale,
                          onTap: () => push(context, const SaleScreen()),
                        ),
                        HomeAction(
                          icon: Icons.inventory_2,
                          label: l.receive,
                          onTap: () => push(context, const ReceiveScreen()),
                        ),
                        HomeAction(
                          icon: Icons.payments,
                          label: l.payment,
                          onTap: () => push(context, const PaymentScreen()),
                        ),
                        HomeAction(
                          icon: Icons.receipt_long,
                          label: l.expense,
                          onTap: () => push(context, const ExpenseScreen()),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _authInputErrorMessage(BuildContext context, AuthInputIssue issue) {
  final l = tr(context);
  return switch (issue) {
    AuthInputIssue.invalidPhone => l.invalidPhoneMessage,
    AuthInputIssue.missingPendingPhone => l.missingPendingPhoneMessage,
    AuthInputIssue.missingShopNames => l.missingShopNamesMessage,
  };
}

void push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

class HomeAction extends StatelessWidget {
  const HomeAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 34),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class CartEntry {
  CartEntry({required this.item, required this.quantity, required this.price});
  final MockItem item;
  double quantity;
  double price;
  double get total => quantity * price;
}

class SaleScreen extends StatefulWidget {
  const SaleScreen({super.key});

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  final searchController = TextEditingController();
  final customerController = TextEditingController();
  final Map<String, CartEntry> cart = {};
  bool debt = false;

  @override
  void dispose() {
    searchController.dispose();
    customerController.dispose();
    super.dispose();
  }

  double get total => cart.values.fold(0, (sum, entry) => sum + entry.total);
  double get count => cart.values.fold(0, (sum, entry) => sum + entry.quantity);

  void addItem(MockItem item, {double quantity = 1, double? price}) {
    setState(() {
      final entry = cart[item.id];
      if (entry == null) {
        cart[item.id] = CartEntry(
          item: item,
          quantity: quantity,
          price: price ?? item.price,
        );
      } else {
        entry.quantity += quantity;
        if (price != null) entry.price = price;
      }
    });
    HapticFeedback.selectionClick();
  }

  Future<void> openQuantityDialog(MockItem item) async {
    final l = tr(context);
    final result = await showDialog<_QtyPrice>(
      context: context,
      builder: (context) => QtyPriceDialog(
        item: item,
        title: item.name(Localizations.localeOf(context)),
      ),
    );
    if (result != null && result.quantity > 0) {
      addItem(item, quantity: result.quantity, price: result.price);
    }
    if (mounted && result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${item.name(Localizations.localeOf(context))}: ${l.addToCart}',
          ),
        ),
      );
    }
  }

  void confirmSale() {
    if (cart.isEmpty) return;
    final oldCart = Map<String, CartEntry>.fromEntries(
      cart.entries.map(
        (e) => MapEntry(
          e.key,
          CartEntry(
            item: e.value.item,
            quantity: e.value.quantity,
            price: e.value.price,
          ),
        ),
      ),
    );
    setState(() => cart.clear());
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(tr(context).savedUndo),
        action: SnackBarAction(
          label: tr(context).undo,
          onPressed: () => setState(() => cart.addAll(oldCart)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final locale = Localizations.localeOf(context);
    final items = [
      ...mockItems.where((item) => item.matches(searchController.text)),
    ]..sort((a, b) => b.frequency.compareTo(a.frequency));
    return Scaffold(
      appBar: dukanAppBar(context, l.sale),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: TextField(
                controller: searchController,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: l.searchItems,
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 116,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) => ItemTile(
                  item: items[index],
                  locale: locale,
                  onTap: () => addItem(items[index]),
                  onLongPress: () => openQuantityDialog(items[index]),
                ),
              ),
            ),
            if (cart.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  l.emptySaleHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            SaleCartStrip(
              cart: cart.values.toList(),
              total: total,
              count: count,
              debt: debt,
              customerController: customerController,
              onModeChanged: (value) => setState(() => debt = value),
              onConfirm: confirmSale,
            ),
          ],
        ),
      ),
    );
  }
}

class ItemTile extends StatelessWidget {
  const ItemTile({
    required this.item,
    required this.locale,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });
  final MockItem item;
  final Locale locale;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                item.icon,
                size: 26,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 4),
              Text(
                item.name(locale),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${item.unit(locale)} · ${money(item.price)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SaleCartStrip extends StatelessWidget {
  const SaleCartStrip({
    required this.cart,
    required this.total,
    required this.count,
    required this.debt,
    required this.customerController,
    required this.onModeChanged,
    required this.onConfirm,
    super.key,
  });

  final List<CartEntry> cart;
  final double total;
  final double count;
  final bool debt;
  final TextEditingController customerController;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Material(
      elevation: 10,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${l.cart}: ${l.itemsCount(count.round())}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${l.total}: ${money(total)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(l.cash),
                        icon: const Icon(Icons.payments),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(l.debt),
                        icon: const Icon(Icons.person),
                      ),
                    ],
                    selected: {debt},
                    onSelectionChanged: (set) => onModeChanged(set.first),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: cart.isEmpty ? null : onConfirm,
                    icon: const Icon(Icons.check_circle),
                    label: Text(l.confirm),
                  ),
                ),
              ],
            ),
            if (debt) ...[
              const SizedBox(height: 8),
              InlinePartySearch(
                controller: customerController,
                parties: customers,
                label: l.customerDebt,
                hint: l.searchCustomers,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QtyPrice {
  const _QtyPrice(this.quantity, this.price);
  final double quantity;
  final double? price;
}

class QtyPriceDialog extends StatefulWidget {
  const QtyPriceDialog({required this.item, required this.title, super.key});
  final MockItem item;
  final String title;

  @override
  State<QtyPriceDialog> createState() => _QtyPriceDialogState();
}

class _QtyPriceDialogState extends State<QtyPriceDialog> {
  final qty = TextEditingController(text: '1');
  final price = TextEditingController();
  TextEditingController? active;

  @override
  void initState() {
    super.initState();
    active = qty;
  }

  @override
  void dispose() {
    qty.dispose();
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: NumberField(
                    label: l.quantity,
                    controller: qty,
                    selected: active == qty,
                    onTap: () => setState(() => active = qty),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NumberField(
                    label: l.optionalPrice,
                    controller: price,
                    selected: active == price,
                    onTap: () => setState(() => active = price),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            BigNumpad(controller: active ?? qty),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            _QtyPrice(
              parseAmount(qty.text),
              price.text.trim().isEmpty ? null : parseAmount(price.text),
            ),
          ),
          icon: const Icon(Icons.add_shopping_cart),
          label: Text(l.addToCart),
        ),
      ],
    );
  }
}

class NumberField extends StatelessWidget {
  const NumberField({
    required this.label,
    required this.controller,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final String label;
  final TextEditingController controller;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderSide: BorderSide(width: selected ? 3 : 1),
        ),
      ),
      style: Theme.of(context).textTheme.titleLarge,
    );
  }
}

class BigNumpad extends StatelessWidget {
  const BigNumpad({required this.controller, super.key});
  final TextEditingController controller;

  void append(String value) {
    if (value == '.' && controller.text.contains('.')) return;
    controller.text += value;
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final labels = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '.',
      '0',
      l.backspace,
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.0,
      ),
      itemCount: labels.length + 1,
      itemBuilder: (context, index) {
        if (index == labels.length) {
          return OutlinedButton(
            onPressed: () => controller.clear(),
            child: Text(l.clear),
          );
        }
        final label = labels[index];
        return OutlinedButton(
          onPressed: () {
            if (label == l.backspace) {
              if (controller.text.isNotEmpty) {
                controller.text = controller.text.substring(
                  0,
                  controller.text.length - 1,
                );
              }
            } else {
              append(label);
            }
          },
          child: Text(
            label,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        );
      },
    );
  }
}

class ReceiveLine {
  ReceiveLine({
    required this.item,
    required this.quantity,
    required this.cost,
    required this.costIsLine,
  });
  final MockItem item;
  final double quantity;
  final double cost;
  final bool costIsLine;
  double get total => costIsLine ? cost : cost * quantity;
}

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final supplierSearch = TextEditingController();
  final itemSearch = TextEditingController();
  final qtyController = TextEditingController();
  final costController = TextEditingController();
  final bonoController = TextEditingController();
  final itemFocus = FocusNode();
  MockParty? supplier;
  MockItem? selectedItem;
  bool costIsLine = false;
  bool bonoAttached = false;
  double paidNow = 0;
  final lines = <ReceiveLine>[];

  @override
  void dispose() {
    supplierSearch.dispose();
    itemSearch.dispose();
    qtyController.dispose();
    costController.dispose();
    bonoController.dispose();
    itemFocus.dispose();
    super.dispose();
  }

  double get runningTotal => lines.fold(0, (sum, line) => sum + line.total);

  void chooseSupplier(MockParty party) => setState(() {
    supplier = party;
    supplierSearch.text = party.name;
  });

  void chooseItem(MockItem item) => setState(() {
    selectedItem = item;
    itemSearch.text = item.name(Localizations.localeOf(context));
    costController.text = item.lastCost.toStringAsFixed(2);
  });

  void addLine() {
    final l = tr(context);
    final qty = parseAmount(qtyController.text);
    final cost = parseAmount(costController.text);
    if (selectedItem == null || qty <= 0 || cost <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.chooseItemWarning)));
      return;
    }
    setState(() {
      lines.add(
        ReceiveLine(
          item: selectedItem!,
          quantity: qty,
          cost: cost,
          costIsLine: costIsLine,
        ),
      );
      selectedItem = null;
      itemSearch.clear();
      qtyController.clear();
      costController.clear();
      costIsLine = false;
      paidNow = 0;
    });
    itemFocus.requestFocus();
  }

  void confirmReceive() {
    if (lines.isEmpty) return;
    final oldLines = List<ReceiveLine>.from(lines);
    final oldSupplier = supplier;
    setState(() {
      lines.clear();
      paidNow = 0;
      bonoController.clear();
      supplier = null;
      supplierSearch.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(tr(context).savedUndo),
        action: SnackBarAction(
          label: tr(context).undo,
          onPressed: () => setState(() {
            supplier = oldSupplier;
            lines.addAll(oldLines);
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final locale = Localizations.localeOf(context);
    final querySuppliers = suppliers
        .where((s) => s.matches(supplierSearch.text))
        .take(5)
        .toList();
    final queryItems = mockItems
        .where((item) => item.matches(itemSearch.text))
        .take(6)
        .toList();
    final qty = parseAmount(qtyController.text);
    final cost = parseAmount(costController.text);
    final lineTotal = costIsLine ? cost : qty * cost;
    final bono = parseAmount(bonoController.text);
    final mismatch =
        lines.isNotEmpty && bono > 0 && (bono - runningTotal).abs() > 0.01;

    return Scaffold(
      appBar: dukanAppBar(context, l.receiveTitle),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      supplier == null
                          ? l.supplierFirst
                          : l.receiveFrom(supplier!.name),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l.recentSuppliers,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: suppliers
                          .take(5)
                          .map(
                            (party) => ActionChip(
                              avatar: const Icon(Icons.local_shipping),
                              label: Text(party.name),
                              onPressed: () => chooseSupplier(party),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: supplierSearch,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: l.searchSuppliers,
                      ),
                    ),
                    if (supplierSearch.text.isNotEmpty)
                      ...querySuppliers.map(
                        (party) => ListTile(
                          leading: const Icon(Icons.store),
                          title: Text(party.name),
                          subtitle: Text(party.phone),
                          onTap: () => chooseSupplier(party),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.newSupplierStub)),
                          ),
                      icon: const Icon(Icons.add),
                      label: Text(l.newSupplier),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.history),
                            label: Text(l.repeatLastBono),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => bonoAttached = !bonoAttached),
                            icon: const Icon(Icons.photo_camera),
                            label: Text(
                              bonoAttached ? l.bonoAttached : l.attachBono,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (supplier != null) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.item,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        focusNode: itemFocus,
                        controller: itemSearch,
                        onChanged: (_) => setState(() => selectedItem = null),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          labelText: l.searchItem,
                        ),
                      ),
                      if (itemSearch.text.isNotEmpty && selectedItem == null)
                        ...queryItems.map(
                          (item) => ListTile(
                            leading: Icon(item.icon),
                            title: Text(item.name(locale)),
                            subtitle: Text(
                              '${item.unit(locale)} · ${money(item.lastCost)}',
                            ),
                            onTap: () => chooseItem(item),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: NumberField(
                              label: l.quantity,
                              controller: qtyController,
                              selected: false,
                              onTap: () =>
                                  openNumberSheet(qtyController, l.quantity),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: NumberField(
                              label: l.cost,
                              controller: costController,
                              selected: false,
                              onTap: () =>
                                  openNumberSheet(costController, l.cost),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<bool>(
                              showSelectedIcon: false,
                              segments: [
                                ButtonSegment(
                                  value: false,
                                  label: Text(l.perUnit),
                                ),
                                ButtonSegment(value: true, label: Text(l.line)),
                              ],
                              selected: {costIsLine},
                              onSelectionChanged: (set) =>
                                  setState(() => costIsLine = set.first),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${l.lineTotal}: ${money(lineTotal)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: addLine,
                        icon: const Icon(Icons.add_box),
                        label: Text(l.addLine),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${l.linesSoFar(lines.length)} · ${l.total}: ${money(runningTotal)}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                      ...lines
                          .take(4)
                          .map(
                            (line) => ListTile(
                              dense: true,
                              leading: Icon(line.item.icon),
                              title: Text(line.item.name(locale)),
                              subtitle: Text(
                                '${line.quantity.toStringAsShort()} × ${money(line.cost)}',
                              ),
                              trailing: Text(money(line.total)),
                            ),
                          ),
                      TextField(
                        controller: bonoController,
                        onChanged: (_) => setState(() {}),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: l.bonoTotal,
                          prefixIcon: const Icon(Icons.receipt_long),
                        ),
                      ),
                      if (mismatch)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            l.mismatchWarning,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        '${l.paidNow}: ${money(paidNow)} · ${l.credit}: ${money(math.max(0, runningTotal - paidNow))}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Slider(
                        min: 0,
                        max: runningTotal <= 0 ? 1 : runningTotal,
                        divisions: runningTotal <= 1
                            ? null
                            : math.max(1, runningTotal.round()),
                        value: paidNow.clamp(
                          0,
                          runningTotal <= 0 ? 1 : runningTotal,
                        ),
                        label: money(paidNow),
                        onChanged: lines.isEmpty
                            ? null
                            : (value) => setState(() => paidNow = value),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => paidNow = runningTotal),
                        icon: const Icon(Icons.done_all),
                        label: Text(l.paidAll),
                      ),
                      FilledButton.icon(
                        onPressed: lines.isEmpty ? null : confirmReceive,
                        icon: const Icon(Icons.check_circle),
                        label: Text(l.confirmReceive),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> openNumberSheet(
    TextEditingController controller,
    String title,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            NumberField(
              label: title,
              controller: controller,
              selected: true,
              onTap: () {},
            ),
            const SizedBox(height: 10),
            BigNumpad(controller: controller),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context).numberDone),
            ),
          ],
        ),
      ),
    );
    setState(() {});
  }
}

class InlinePartySearch extends StatefulWidget {
  const InlinePartySearch({
    required this.controller,
    required this.parties,
    required this.label,
    required this.hint,
    super.key,
  });
  final TextEditingController controller;
  final List<MockParty> parties;
  final String label;
  final String hint;

  @override
  State<InlinePartySearch> createState() => _InlinePartySearchState();
}

class _InlinePartySearchState extends State<InlinePartySearch> {
  @override
  Widget build(BuildContext context) {
    final matches = widget.parties
        .where((party) => party.matches(widget.controller.text))
        .take(3)
        .toList();
    return Column(
      children: [
        TextField(
          controller: widget.controller,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.person_search),
          ),
        ),
        if (widget.controller.text.isNotEmpty)
          ...matches.map(
            (party) => ListTile(
              title: Text(party.name),
              subtitle: Text(party.phone),
              onTap: () => setState(() => widget.controller.text = party.name),
            ),
          ),
      ],
    );
  }
}

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final customerController = TextEditingController();
  final amountController = TextEditingController();

  @override
  void dispose() {
    customerController.dispose();
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.paymentTitle),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              InlinePartySearch(
                controller: customerController,
                parties: customers,
                label: l.pickCustomer,
                hint: l.searchCustomers,
              ),
              const SizedBox(height: 12),
              NumberField(
                label: l.amount,
                controller: amountController,
                selected: false,
                onTap: () => openPaymentNumber(context),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: saveMock,
                  icon: const Icon(Icons.check_circle),
                  label: Text(l.confirmPayment),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> openPaymentNumber(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NumberField(
              label: tr(context).amount,
              controller: amountController,
              selected: true,
              onTap: () {},
            ),
            const SizedBox(height: 10),
            BigNumpad(controller: amountController),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context).numberDone),
            ),
          ],
        ),
      ),
    );
  }

  void saveMock() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(tr(context).comingSoon),
        action: SnackBarAction(label: tr(context).undo, onPressed: () {}),
      ),
    );
  }
}

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  final amountController = TextEditingController();
  String? category;

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final cats = [l.rent, l.power, l.salary, l.water, l.transport, l.other];
    return Scaffold(
      appBar: dukanAppBar(context, l.expenseTitle),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.category, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: cats
                    .map(
                      (cat) => ChoiceChip(
                        label: Text(cat),
                        selected: category == cat,
                        onSelected: (_) => setState(() => category = cat),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              NumberField(
                label: l.amount,
                controller: amountController,
                selected: false,
                onTap: () => openExpenseNumber(context),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: saveMock,
                icon: const Icon(Icons.check_circle),
                label: Text(l.confirmExpense),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> openExpenseNumber(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NumberField(
              label: tr(context).amount,
              controller: amountController,
              selected: true,
              onTap: () {},
            ),
            const SizedBox(height: 10),
            BigNumpad(controller: amountController),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context).numberDone),
            ),
          ],
        ),
      ),
    );
  }

  void saveMock() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(tr(context).comingSoon),
        action: SnackBarAction(label: tr(context).undo, onPressed: () {}),
      ),
    );
  }
}

extension on double {
  String toStringAsShort() =>
      this == roundToDouble() ? toStringAsFixed(0) : toStringAsFixed(2);
}
