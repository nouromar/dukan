// Prototype Receive screen (mock data only). Replaced in slice 3 of the
// mobile UI rebuild; see docs/ux-screens.md §5.4 for the design target.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:dukan/mock/mock_data.dart';
import 'package:dukan/prototype/_widgets.dart';
import 'package:dukan/shared/dukan_app_bar.dart';
import 'package:dukan/shared/formatting.dart';
import 'package:dukan/shared/l10n.dart';

class ReceiveLine {
  ReceiveLine({
    required this.item,
    required this.quantity,
    required this.cost,
    required this.costIsLine,
  });
  final MockItem item;
  final double quantity;
  final double cost;
  final bool costIsLine;
  double get total => costIsLine ? cost : cost * quantity;
}

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final supplierSearch = TextEditingController();
  final itemSearch = TextEditingController();
  final qtyController = TextEditingController();
  final costController = TextEditingController();
  final bonoController = TextEditingController();
  final itemFocus = FocusNode();
  MockParty? supplier;
  MockItem? selectedItem;
  bool costIsLine = false;
  bool bonoAttached = false;
  double paidNow = 0;
  final lines = <ReceiveLine>[];

  @override
  void dispose() {
    supplierSearch.dispose();
    itemSearch.dispose();
    qtyController.dispose();
    costController.dispose();
    bonoController.dispose();
    itemFocus.dispose();
    super.dispose();
  }

  double get runningTotal => lines.fold(0, (sum, line) => sum + line.total);

  void chooseSupplier(MockParty party) => setState(() {
    supplier = party;
    supplierSearch.text = party.name;
  });

  void chooseItem(MockItem item) => setState(() {
    selectedItem = item;
    itemSearch.text = item.name(Localizations.localeOf(context));
    costController.text = item.lastCost.toStringAsFixed(2);
  });

  void addLine() {
    final l = tr(context);
    final qty = parseAmount(qtyController.text);
    final cost = parseAmount(costController.text);
    if (selectedItem == null || qty <= 0 || cost <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.chooseItemWarning)));
      return;
    }
    setState(() {
      lines.add(
        ReceiveLine(
          item: selectedItem!,
          quantity: qty,
          cost: cost,
          costIsLine: costIsLine,
        ),
      );
      selectedItem = null;
      itemSearch.clear();
      qtyController.clear();
      costController.clear();
      costIsLine = false;
      paidNow = 0;
    });
    itemFocus.requestFocus();
  }

  void confirmReceive() {
    if (lines.isEmpty) return;
    final oldLines = List<ReceiveLine>.from(lines);
    final oldSupplier = supplier;
    setState(() {
      lines.clear();
      paidNow = 0;
      bonoController.clear();
      supplier = null;
      supplierSearch.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(tr(context).savedUndo),
        action: SnackBarAction(
          label: tr(context).undo,
          onPressed: () => setState(() {
            supplier = oldSupplier;
            lines.addAll(oldLines);
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final locale = Localizations.localeOf(context);
    final querySuppliers = suppliers
        .where((s) => s.matches(supplierSearch.text))
        .take(5)
        .toList();
    final queryItems = mockItems
        .where((item) => item.matches(itemSearch.text))
        .take(6)
        .toList();
    final qty = parseAmount(qtyController.text);
    final cost = parseAmount(costController.text);
    final lineTotal = costIsLine ? cost : qty * cost;
    final bono = parseAmount(bonoController.text);
    final mismatch =
        lines.isNotEmpty && bono > 0 && (bono - runningTotal).abs() > 0.01;

    return Scaffold(
      appBar: dukanAppBar(context, l.receiveTitle),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      supplier == null
                          ? l.supplierFirst
                          : l.receiveFrom(supplier!.name),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l.recentSuppliers,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: suppliers
                          .take(5)
                          .map(
                            (party) => ActionChip(
                              avatar: const Icon(Icons.local_shipping),
                              label: Text(party.name),
                              onPressed: () => chooseSupplier(party),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: supplierSearch,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: l.searchSuppliers,
                      ),
                    ),
                    if (supplierSearch.text.isNotEmpty)
                      ...querySuppliers.map(
                        (party) => ListTile(
                          leading: const Icon(Icons.store),
                          title: Text(party.name),
                          subtitle: Text(party.phone),
                          onTap: () => chooseSupplier(party),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.newSupplierStub)),
                          ),
                      icon: const Icon(Icons.add),
                      label: Text(l.newSupplier),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.history),
                            label: Text(l.repeatLastBono),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => bonoAttached = !bonoAttached),
                            icon: const Icon(Icons.photo_camera),
                            label: Text(
                              bonoAttached ? l.bonoAttached : l.attachBono,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (supplier != null) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.item,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        focusNode: itemFocus,
                        controller: itemSearch,
                        onChanged: (_) => setState(() => selectedItem = null),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          labelText: l.searchItem,
                        ),
                      ),
                      if (itemSearch.text.isNotEmpty && selectedItem == null)
                        ...queryItems.map(
                          (item) => ListTile(
                            leading: Icon(item.icon),
                            title: Text(item.name(locale)),
                            subtitle: Text(
                              '${item.unit(locale)} · ${money(item.lastCost)}',
                            ),
                            onTap: () => chooseItem(item),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: NumberField(
                              label: l.quantity,
                              controller: qtyController,
                              selected: false,
                              onTap: () =>
                                  openNumberSheet(qtyController, l.quantity),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: NumberField(
                              label: l.cost,
                              controller: costController,
                              selected: false,
                              onTap: () =>
                                  openNumberSheet(costController, l.cost),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<bool>(
                              showSelectedIcon: false,
                              segments: [
                                ButtonSegment(
                                  value: false,
                                  label: Text(l.perUnit),
                                ),
                                ButtonSegment(value: true, label: Text(l.line)),
                              ],
                              selected: {costIsLine},
                              onSelectionChanged: (set) =>
                                  setState(() => costIsLine = set.first),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${l.lineTotal}: ${money(lineTotal)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: addLine,
                        icon: const Icon(Icons.add_box),
                        label: Text(l.addLine),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${l.linesSoFar(lines.length)} · ${l.total}: ${money(runningTotal)}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                      ...lines
                          .take(4)
                          .map(
                            (line) => ListTile(
                              dense: true,
                              leading: Icon(line.item.icon),
                              title: Text(line.item.name(locale)),
                              subtitle: Text(
                                '${line.quantity.toStringAsShort()} × ${money(line.cost)}',
                              ),
                              trailing: Text(money(line.total)),
                            ),
                          ),
                      TextField(
                        controller: bonoController,
                        onChanged: (_) => setState(() {}),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: l.bonoTotal,
                          prefixIcon: const Icon(Icons.receipt_long),
                        ),
                      ),
                      if (mismatch)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            l.mismatchWarning,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        '${l.paidNow}: ${money(paidNow)} · ${l.credit}: ${money(math.max(0, runningTotal - paidNow))}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Slider(
                        min: 0,
                        max: runningTotal <= 0 ? 1 : runningTotal,
                        divisions: runningTotal <= 1
                            ? null
                            : math.max(1, runningTotal.round()),
                        value: paidNow.clamp(
                          0,
                          runningTotal <= 0 ? 1 : runningTotal,
                        ),
                        label: money(paidNow),
                        onChanged: lines.isEmpty
                            ? null
                            : (value) => setState(() => paidNow = value),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => paidNow = runningTotal),
                        icon: const Icon(Icons.done_all),
                        label: Text(l.paidAll),
                      ),
                      FilledButton.icon(
                        onPressed: lines.isEmpty ? null : confirmReceive,
                        icon: const Icon(Icons.check_circle),
                        label: Text(l.confirmReceive),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> openNumberSheet(
    TextEditingController controller,
    String title,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            NumberField(
              label: title,
              controller: controller,
              selected: true,
              onTap: () {},
            ),
            const SizedBox(height: 10),
            BigNumpad(controller: controller),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context).numberDone),
            ),
          ],
        ),
      ),
    );
    setState(() {});
  }
}

extension on double {
  String toStringAsShort() =>
      this == roundToDouble() ? toStringAsFixed(0) : toStringAsFixed(2);
}
