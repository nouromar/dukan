import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/config/business_rules.dart';
import 'package:dukan/shared/digit_input.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

/// Standalone phone-login screen (Scaffold + AppBar). Retained for the
/// widget tests that drive PhoneLoginScreen directly; the production
/// auth flow now uses LoginScreen which embeds PhoneLoginForm next to
/// EmailLoginForm in a TabBar.
class PhoneLoginScreen extends StatelessWidget {
  const PhoneLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: dukanAppBar(
        context,
        tr(context).loginTitle,
        showLanguageToggle: true,
      ),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: PhoneLoginForm(),
        ),
      ),
    );
  }
}

/// Body of the phone-login flow, with no Scaffold of its own so it can
/// be embedded in a TabBarView. The standalone PhoneLoginScreen above
/// wraps it for backward-compat with widget tests.
class PhoneLoginForm extends StatefulWidget {
  const PhoneLoginForm({super.key});

  @override
  State<PhoneLoginForm> createState() => _PhoneLoginFormState();
}

class _PhoneLoginFormState extends State<PhoneLoginForm> {
  final _phoneController = TextEditingController(text: defaultCountryCode);
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
        showError(context, authInputErrorMessage(context, error.issue));
      }
    } on AuthException {
      if (mounted) {
        showError(context, tr(context).sendOtpFailedMessage);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
          // Phone numbers must stay ASCII for E.164 normalization;
          // accept "+" plus ASCII / Arabic / Persian digits.
          textDirection: TextDirection.ltr,
          inputFormatters: const [PhoneDigitsInputFormatter()],
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
    );
  }
}
