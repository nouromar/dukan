// Bottom-sheet language picker. Two options (English / Somali);
// taps switch the LocaleController and dismiss the sheet. The
// current language is shown with a check mark.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dukan/shared/l10n.dart';
import 'package:dukan/shared/locale_controller.dart';

Future<void> showLanguageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => const _LanguageSheetBody(),
  );
}

class _LanguageSheetBody extends StatelessWidget {
  const _LanguageSheetBody();

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    final controller = context.watch<LocaleController>();
    final current = controller.locale.languageCode;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LanguageTile(
              code: 'en',
              label: l.languageEnglish,
              selected: current == 'en',
            ),
            _LanguageTile(
              code: 'so',
              label: l.languageSomali,
              selected: current == 'so',
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.code,
    required this.label,
    required this.selected,
  });

  final String code;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      minVerticalPadding: 12,
      title: Text(
        label,
        style: theme.textTheme.titleMedium,
      ),
      trailing: selected
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      onTap: () {
        context.read<LocaleController>().setLocale(Locale(code));
        Navigator.of(context).maybePop();
      },
    );
  }
}
