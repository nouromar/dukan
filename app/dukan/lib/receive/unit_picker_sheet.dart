// Bottom-sheet picker for a shop_item's packagings. Triggered from the
// Receive (and Sale) line form when the cashier wants to enter the bono
// in a non-default packaging — e.g., the supplier delivered a 50 kg bag
// when the default is 25 kg. Lists every packaging for the item with
// the packaging label as identity (e.g., "25 kg bag") plus small badges
// for default / base unit. The conversion is implicit in the label, so
// we don't need to spell it out as a subtitle.
//
// At the bottom of the sheet there is a "+ Add packaging" button —
// tapping it opens the AddPackagingSheet directly, then (on success)
// closes the unit picker returning the new packaging to the caller as
// the picked option. The caller treats it like any other packaging
// selection: the receive line composer re-pre-fills from the new row
// without an extra trip back through the picker.
//
// `+ Add packaging` is only rendered when the caller supplies the
// `baseUnitLabel` — the AddPackagingSheet needs it to render the "How
// many kg per bag" prompt. Callers that don't pass it (e.g., test hosts
// or the eventual Sale-side picker) just don't get the affordance.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/receive/add_packaging_sheet.dart';
import 'package:dukan/shared/l10n.dart';

/// Opens the unit picker as a bottom sheet. Returns the chosen
/// packaging, or null on dismiss.
///
/// `shopItemId` must point at an activated shop_item. The caller is
/// expected to have run `ensureShopItem` for unactivated catalog rows
/// before reaching this sheet.
///
/// `screen` controls which default flag the rows surface as `isDefault`
/// — pass `'receive'` from the Receive flow and `'sale'` from Sale.
///
/// `baseUnitLabel` enables the inline "+ Add packaging" entry; when
/// null the entry is hidden (the AddPackagingSheet needs it to render
/// the conversion prompt).
Future<ReceiveUnitOption?> showUnitPicker(
  BuildContext context, {
  required String shopId,
  required String shopItemId,
  String screen = 'receive',
  String? baseUnitCode,
  String? baseUnitLabel,
  String? categoryId,
}) {
  return showModalBottomSheet<ReceiveUnitOption>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _UnitPickerBody(
      shopId: shopId,
      shopItemId: shopItemId,
      screen: screen,
      baseUnitCode: baseUnitCode,
      baseUnitLabel: baseUnitLabel,
      categoryId: categoryId,
    ),
  );
}

class _UnitPickerBody extends StatefulWidget {
  const _UnitPickerBody({
    required this.shopId,
    required this.shopItemId,
    required this.screen,
    required this.baseUnitCode,
    required this.baseUnitLabel,
    required this.categoryId,
  });

  final String shopId;
  final String shopItemId;
  final String screen;
  final String? baseUnitCode;
  final String? baseUnitLabel;
  final String? categoryId;

  @override
  State<_UnitPickerBody> createState() => _UnitPickerBodyState();
}

class _UnitPickerBodyState extends State<_UnitPickerBody> {
  late Future<List<ReceiveUnitOption>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ShopApi>().listShopItemUnits(
      shopId: widget.shopId,
      shopItemId: widget.shopItemId,
      screen: widget.screen,
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
                            Expanded(
                              child: Text(
                                u.packagingLabel,
                                style:
                                    Theme.of(context).textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (u.isDefault) ...[
                              const SizedBox(width: 8),
                              _Badge(text: l.unitPickerDefaultBadge),
                            ],
                            if (u.isBaseUnit) ...[
                              const SizedBox(width: 6),
                              _Badge(text: l.unitPickerBaseUnit),
                            ],
                          ],
                        ),
                        onTap: () => Navigator.of(context).pop(u),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 8),
            // "+ Add packaging" — opens the AddPackagingSheet inline.
            // On success we close the unit picker returning the new
            // packaging so the receive screen rebinds its line form
            // against it without an extra picker round-trip. Hidden
            // when the caller didn't supply baseUnitLabel + baseUnitCode
            // (both are needed for the suggestion query + custom form).
            if (widget.baseUnitLabel != null && widget.baseUnitCode != null)
              TextButton(
                onPressed: () async {
                  final added = await AddPackagingSheet.show(
                    context,
                    widget.shopId,
                    widget.shopItemId,
                    widget.baseUnitCode!,
                    widget.baseUnitLabel!,
                    categoryId: widget.categoryId,
                  );
                  if (added != null && context.mounted) {
                    Navigator.of(context).pop(added);
                  }
                },
                child: Text(l.unitPickerAddPackagingButton),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
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
