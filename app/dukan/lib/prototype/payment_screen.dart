// Prototype Payment screen (mock data only). Replaced in slice 5 of the
// mobile UI rebuild; see docs/ux-screens.md §5.7 for the design target.

import 'package:flutter/material.dart';

import 'package:dukan/mock/mock_data.dart';
import 'package:dukan/prototype/_widgets.dart';
import 'package:dukan/prototype/inline_party_search.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/l10n.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final customerController = TextEditingController();
  final amountController = TextEditingController();

  @override
  void dispose() {
    customerController.dispose();
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Scaffold(
      appBar: dukanAppBar(context, l.paymentTitle),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              InlinePartySearch(
                controller: customerController,
                parties: customers,
                label: l.pickCustomer,
                hint: l.searchCustomers,
              ),
              const SizedBox(height: 12),
              NumberField(
                label: l.amount,
                controller: amountController,
                selected: false,
                onTap: () => openPaymentNumber(context),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: saveMock,
                  icon: const Icon(Icons.check_circle),
                  label: Text(l.confirmPayment),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> openPaymentNumber(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NumberField(
              label: tr(context).amount,
              controller: amountController,
              selected: true,
              onTap: () {},
            ),
            const SizedBox(height: 10),
            BigNumpad(controller: amountController),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context).numberDone),
            ),
          ],
        ),
      ),
    );
  }

  void saveMock() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(tr(context).comingSoon),
        action: SnackBarAction(label: tr(context).undo, onPressed: () {}),
      ),
    );
  }
}
