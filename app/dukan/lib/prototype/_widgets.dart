// Shared widgets used by the prototype Sale/Receive/Payment/Expense screens
// while they're still mock-data backed. Each daily flow will eventually
// replace its consumers with real-data widgets, at which point this file
// disappears alongside the rest of lib/prototype/.

import 'package:flutter/material.dart';

import 'package:dukan/shared/l10n.dart';

class NumberField extends StatelessWidget {
  const NumberField({
    required this.label,
    required this.controller,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final String label;
  final TextEditingController controller;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderSide: BorderSide(width: selected ? 3 : 1),
        ),
      ),
      style: Theme.of(context).textTheme.titleLarge,
    );
  }
}

class BigNumpad extends StatelessWidget {
  const BigNumpad({required this.controller, super.key});
  final TextEditingController controller;

  void append(String value) {
    if (value == '.' && controller.text.contains('.')) return;
    controller.text += value;
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final labels = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '.', '0', l.backspace,
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.0,
      ),
      itemCount: labels.length + 1,
      itemBuilder: (context, index) {
        if (index == labels.length) {
          return OutlinedButton(
            onPressed: () => controller.clear(),
            child: Text(l.clear),
          );
        }
        final label = labels[index];
        return OutlinedButton(
          onPressed: () {
            if (label == l.backspace) {
              if (controller.text.isNotEmpty) {
                controller.text = controller.text.substring(
                  0,
                  controller.text.length - 1,
                );
              }
            } else {
              append(label);
            }
          },
          child: Text(
            label,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        );
      },
    );
  }
}
