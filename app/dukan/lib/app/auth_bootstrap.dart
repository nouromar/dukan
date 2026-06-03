import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/auth/otp_verification_screen.dart';
import 'package:dukan/auth/owner_onboarding_screen.dart';
import 'package:dukan/auth/phone_login_screen.dart';
import 'package:dukan/auth/shop_picker_screen.dart';
import 'package:dukan/expense/expense_controller.dart';
import 'package:dukan/home/home_screen.dart';
import 'package:dukan/payment/payment_controller.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/sale/cart_controller.dart';
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
  bool _hadSession = false;

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
    // Clear in-progress carts/bonos/payments/expenses whenever the
    // session transitions to null (sign-out or session expiry). Stops
    // state from leaking across users sharing the same device.
    _authController.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    final hasSession = _authController.session != null;
    if (_hadSession && !hasSession) {
      _cartController.clearAll();
      _receiveController.clearAll();
      _paymentController.clearAll();
      _expenseController.clearAll();
    }
    _hadSession = hasSession;
  }

  @override
  void dispose() {
    _authController.removeListener(_onAuthChanged);
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
