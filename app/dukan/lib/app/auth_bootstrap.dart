import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/auth/otp_verification_screen.dart';
import 'package:dukan/auth/owner_onboarding_screen.dart';
import 'package:dukan/auth/phone_login_screen.dart';
import 'package:dukan/auth/shop_picker_screen.dart';
import 'package:dukan/home/home_screen.dart';
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
