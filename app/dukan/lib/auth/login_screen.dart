import 'package:flutter/material.dart';

import 'package:dukan/auth/email_login_screen.dart';
import 'package:dukan/auth/phone_login_screen.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/l10n.dart';

/// Tabbed sign-in surface. Phone tab uses the existing Twilio/SMS path
/// (mobile-first), Email tab uses Supabase email OTP. Email defaults to
/// the first tab because pilot Supabase doesn't have Phone provider
/// credentials yet — users can still switch to Phone for local-stack
/// testing where +252612345678/123456 is fixtured.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: dukanAppBar(
          context,
          l.loginTitle,
          showLanguageToggle: true,
          bottom: TabBar(
            tabs: [
              Tab(text: l.loginTabEmail),
              Tab(text: l.loginTabPhone),
            ],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: EmailLoginForm(),
              ),
              SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: PhoneLoginForm(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
