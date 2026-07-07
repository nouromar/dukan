// Bind an unmatched ("Not found") bono line to a real shop item + packaging.
// Cloned from party_picker_sheet: a search field over searchItems('receive'),
// tap a result to select it (activating an unactivated catalog row first), or
// "Add new item" to create one. Returns the chosen target, or null on dismiss.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/receive/add_new_item_sheet.dart';
import 'package:dukan/shared/l10n.dart';

/// A concrete shop item + packaging to attach an unmatched bono line to.
class BonoBindTarget {
  const BonoBindTarget({
    required this.shopItemId,
    required this.shopItemUnitId,
    required this.itemId,
    required this.displayName,
    required this.packagingLabel,
    required this.baseUnitLabel,
  });

  final String shopItemId;
  final String shopItemUnitId;
  final String? itemId;
  final String displayName;
  final String packagingLabel;
  final String baseUnitLabel;
}

Future<BonoBindTarget?> showBonoBindItemPicker(
  BuildContext context, {
  required ShopSummary shop,
  String? supplierPartyId,
  String initialQuery = '',
}) {
  return showModalBottomSheet<BonoBindTarget>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BonoBindItemBody(
      shop: shop,
      supplierPartyId: supplierPartyId,
      initialQuery: initialQuery,
    ),
  );
}

class _BonoBindItemBody extends StatefulWidget {
  const _BonoBindItemBody({
    required this.shop,
    this.supplierPartyId,
    this.initialQuery = '',
  });

  final ShopSummary shop;
  final String? supplierPartyId;
  final String initialQuery;

  @override
  State<_BonoBindItemBody> createState() => _BonoBindItemBodyState();
}

class _BonoBindItemBodyState extends State<_BonoBindItemBody> {
  late final TextEditingController _searchController =
      TextEditingController(text: widget.initialQuery);
  Future<List<ItemSearchResult>> _resultsFuture = Future.value(const []);
  String _activeQuery = '';
  Timer? _debounce;
  bool _resolving = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // First run: _fetch reads Localizations, which isn't available in initState.
    if (_initialized) return;
    _initialized = true;
    _activeQuery = widget.initialQuery.trim();
    _resultsFuture = _fetch(_activeQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<ItemSearchResult>> _fetch(String query) {
    return context.read<ShopApi>().searchItems(
      shopId: widget.shop.id,
      query: query,
      screen: 'receive',
      partyId: widget.supplierPartyId,
      locale: Localizations.localeOf(context).languageCode,
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _activeQuery = value.trim();
        _resultsFuture = _fetch(_activeQuery);
      });
    });
  }

  Future<void> _onTapResult(ItemSearchResult item) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    final api = context.read<ShopApi>();
    final navigator = Navigator.of(context);
    try {
      BonoBindTarget? target;
      if (item.shopItemId != null && item.defaultShopItemUnitId != null) {
        target = BonoBindTarget(
          shopItemId: item.shopItemId!,
          shopItemUnitId: item.defaultShopItemUnitId!,
          itemId: item.itemId,
          displayName: item.displayName,
          packagingLabel: item.packagingLabel ??
              item.defaultUnitLabel ??
              item.baseUnitLabel,
          baseUnitLabel: item.baseUnitLabel,
        );
      } else if (item.itemId != null) {
        // Unactivated catalog row: activate, then take its default packaging.
        final newShopItemId = await api.ensureShopItem(
          shopId: widget.shop.id,
          itemId: item.itemId!,
        );
        final units = await api.listShopItemUnits(
          shopId: widget.shop.id,
          shopItemId: newShopItemId,
          screen: 'receive',
        );
        final unit = _pickUnit(units);
        if (unit != null) {
          target = BonoBindTarget(
            shopItemId: newShopItemId,
            shopItemUnitId: unit.shopItemUnitId,
            itemId: item.itemId,
            displayName: item.displayName,
            packagingLabel: unit.packagingLabel,
            baseUnitLabel: item.baseUnitLabel,
          );
        }
      }
      if (target != null) navigator.pop(target);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  ReceiveUnitOption? _pickUnit(List<ReceiveUnitOption> units) {
    if (units.isEmpty) return null;
    for (final u in units) {
      if (u.isDefault) return u;
    }
    for (final u in units) {
      if (u.isBaseUnit) return u;
    }
    return units.first;
  }

  Future<void> _onAddNew() async {
    final result = await AddNewItemSheet.show(
      context,
      widget.shop,
      initialName: _searchController.text.trim(),
    );
    if (result == null || !mounted) return;
    Navigator.of(context).pop(
      BonoBindTarget(
        shopItemId: result.shopItemId,
        shopItemUnitId: result.shopItemUnitId,
        itemId: null,
        displayName: result.displayName,
        packagingLabel: result.packagingLabel,
        baseUnitLabel: result.baseUnitLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final sheetHeight = MediaQuery.of(context).size.height * 0.6;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + viewInsets),
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.bonoBindPickerTitle,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l.bonoBindSearchHint,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<ItemSearchResult>>(
                  future: _resultsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final results =
                        snapshot.data ?? const <ItemSearchResult>[];
                    if (results.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          l.bonoBindEmpty,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final item = results[i];
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            minVerticalPadding: 14,
                            title: Text(
                              item.displayName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            subtitle: item.packagingLabel == null
                                ? null
                                : Text(item.packagingLabel!),
                            onTap:
                                _resolving ? null : () => _onTapResult(item),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _resolving ? null : _onAddNew,
                icon: const Icon(Icons.add),
                label: Text(l.bonoBindAddNew),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
