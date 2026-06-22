import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/shared/add_party_sheet.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/offline_mode.dart';

/// Bottom-sheet party picker, used by both Sale (typeCode='customer'
/// for debt sales) and Payment (either type). Returns the chosen party
/// or null on dismiss. Providers come from AuthBootstrap above
/// MaterialApp; no per-call re-export needed.
Future<PartySearchResult?> showPartyPicker(
  BuildContext context, {
  required ShopSummary shop,
  required String typeCode,
}) {
  return showModalBottomSheet<PartySearchResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PartyPickerBody(shop: shop, typeCode: typeCode),
  );
}

class _PartyPickerBody extends StatefulWidget {
  const _PartyPickerBody({required this.shop, required this.typeCode});

  final ShopSummary shop;
  final String typeCode;

  @override
  State<_PartyPickerBody> createState() => _PartyPickerBodyState();
}

class _PartyPickerBodyState extends State<_PartyPickerBody> {
  final _searchController = TextEditingController();
  late Future<List<PartySearchResult>> _resultsFuture;
  String _activeQuery = '';
  Timer? _debounce;

  bool get _isSupplier => widget.typeCode == 'supplier';

  @override
  void initState() {
    super.initState();
    _resultsFuture = _fetch('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<PartySearchResult>> _fetch(String query) async {
    // #374: local mirror when offline_mode = full.
    if (offlineModeFull(context)) {
      final repo = context.read<LocalRepository>();
      final rows = await repo.searchParties(
        query,
        shopId: widget.shop.id,
        typeCode: widget.typeCode,
      );
      return rows.map(repo.toPartySearchResult).toList(growable: false);
    }
    return context.read<ShopApi>().searchParties(
      shopId: widget.shop.id,
      query: query,
      type: widget.typeCode,
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

  Future<void> _onTapAdd() async {
    final created = await showAddPartySheet(
      context,
      shopId: widget.shop.id,
      typeCode: widget.typeCode,
    );
    if (created != null && mounted) {
      Navigator.of(context).pop(created);
    }
  }

  String _balanceLabelFor(PartySearchResult party, AppLocalizations l) {
    if (_isSupplier) {
      return party.payable > 0
          ? l.supplierPickerOwesLabel(formatMoney(party.payable, widget.shop))
          : l.supplierPickerNoBonosLabel;
    }
    return party.receivable > 0
        ? l.customerPickerOwesLabel(formatMoney(party.receivable, widget.shop))
        : l.customerPickerNoDebtLabel;
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final mediaHeight = MediaQuery.of(context).size.height;
    final sheetHeight = mediaHeight * 0.55;
    final title = _isSupplier
        ? l.supplierPickerTitle
        : l.customerPickerTitle;
    final searchHint = _isSupplier
        ? l.supplierPickerSearchHint
        : l.customerPickerSearchHint;
    final emptyMessage = _isSupplier
        ? l.supplierPickerEmptyMessage
        : l.customerPickerEmptyMessage;
    final loadFailedMessage = _isSupplier
        ? l.supplierPickerLoadFailedMessage
        : l.customerPickerLoadFailedMessage;
    final newButtonLabel = _isSupplier
        ? l.supplierNewButton
        : l.customerNewButton;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + viewInsets),
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
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
                  hintText: searchHint,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<PartySearchResult>>(
                  future: _resultsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      // #372: append raw error to surface the
                      // actual server failure during smoke
                      // testing. Temporary debug aid.
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          '$loadFailedMessage\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      );
                    }
                    final results =
                        snapshot.data ?? const <PartySearchResult>[];
                    if (results.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _activeQuery.isEmpty
                              ? emptyMessage
                              : (_isSupplier
                                    ? l.supplierPickerSearchEmptyMessage(
                                        _activeQuery,
                                      )
                                    : l.customerPickerSearchEmptyMessage(
                                        _activeQuery,
                                      )),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final party = results[i];
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            minVerticalPadding: 14,
                            title: Text(
                              party.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            subtitle: Text(_balanceLabelFor(party, l)),
                            onTap: () => Navigator.of(context).pop(party),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _onTapAdd,
                child: Text(newButtonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
