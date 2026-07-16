// Getting-started guide shown once after a fresh shop reaches
// setup_status='ready'. Pure INSTRUCTIONS (not action cards): a short numbered
// guide of how to run the shop, plus a single START SELLING primary CTA that
// dismisses the guide and pops into Home. It orients a new owner without
// pushing them into a flow — the template already seeded the catalog.
//
// Dismissal is one-shot: START SELLING fires `dismissOnboarding`, which sets
// `shop.onboarding_dismissed_at` (a timestamp column on shop, see 0003 + 0010).
// After that, the AuthRouter goes straight to HomeScreen on subsequent sign-ins.
//
// Per data-model-v2 §3 locked decision: this is a *recommendation*, not a gate.
// The shop is "ready" the moment template_applied completes; this never blocks
// selling.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

class SetupItemOnboardingScreen extends StatefulWidget {
  const SetupItemOnboardingScreen({
    required this.shop,
    this.asGuide = false,
    super.key,
  });

  final ShopSummary shop;

  /// When opened from the menu as a reference (a pushed route), the CTA just
  /// closes the guide and it does NOT dismiss onboarding. The default (false)
  /// is the one-shot setup step the AuthRouter mounts after a fresh shop.
  final bool asGuide;

  @override
  State<SetupItemOnboardingScreen> createState() =>
      _SetupItemOnboardingScreenState();
}

class _SetupItemOnboardingScreenState extends State<SetupItemOnboardingScreen> {
  bool _dismissing = false;

  Future<void> _dismissAndPushHome() async {
    if (_dismissing) return;
    setState(() => _dismissing = true);
    final l = tr(context);
    final api = context.read<ShopApi>();
    final auth = context.read<AuthController>();
    try {
      await api.dismissOnboarding(shopId: widget.shop.id);
      await auth.refreshSelectedShop();
      // AuthRouter watches selectedShop; once shop.onboardingDismissedAt is
      // non-null, it falls through to HomeScreen and this screen unmounts.
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'dukan setup',
          context: ErrorDescription('dismiss_shop_onboarding'),
        ),
      );
      if (mounted) showError(context, l.settingsSaveFailedMessage);
    } finally {
      if (mounted) setState(() => _dismissing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.setupOnboardingTitle),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.setupGuideIntro, style: theme.textTheme.titleMedium),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  children: [
                    _Step(1, l.setupGuideStep1Title, l.setupGuideStep1Body),
                    _Step(2, l.setupGuideStep2Title, l.setupGuideStep2Body),
                    _Step(3, l.setupGuideStep3Title, l.setupGuideStep3Body),
                    _Step(4, l.setupGuideStep4Title, l.setupGuideStep4Body),
                    const SizedBox(height: 10),
                    Text(
                      l.setupGuideFootnote,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _dismissing
                    ? null
                    : (widget.asGuide
                        ? () => Navigator.of(context).pop()
                        : _dismissAndPushHome),
                child: _dismissing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.asGuide
                            ? l.setupGuideDoneButton
                            : l.setupOnboardingSkipButton,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One instruction line: a numbered badge + title + explanation. Read-only —
/// it tells the owner what to do, it doesn't launch a flow.
class _Step extends StatelessWidget {
  const _Step(this.number, this.title, this.body);

  final int number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
