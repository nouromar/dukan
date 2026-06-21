import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/auth/sign_out_flow.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

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
        showError(context, authInputErrorMessage(context, error.issue));
      }
    } on PostgrestException {
      if (mounted) {
        showError(context, tr(context).createShopFailedMessage);
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
        showLanguageToggle: true,
        actions: [
          IconButton(
            tooltip: l.signOut,
            onPressed: () => confirmSignOut(context),
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
