// Optional item-onboarding step shown once after a fresh shop reaches
// setup_status='ready'. Three skippable cards push the shopkeeper into
// helper flows (Add my items, Set prices on top items, Browse the
// catalog) and a SKIP — START SELLING primary CTA pops them straight
// into Home.
//
// Dismissal is one-shot: tapping any card or SKIP fires
// `dismissOnboarding`, which sets `shop.onboarding_dismissed_at` (a
// timestamp column on shop, see 0003 + 0010). After that, the
// AuthRouter goes straight to HomeScreen on subsequent sign-ins.
//
// Per data-model-v2 §3 locked decision: this is a *recommendation*, not
// a gate. The shop is "ready" the moment template_applied completes;
// this screen never blocks selling.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/products/catalog_picker_screen.dart';
import 'package:dukan/products/products_screen.dart';
import 'package:dukan/sale/add_new_item_sheet.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

class SetupItemOnboardingScreen extends StatefulWidget {
  const SetupItemOnboardingScreen({required this.shop, super.key});

  final ShopSummary shop;

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
      // AuthRouter watches selectedShop; once
      // shop.onboardingDismissedAt is non-null, it falls through to
      // HomeScreen and this screen unmounts.
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

  Future<void> _pushAndDismiss(Widget destination) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => destination));
    // Whatever the shopkeeper did inside, dismiss the onboarding card
    // so they don't see it again next time.
    if (mounted) await _dismissAndPushHome();
  }

  /// "Add my own items" — the simplified product-create sheet ("Save & add
  /// another" lets them add many in a row), then dismiss the onboarding card.
  Future<void> _addProductsAndDismiss() async {
    await AddNewItemSheet.show(
      context,
      widget.shop,
      initialName: '',
      variant: AddNewItemVariant.product,
    );
    if (mounted) await _dismissAndPushHome();
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
              Text(
                // Body uses count + template placeholders; v1.5 will
                // wire the real counts. For now, generic-ish:
                l.setupOnboardingBody(
                  '—',
                  widget.shop.name,
                ),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _OnboardingCard(
                title: l.setupOnboardingAddItemsTitle,
                body: l.setupOnboardingAddItemsBody,
                icon: Icons.add_box_outlined,
                onTap: _dismissing ? null : _addProductsAndDismiss,
              ),
              const SizedBox(height: 12),
              _OnboardingCard(
                title: l.setupOnboardingSetPricesTitle,
                body: l.setupOnboardingSetPricesBody,
                icon: Icons.attach_money,
                onTap: _dismissing
                    ? null
                    : () => _pushAndDismiss(
                          ProductsScreen(shop: widget.shop),
                        ),
              ),
              const SizedBox(height: 12),
              _OnboardingCard(
                title: l.setupOnboardingBrowseCatalogTitle,
                body: l.setupOnboardingBrowseCatalogBody,
                icon: Icons.library_books_outlined,
                onTap: _dismissing
                    ? null
                    : () => _pushAndDismiss(
                          CatalogPickerScreen(shop: widget.shop),
                        ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _dismissing ? null : _dismissAndPushHome,
                child: _dismissing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.setupOnboardingSkipButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String body;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium,
                    ),
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
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
