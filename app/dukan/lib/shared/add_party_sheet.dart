// Shared "+ NEW {CUSTOMER,SUPPLIER}" form. Bottom sheet with name +
// optional phone fields. On SAVE: creates the party via the
// create_party RPC and returns a PartySearchResult so the caller can
// auto-select it (a customer just added → immediately selected for
// the in-flight debt sale; a supplier just added → goes straight into
// the receive flow).
//
// One sheet, two type_codes — Sale's customer picker and Receive's
// supplier picker both call this with the right typeCode.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dukan/api/shop_api.dart';
import 'package:dukan/api/types.dart';
import 'package:dukan/shared/feedback.dart';
import 'package:dukan/shared/l10n.dart';

/// `typeCode` must be 'customer' or 'supplier'. Returns the new
/// PartySearchResult on success; null on cancel / error / dismiss.
///
/// When [allowOpeningBalance] is true (Parties-screen FAB only), the
/// sheet renders a numeric opening-balance field; entering a positive
/// amount also posts a no-line opening txn so reports stay coherent.
Future<PartySearchResult?> showAddPartySheet(
  BuildContext context, {
  required String shopId,
  required String typeCode,
  bool allowOpeningBalance = false,
}) {
  return showModalBottomSheet<PartySearchResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AddPartyBody(
      shopId: shopId,
      typeCode: typeCode,
      allowOpeningBalance: allowOpeningBalance,
    ),
  );
}

class _AddPartyBody extends StatefulWidget {
  const _AddPartyBody({
    required this.shopId,
    required this.typeCode,
    required this.allowOpeningBalance,
  });

  final String shopId;
  final String typeCode;
  final bool allowOpeningBalance;

  @override
  State<_AddPartyBody> createState() => _AddPartyBodyState();
}

class _AddPartyBodyState extends State<_AddPartyBody> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _openingController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _openingController.dispose();
    super.dispose();
  }

  num? get _parsedOpening {
    final raw = _openingController.text.trim();
    if (raw.isEmpty) return null;
    final v = num.tryParse(raw);
    if (v == null || v <= 0) return null;
    return v;
  }

  Future<void> _onSave() async {
    final l = tr(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showError(context, l.partyNewNameRequiredMessage);
      return;
    }
    final phone = _phoneController.text.trim();
    final opening = _parsedOpening;
    setState(() => _saving = true);
    try {
      final api = context.read<ShopApi>();
      final partyId = await api.createParty(
        shopId: widget.shopId,
        name: name,
        typeCode: widget.typeCode,
        phone: phone.isEmpty ? null : phone,
      );
      // Optional opening balance — direction depends on type.
      if (widget.allowOpeningBalance && opening != null) {
        final direction = widget.typeCode == 'supplier' ? 'O' : 'I';
        await api.postOpeningPartyBalance(
          shopId: widget.shopId,
          partyId: partyId,
          amount: opening,
          direction: direction,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        PartySearchResult(
          id: partyId,
          name: name,
          phone: phone.isEmpty ? null : phone,
          typeCode: widget.typeCode,
          receivable: widget.typeCode == 'customer'
              ? (opening?.toDouble() ?? 0)
              : 0,
          payable: widget.typeCode == 'supplier'
              ? (opening?.toDouble() ?? 0)
              : 0,
        ),
      );
    } on PostgrestException catch (error, stackTrace) {
      _handleFailure(error, stackTrace, l.partyNewSaveFailedMessage);
    } catch (error, stackTrace) {
      _handleFailure(error, stackTrace, l.partyNewSaveFailedMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _handleFailure(Object error, StackTrace stackTrace, String message) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'dukan party',
        context: ErrorDescription('create_party'),
      ),
    );
    if (!mounted) return;
    showError(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final title = widget.typeCode == 'supplier'
        ? l.partyNewSupplierTitle
        : l.partyNewCustomerTitle;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + viewInsets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l.partyNewNameLabel,
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: widget.allowOpeningBalance
                  ? TextInputAction.next
                  : TextInputAction.done,
              decoration: InputDecoration(
                labelText: l.partyNewPhoneLabel,
                isDense: true,
              ),
              onSubmitted: (_) {
                if (!widget.allowOpeningBalance && !_saving) _onSave();
              },
            ),
            if (widget.allowOpeningBalance) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _openingController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: widget.typeCode == 'supplier'
                      ? l.partyNewOpeningPayableLabel
                      : l.partyNewOpeningReceivableLabel,
                  helperText: l.partyNewOpeningBalanceHelper,
                  isDense: true,
                ),
                onSubmitted: (_) => _saving ? null : _onSave(),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _onSave,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(l.partyNewSaveButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
