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

/// Language picker for pre-auth screens — a dropdown menu rather than a 2-way
/// toggle so it scales as more languages are added. Each language is shown in
/// its own name (endonym) so the picker reads naturally regardless of the
/// current locale. To offer a new language: add a row to [languages] and a
/// matching `app_<code>.arb`; the dropdown picks it up as-is.
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  static const List<({String code, String name})> languages = [
    (code: 'en', name: 'English'),
    (code: 'so', name: 'Soomaali'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = context.watch<LocaleController>().locale.languageCode;
    final currentName = languages
        .firstWhere((l) => l.code == current, orElse: () => languages.first)
        .name;
    return PopupMenuButton<String>(
      tooltip: tr(context).settingsLanguageLabel,
      position: PopupMenuPosition.under,
      onSelected: (code) =>
          context.read<LocaleController>().setLocale(Locale(code)),
      itemBuilder: (context) => [
        for (final lang in languages)
          PopupMenuItem<String>(
            value: lang.code,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: lang.code == current
                      ? Icon(Icons.check,
                          size: 18, color: theme.colorScheme.primary)
                      : null,
                ),
                const SizedBox(width: 10),
                Text(lang.name),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, size: 20),
            const SizedBox(width: 4),
            Text(currentName),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}
