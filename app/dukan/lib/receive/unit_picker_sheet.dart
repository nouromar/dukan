// Bottom-sheet picker for an item's receive units. Triggered from the
// Receive line form when the cashier wants to enter the bono in a
// non-default unit (e.g., partial bag → kg). Lists every allow_receive
// unit for the item, with the conversion shown so the cashier can pick
// confidently. Default unit is flagged.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/shared/l10n.dart';

/// Opens the unit picker as a bottom sheet. Returns the chosen unit, or
/// null on dismiss. Pass either an activated `itemId` OR a catalog-only
/// `catalogItemId` (exactly one — the RPC enforces it).
Future<ReceiveUnitOption?> showUnitPicker(
  BuildContext context, {
  required String shopId,
  required String baseUnitLabel,
  String? itemId,
  String? catalogItemId,
}) {
  return showModalBottomSheet<ReceiveUnitOption>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _UnitPickerBody(
      shopId: shopId,
      baseUnitLabel: baseUnitLabel,
      itemId: itemId,
      catalogItemId: catalogItemId,
    ),
  );
}

class _UnitPickerBody extends StatefulWidget {
  const _UnitPickerBody({
    required this.shopId,
    required this.baseUnitLabel,
    required this.itemId,
    required this.catalogItemId,
  });

  final String shopId;
  final String baseUnitLabel;
  final String? itemId;
  final String? catalogItemId;

  @override
  State<_UnitPickerBody> createState() => _UnitPickerBodyState();
}

class _UnitPickerBodyState extends State<_UnitPickerBody> {
  late Future<List<ReceiveUnitOption>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ShopApi>().listItemUnits(
      shopId: widget.shopId,
      itemId: widget.itemId,
      catalogItemId: widget.catalogItemId,
      screen: 'receive',
    );
  }

  String _conversionLabel(BuildContext context, ReceiveUnitOption u) {
    final l = tr(context);
    if (u.conversionToBase == 1) {
      // Either it IS the base unit, or it's a unit-equal-to-base
      // (uncommon). The "base unit" badge is good enough either way.
      return l.unitPickerBaseUnit;
    }
    final multiplier = u.conversionToBase == u.conversionToBase.roundToDouble()
        ? u.conversionToBase.toInt().toString()
        : u.conversionToBase.toString();
    return l.unitPickerConversion(
      multiplier,
      widget.baseUnitLabel.toLowerCase(),
      u.unitLabel.toLowerCase(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.unitPickerTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<ReceiveUnitOption>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      l.unitPickerLoadFailedMessage,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  );
                }
                final units = snapshot.data ?? const <ReceiveUnitOption>[];
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: units.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final u = units[i];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        title: Row(
                          children: [
                            Text(
                              u.unitLabel,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (u.isDefault) ...[
                              const SizedBox(width: 8),
                              _DefaultBadge(text: l.unitPickerDefaultBadge),
                            ],
                          ],
                        ),
                        subtitle: Text(_conversionLabel(context, u)),
                        onTap: () => Navigator.of(context).pop(u),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
