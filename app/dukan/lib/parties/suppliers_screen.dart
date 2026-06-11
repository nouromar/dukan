// Suppliers screen — list, add, headline payable total. Thin wrapper
// around PeopleScreen with kind=supplier.

import 'package:flutter/material.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/parties/people_screen.dart';

class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({
    required this.shop,
    this.initialHasBalanceOnly = false,
    super.key,
  });

  final ShopSummary shop;
  final bool initialHasBalanceOnly;

  @override
  Widget build(BuildContext context) {
    return PeopleScreen(
      shop: shop,
      kind: PeopleKind.supplier,
      initialHasBalanceOnly: initialHasBalanceOnly,
    );
  }
}
