// Full-screen supplier picker that gates entry to the Receive screen.
// Receive is intrinsically supplier-scoped — the bono is from someone —
// so the picker is its own screen rather than a sheet over the lines
// grid. Picking a supplier replaces the route with ReceiveScreen so
// "back" returns the cashier to Home, not to the picker (a routine
// supplier change re-opens the picker from Receive's app bar action).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/receive/receive_controller.dart';
import 'package:dukan/receive/receive_screen.dart';
import 'package:dukan/shared/add_party_sheet.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/money.dart';
import 'package:dukan/sync/local_repository.dart';
import 'package:dukan/sync/use_local_db.dart';

class SupplierPickerScreen extends StatefulWidget {
  const SupplierPickerScreen({required this.shop, super.key});

  final ShopSummary shop;

  @override
  State<SupplierPickerScreen> createState() => _SupplierPickerScreenState();
}

class _SupplierPickerScreenState extends State<SupplierPickerScreen> {
  final _searchController = TextEditingController();
  late Future<List<PartySearchResult>> _resultsFuture;
  String _activeQuery = '';
  Timer? _debounce;

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
    if (useLocalDb(context)) {
      final repo = context.read<LocalRepository>();
      final rows = await repo.searchParties(
        query,
        shopId: widget.shop.id,
        typeCode: 'supplier',
      );
      return rows.map(repo.toPartySearchResult).toList(growable: false);
    }
    return context.read<ShopApi>().searchParties(
      shopId: widget.shop.id,
      query: query,
      type: 'supplier',
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

  Future<void> _onTapNewSupplier() async {
    final created = await showAddPartySheet(
      context,
      shopId: widget.shop.id,
      typeCode: 'supplier',
    );
    if (created != null && mounted) {
      // Auto-select: same flow as picking an existing supplier.
      _onPickSupplier(created);
    }
  }

  void _onPickSupplier(PartySearchResult supplier) {
    context.read<ReceiveController>().setSupplier(supplier);
    // Replace, not push: "back" from Receive should return to Home, not
    // re-open the picker. The Receive screen has its own affordance to
    // change supplier mid-bono.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ReceiveScreen(shop: widget.shop)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.supplierPickerTitle),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l.supplierPickerSearchHint,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<PartySearchResult>>(
                  future: _resultsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    if (snapshot.hasError) {
                      // #372: append raw error to surface the
                      // actual server failure during smoke
                      // testing. Temporary debug aid.
                      return _ErrorBlock(
                        message: '${l.supplierPickerLoadFailedMessage}\n'
                            '${snapshot.error}',
                      );
                    }
                    final results =
                        snapshot.data ?? const <PartySearchResult>[];
                    if (results.isEmpty) {
                      return _EmptyBlock(
                        message: _activeQuery.isEmpty
                            ? l.supplierPickerEmptyMessage
                            : l.supplierPickerSearchEmptyMessage(_activeQuery),
                      );
                    }
                    return ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _SupplierTile(
                        shop: widget.shop,
                        party: results[i],
                        onTap: () => _onPickSupplier(results[i]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _onTapNewSupplier,
                  child: Text(l.supplierNewButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierTile extends StatelessWidget {
  const _SupplierTile({
    required this.shop,
    required this.party,
    required this.onTap,
  });

  final ShopSummary shop;
  final PartySearchResult party;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final subtitle = party.payable > 0
        ? l.supplierPickerOwesLabel(formatMoney(party.payable, shop))
        : l.supplierPickerNoBonosLabel;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        minVerticalPadding: 14,
        title: Text(
          party.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

