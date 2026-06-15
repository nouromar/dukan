import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

/// Body of the email-login flow, no Scaffold of its own — designed to
/// sit inside the LoginScreen TabBarView next to PhoneLoginForm. Mirrors
/// the phone form's shape so users can switch tabs without losing context.
class EmailLoginForm extends StatefulWidget {
  const EmailLoginForm({super.key});

  @override
  State<EmailLoginForm> createState() => _EmailLoginFormState();
}

class _EmailLoginFormState extends State<EmailLoginForm> {
  final _emailController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() => _sending = true);
    try {
      await context.read<AuthController>().sendEmailOtp(_emailController.text);
    } on AuthInputException catch (error) {
      if (mounted) {
        showError(context, authInputErrorMessage(context, error.issue));
      }
    } on AuthException catch (error) {
      // Print the real Supabase error to console so logcat / flutter run
      // terminal surfaces it. Otherwise the user sees only the friendly
      // snackbar and the underlying "Email rate limit exceeded" /
      // "Invalid sender" / etc. is invisible.
      debugPrint('[email-login] AuthException: ${error.message}');
      if (mounted) {
        // Supabase returns a generic "signups not allowed" string when the
        // address doesn't match an existing user; surface the friendlier
        // "no account" copy in that case.
        final msg = (error.message).toLowerCase();
        final notFound =
            msg.contains('not allowed') || msg.contains('not found');
        showError(
          context,
          notFound
              ? tr(context).emailAccountNotFoundMessage
              : tr(context).sendEmailOtpFailedMessage,
        );
      }
    } catch (error, stackTrace) {
      // Network / unexpected errors (SocketException, TimeoutException)
      // don't surface as AuthException — log them too so spinning-then-
      // failing is debuggable from the terminal.
      debugPrint('[email-login] non-Auth error: $error');
      debugPrint('$stackTrace');
      if (mounted) {
        showError(context, tr(context).sendEmailOtpFailedMessage);
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
          Icons.mail_outline,
          size: 72,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 20),
        Text(
          l.loginEmailHeadline,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          l.loginEmailBody,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: l.emailAddressLabel),
          onSubmitted: (_) => _sending ? null : _sendOtp(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _sending ? null : _sendOtp,
          child: _sending
              ? const CircularProgressIndicator()
              : Text(l.sendEmailOtpButton),
        ),
      ],
    );
  }
}
