import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

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
        showError(context, authInputErrorMessage(context, error.issue));
      }
    } on AuthException {
      if (mounted) {
        showError(context, tr(context).verifyOtpFailedMessage);
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
