import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/expense/expense_screen.dart';
import 'package:dukan/payment/payment_screen.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/receive/receive_screen.dart';
import 'package:dukan/receive/supplier_picker_screen.dart';
import 'package:dukan/receive/receive_history_screen.dart';
import 'package:dukan/sale/sale_history_screen.dart';
import 'package:dukan/sale/sale_screen.dart';
import 'package:dukan/settings/settings_screen.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/l10n.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.shop, this.onSignOut});

  final ShopSummary? shop;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(
        context,
        l.appTitle,
        actions: [
          if (shop != null)
            PopupMenuButton<_HistoryDestination>(
              tooltip: l.historyMenuTooltip,
              icon: const Icon(Icons.history),
              onSelected: (choice) {
                final route = switch (choice) {
                  _HistoryDestination.sales =>
                    MaterialPageRoute<void>(
                      builder: (_) => SaleHistoryScreen(shop: shop!),
                    ),
                  _HistoryDestination.receives =>
                    MaterialPageRoute<void>(
                      builder: (_) => ReceiveHistoryScreen(shop: shop!),
                    ),
                };
                Navigator.of(context).push(route);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _HistoryDestination.sales,
                  child: Text(l.historyMenuSales),
                ),
                PopupMenuItem(
                  value: _HistoryDestination.receives,
                  child: Text(l.historyMenuReceives),
                ),
              ],
            ),
          if (shop != null)
            IconButton(
              tooltip: l.openSettings,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(shop: shop!),
                ),
              ),
              icon: const Icon(Icons.settings),
            ),
          if (onSignOut != null)
            IconButton(
              tooltip: l.signOut,
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final buttonAreaHeight = math.min(
                360.0,
                constraints.maxHeight * 0.58,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.homeHint,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (shop != null) ...[
                    const SizedBox(height: 12),
                    Chip(
                      avatar: const Icon(Icons.storefront),
                      label: Text(l.activeShopLabel(shop!.name)),
                    ),
                  ],
                  const Spacer(),
                  SizedBox(
                    height: buttonAreaHeight,
                    child: GridView.count(
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 1.55,
                      children: [
                        HomeAction(
                          icon: Icons.point_of_sale,
                          label: l.sale,
                          onTap: shop == null
                              ? () {}
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SaleScreen(shop: shop!),
                                  ),
                                ),
                        ),
                        HomeAction(
                          icon: Icons.inventory_2,
                          label: l.receive,
                          onTap: shop == null
                              ? () {}
                              : () {
                                  final receive =
                                      context.read<ReceiveController>();
                                  // Resume a partial bono if one is in
                                  // flight; otherwise start from the
                                  // supplier picker. Supplier alone is
                                  // not enough to count as "in flight"
                                  // — we resume only when actual lines
                                  // exist, so an aborted picker visit
                                  // doesn't pin us to a stale supplier.
                                  final destination = receive.isNotEmpty
                                      ? ReceiveScreen(shop: shop!)
                                      : SupplierPickerScreen(shop: shop!);
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => destination,
                                    ),
                                  );
                                },
                        ),
                        HomeAction(
                          icon: Icons.payments,
                          label: l.payment,
                          onTap: shop == null
                              ? () {}
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PaymentScreen(shop: shop!),
                                  ),
                                ),
                        ),
                        HomeAction(
                          icon: Icons.receipt_long,
                          label: l.expense,
                          onTap: shop == null
                              ? () {}
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ExpenseScreen(shop: shop!),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _HistoryDestination { sales, receives }

class HomeAction extends StatelessWidget {
  const HomeAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 34),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
