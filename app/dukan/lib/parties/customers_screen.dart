// Customers screen — list, add, headline receivable total. Thin
// wrapper around PeopleScreen with kind=customer.

import 'package:flutter/material.dart';

import 'package:dukan/api/types.dart';
import 'package:dukan/parties/people_screen.dart';

class CustomersScreen extends StatelessWidget {
  const CustomersScreen({
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
      kind: PeopleKind.customer,
      initialHasBalanceOnly: initialHasBalanceOnly,
    );
  }
}
