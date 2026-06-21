import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/auth/sign_out_flow.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/l10n.dart';

class ShopPickerScreen extends StatelessWidget {
  const ShopPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final auth = context.watch<AuthController>();
    return Scaffold(
      appBar: dukanAppBar(
        context,
        l.chooseShopTitle,
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
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: auth.shops.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final shop = auth.shops[index];
            return Card(
              child: ListTile(
                minVerticalPadding: 18,
                title: Text(
                  shop.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(l.shopSetupStatus(shop.setupStatus)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.read<AuthController>().selectShop(shop),
              ),
            );
          },
        ),
      ),
    );
  }
}
