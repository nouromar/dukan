// Home drawer — the "look something up later" surface for everything
// that isn't a daily Sale/Receive/Payment/Expense. Grouped so the
// shopkeeper can find things by intent (history vs reports vs setup)
// without scanning a flat list.
//
// Daily-flow access stays on Home (the 4-tile grid + Today card
// shortcuts). The drawer is intentionally NOT the main path for any
// daily action.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/auth/auth_controller.dart';
import 'package:dukan/expense/expense_history_screen.dart';
import 'package:dukan/parties/customers_screen.dart';
import 'package:dukan/parties/suppliers_screen.dart';
import 'package:dukan/payment/payment_history_screen.dart';
import 'package:dukan/products/products_screen.dart';
import 'package:dukan/products/top_movers_screen.dart';
import 'package:dukan/receive/receive_history_screen.dart';
import 'package:dukan/reports/low_stock_screen.dart';
import 'package:dukan/reports/reports_screen.dart';
import 'package:dukan/sale/sale_history_screen.dart';
import 'package:dukan/settings/manage_categories_screen.dart';
import 'package:dukan/settings/settings_screen.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/storage/storage_sync_screen.dart';

class DukanDrawer extends StatelessWidget {
  const DukanDrawer({required this.shop, this.onSignOut, super.key});
  final ShopSummary shop;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final theme = Theme.of(context);
    final caps = context.watch<AuthController>().capabilities;
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Slim header — colored strip with app + shop on one row.
            // ~72dp instead of the old 160dp DrawerHeader, leaving room
            // for the 11 items below without scrolling on most phones.
            Container(
              color: theme.colorScheme.primary,
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + 8,
                16,
                12,
              ),
              child: Row(
                children: [
                  Text(
                    l.appTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      shop.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _DrawerItem(
              icon: Icons.bar_chart,
              label: l.drawerReports,
              builder: (_) => ReportsScreen(shop: shop),
            ),
            const SizedBox(height: 4),
            _SectionHeader(label: l.drawerHistoryHeader),
            _DrawerItem(
              icon: Icons.point_of_sale,
              label: l.drawerSalesHistory,
              builder: (_) => SaleHistoryScreen(shop: shop),
            ),
            _DrawerItem(
              icon: Icons.inventory_2_outlined,
              label: l.drawerReceiveHistory,
              builder: (_) => ReceiveHistoryScreen(shop: shop),
            ),
            _DrawerItem(
              icon: Icons.receipt_long_outlined,
              label: l.drawerExpenseHistory,
              builder: (_) => ExpenseHistoryScreen(shop: shop),
            ),
            _DrawerItem(
              icon: Icons.payments_outlined,
              label: l.drawerPaymentHistory,
              builder: (_) => PaymentHistoryScreen(shop: shop),
            ),
            const SizedBox(height: 4),
            _SectionHeader(label: l.drawerPeopleHeader),
            _DrawerItem(
              icon: Icons.person_outline,
              label: l.drawerCustomers,
              builder: (_) => CustomersScreen(shop: shop),
            ),
            _DrawerItem(
              icon: Icons.local_shipping_outlined,
              label: l.drawerSuppliers,
              builder: (_) => SuppliersScreen(shop: shop),
            ),
            const SizedBox(height: 4),
            _SectionHeader(label: l.drawerProductsHeader),
            _DrawerItem(
              icon: Icons.label_outline,
              label: l.drawerProducts,
              builder: (_) => ProductsScreen(shop: shop),
            ),
            _DrawerItem(
              icon: Icons.warning_amber_outlined,
              label: l.drawerLowStock,
              builder: (_) => LowStockScreen(shop: shop),
            ),
            _DrawerItem(
              icon: Icons.trending_up,
              label: l.drawerTopMovers,
              builder: (_) => TopMoversScreen(shop: shop),
            ),
            const SizedBox(height: 4),
            _SectionHeader(label: l.drawerSetupHeader),
            _DrawerItem(
              icon: Icons.settings,
              label: l.drawerSettings,
              builder: (_) => SettingsScreen(shop: shop),
            ),
            if (caps.canManageCategories)
              _DrawerItem(
                icon: Icons.category_outlined,
                label: l.drawerManageCategories,
                builder: (_) => ManageCategoriesScreen(shop: shop),
              ),
            _DrawerItem(
              icon: Icons.cloud_sync_outlined,
              label: l.storageSyncDrawerEntry,
              builder: (_) => const StorageSyncScreen(),
            ),
            if (onSignOut != null) ...[
              const Divider(height: 24),
              // Logout sits at the bottom of the drawer (moved
              // from the home AppBar) so the daily-flow screens
              // don't show a destructive action above the fold.
              ListTile(
                dense: true,
                leading: const Icon(Icons.logout),
                title: Text(l.signOut),
                onTap: () {
                  Navigator.of(context).pop();  // close drawer
                  onSignOut!.call();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.builder,
  });

  final IconData icon;
  final String label;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    // Dense + trimmed padding shaves ~12dp/row × 11 rows ≈ 130dp so
    // every group fits without scroll on a 6" phone. Tap target stays
    // ≥48dp via minVerticalPadding.
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      horizontalTitleGap: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      minLeadingWidth: 24,
      leading: Icon(icon, size: 22),
      title: Text(label),
      onTap: () {
        // Close the drawer first, then push so the user sees the
        // destination animate in cleanly.
        Navigator.of(context).pop();
        Navigator.of(context).push(MaterialPageRoute(builder: builder));
      },
    );
  }
}
