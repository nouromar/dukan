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
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/l10n.dart';

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

  Future<List<PartySearchResult>> _fetch(String query) {
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
    // Mirror the customer-picker placeholder. Real supplier-add lands
    // with the admin portal / Settings.
    final l = tr(context);
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        content: Text(l.supplierNewUnavailable),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(MaterialLocalizations.of(dialogCtx).okButtonLabel),
          ),
        ],
      ),
    );
  }

  void _onPickSupplier(PartySearchResult supplier) {
    final api = context.read<ShopApi>();
    final receive = context.read<ReceiveController>();
    receive.setSupplier(supplier);
    // Replace, not push: "back" from Receive should return to Home, not
    // re-open the picker. The Receive screen has its own affordance to
    // change supplier mid-bono. Re-export providers so ReceiveScreen
    // sees them under the root Navigator (the providers are scoped to
    // AuthBootstrap, which lives inside MaterialApp, not above it).
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MultiProvider(
          providers: [
            Provider<ShopApi>.value(value: api),
            ChangeNotifierProvider<ReceiveController>.value(value: receive),
          ],
          child: ReceiveScreen(shop: widget.shop),
        ),
      ),
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
                      return _ErrorBlock(
                        message: l.supplierPickerLoadFailedMessage,
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
  const _SupplierTile({required this.party, required this.onTap});

  final PartySearchResult party;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final subtitle = party.payable > 0
        ? l.supplierPickerOwesLabel(_formatMoney(party.payable))
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

String _formatMoney(num value) {
  final v = value.toDouble();
  if (v == v.roundToDouble()) {
    return '\$${v.toStringAsFixed(0)}';
  }
  return '\$${v.toStringAsFixed(2)}';
}
