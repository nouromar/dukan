// Prototype Expense screen (mock data only). Replaced in slice 6 of the
// mobile UI rebuild; see docs/ux-screens.md §5.8 for the design target.

import 'package:flutter/material.dart';

import 'package:dukan/prototype/_widgets.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/l10n.dart';

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  final amountController = TextEditingController();
  String? category;

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final cats = [l.rent, l.power, l.salary, l.water, l.transport, l.other];
    return Scaffold(
      appBar: dukanAppBar(context, l.expenseTitle),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.category, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: cats
                    .map(
                      (cat) => ChoiceChip(
                        label: Text(cat),
                        selected: category == cat,
                        onSelected: (_) => setState(() => category = cat),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              NumberField(
                label: l.amount,
                controller: amountController,
                selected: false,
                onTap: () => openExpenseNumber(context),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: saveMock,
                icon: const Icon(Icons.check_circle),
                label: Text(l.confirmExpense),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> openExpenseNumber(BuildContext context) async {
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
