import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/locale_controller.dart';

PreferredSizeWidget dukanAppBar(
  BuildContext context,
  String title, {
  List<Widget> actions = const [],
}) => AppBar(
  title: Text(title),
  actions: [
    ...actions,
    const Padding(
      padding: EdgeInsetsDirectional.only(end: 12),
      child: LanguageToggle(),
    ),
  ],
);

class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final current = context.watch<LocaleController>().locale.languageCode;
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: 'en', label: Text(tr(context).languageEnglish)),
        ButtonSegment(value: 'so', label: Text(tr(context).languageSomali)),
      ],
      selected: {current},
      onSelectionChanged: (selected) =>
          context.read<LocaleController>().setLocale(Locale(selected.first)),
      style: ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.padded,
        minimumSize: WidgetStateProperty.all(const Size(56, 48)),
      ),
    );
  }
}
