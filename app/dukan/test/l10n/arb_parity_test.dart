// Makes the documented "missing Somali = release blocker" rule real (CLAUDE.md):
// app_en.arb and app_so.arb must carry the exact same message keys. Without this,
// gen-l10n silently falls back to the English template for any key missing from
// Somali, so an untranslated string ships looking fine in code review.
//
// (The per-role length budget is tracked as an advisory report by
// l10n-review/build_worklist.py until the Somali rewrite clears the backlog; it
// can be promoted to a hard assertion here once overflows reach zero.)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> _messageKeys(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  // Real message keys only — drop @@locale and @meta blocks.
  return json.keys.where((k) => !k.startsWith('@')).toSet();
}

void main() {
  test('app_en.arb and app_so.arb have identical message keys', () {
    final en = _messageKeys('lib/l10n/app_en.arb');
    final so = _messageKeys('lib/l10n/app_so.arb');

    final missingInSo = en.difference(so);
    final extraInSo = so.difference(en);

    expect(
      missingInSo,
      isEmpty,
      reason: 'Keys in app_en.arb missing from app_so.arb (untranslated): '
          '$missingInSo',
    );
    expect(
      extraInSo,
      isEmpty,
      reason: 'Keys in app_so.arb not in app_en.arb (stale): $extraInSo',
    );
  });

  test('no Somali value is left identical-empty where English has content', () {
    final enJson =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>;
    final soJson =
        jsonDecode(File('lib/l10n/app_so.arb').readAsStringSync()) as Map<String, dynamic>;
    final blanks = <String>[];
    for (final k in enJson.keys) {
      if (k.startsWith('@')) continue;
      final en = enJson[k];
      final so = soJson[k];
      if (en is String && en.trim().isNotEmpty &&
          (so is! String || so.trim().isEmpty)) {
        blanks.add(k);
      }
    }
    expect(blanks, isEmpty, reason: 'Somali blank for: $blanks');
  });
}
