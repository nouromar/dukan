import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/locale_controller.dart';

/// Default app bar used across the app.
///
/// `showLanguageToggle` is opt-in (default `false`) because once a shop
/// is selected, Settings owns the language and the shop's
/// `default_language_code` drives the locale. Pre-auth screens (phone
/// login, OTP, onboarding, shop picker, supabase config) pass `true`
/// so a non-signed-in user still has a way to switch language.
PreferredSizeWidget dukanAppBar(
  BuildContext context,
  String title, {
  List<Widget> actions = const [],
  bool showLanguageToggle = false,
  PreferredSizeWidget? bottom,
}) => AppBar(
  title: Text(title),
  actions: [
    ...actions,
    if (showLanguageToggle)
      const Padding(
        padding: EdgeInsetsDirectional.only(end: 12),
        child: LanguageToggle(),
      ),
  ],
  bottom: bottom,
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
