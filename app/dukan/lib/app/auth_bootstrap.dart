import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/auth/otp_verification_screen.dart';
import 'package:dukan/auth/owner_onboarding_screen.dart';
import 'package:dukan/auth/phone_login_screen.dart';
import 'package:dukan/auth/shop_picker_screen.dart';
import 'package:dukan/home/home_screen.dart';
import 'package:dukan/sale/cart_controller.dart';
import 'package:dukan/setup/shop_type_setup_screen.dart';
import 'package:dukan/shared/friendly_error_screen.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/loading_screen.dart';

class AuthBootstrap extends StatefulWidget {
  const AuthBootstrap({required this.supabaseClient, super.key});

  final SupabaseClient supabaseClient;

  @override
  State<AuthBootstrap> createState() => _AuthBootstrapState();
}

class _AuthBootstrapState extends State<AuthBootstrap> {
  late final ShopApi _shopApi;
  late final AuthController _authController;
  late final CartController _cartController;
  bool _hadSession = false;

  @override
  void initState() {
    super.initState();
    _shopApi = ShopApi(widget.supabaseClient);
    _authController =
        AuthController(client: widget.supabaseClient, shopApi: _shopApi)
          ..start();
    _cartController = CartController();
    // Clear the cart whenever the session transitions to null (sign-out
    // or session expiry). Stops a held cart from leaking across users
    // sharing the same device.
    _authController.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    final hasSession = _authController.session != null;
    if (_hadSession && !hasSession) {
      _cartController.clearAll();
    }
    _hadSession = hasSession;
  }

  @override
  void dispose() {
    _authController.removeListener(_onAuthChanged);
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
      ],
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
