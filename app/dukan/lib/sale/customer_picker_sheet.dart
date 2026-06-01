import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

/// Opens the customer picker as a bottom sheet. Returns the chosen party,
/// or null if the user dismissed without picking. Wraps the sheet child
/// with `Provider<ShopApi>.value` so the sheet sees the API from the
/// calling context (otherwise pushing through the root Navigator would
/// lose the provider).
Future<PartySearchResult?> showCustomerPicker(
  BuildContext context, {
  required String shopId,
}) {
  final api = context.read<ShopApi>();
  return showModalBottomSheet<PartySearchResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => Provider<ShopApi>.value(
      value: api,
      child: _CustomerPickerBody(shopId: shopId),
    ),
  );
}

class _CustomerPickerBody extends StatefulWidget {
  const _CustomerPickerBody({required this.shopId});

  final String shopId;

  @override
  State<_CustomerPickerBody> createState() => _CustomerPickerBodyState();
}

class _CustomerPickerBodyState extends State<_CustomerPickerBody> {
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
      shopId: widget.shopId,
      query: query,
      type: 'customer',
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

  void _onTapNewCustomer() {
    showError(context, tr(context).customerNewUnavailable);
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + viewInsets),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.customerPickerTitle,
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
                  hintText: l.customerPickerSearchHint,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
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
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          l.customerPickerLoadFailedMessage,
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
                              ? l.customerPickerEmptyMessage
                              : l.customerPickerSearchEmptyMessage(
                                  _activeQuery,
                                ),
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
                            subtitle: Text(
                              party.receivable > 0
                                  ? l.customerPickerOwesLabel(
                                      _formatMoney(party.receivable),
                                    )
                                  : l.customerPickerNoDebtLabel,
                            ),
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
                onPressed: _onTapNewCustomer,
                child: Text(l.customerNewButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatMoney(double value) {
  if (value == value.roundToDouble()) {
    return '\$${value.toStringAsFixed(0)}';
  }
  return '\$${value.toStringAsFixed(2)}';
}
