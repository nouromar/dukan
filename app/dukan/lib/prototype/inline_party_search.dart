// Shared inline party search used by the prototype Sale/Receive/Payment
// screens. Replaced by the proper Customer/Supplier picker bottom sheets
// when slice 2 (Sale) and slice 3 (Receive) land.

import 'package:flutter/material.dart';

import 'package:dukan/mock/mock_data.dart';

class InlinePartySearch extends StatefulWidget {
  const InlinePartySearch({
    required this.controller,
    required this.parties,
    required this.label,
    required this.hint,
    super.key,
  });
  final TextEditingController controller;
  final List<MockParty> parties;
  final String label;
  final String hint;

  @override
  State<InlinePartySearch> createState() => _InlinePartySearchState();
}

class _InlinePartySearchState extends State<InlinePartySearch> {
  @override
  Widget build(BuildContext context) {
    final matches = widget.parties
        .where((party) => party.matches(widget.controller.text))
        .take(3)
        .toList();
    return Column(
      children: [
        TextField(
          controller: widget.controller,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.person_search),
          ),
        ),
        if (widget.controller.text.isNotEmpty)
          ...matches.map(
            (party) => ListTile(
              title: Text(party.name),
              subtitle: Text(party.phone),
              onTap: () => setState(() => widget.controller.text = party.name),
            ),
          ),
      ],
    );
  }
}
