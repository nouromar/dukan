import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/l10n/generated/app_localizations.dart';
import 'package:dukan/shared/fallback_localizations.dart';
import 'package:dukan/shared/relative_time.dart';

/// Pumps a tiny widget that captures `BuildContext` so we can call
/// `formatRelativeTime(context, ...)` without mounting a real screen.
Future<String> _resolve(
  WidgetTester tester,
  DateTime when, {
  DateTime? now,
  Locale locale = const Locale('en'),
}) async {
  late String value;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FallbackMaterialLocalizationsDelegate(),
        FallbackWidgetsLocalizationsDelegate(),
        FallbackCupertinoLocalizationsDelegate(),
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        value = formatRelativeTime(context, when, now: now);
        return const SizedBox.shrink();
      }),
    ),
  );
  await tester.pumpAndSettle();
  return value;
}

void main() {
  final reference = DateTime(2026, 6, 12, 12, 0, 0);

  testWidgets('< 60s → "just now"', (tester) async {
    final out = await _resolve(
      tester,
      reference.subtract(const Duration(seconds: 30)),
      now: reference,
    );
    expect(out, 'just now');
  });

  testWidgets('5 min → "5 min ago"', (tester) async {
    final out = await _resolve(
      tester,
      reference.subtract(const Duration(minutes: 5)),
      now: reference,
    );
    expect(out, '5 min ago');
  });

  testWidgets('1 min → singular form', (tester) async {
    final out = await _resolve(
      tester,
      reference.subtract(const Duration(minutes: 1)),
      now: reference,
    );
    expect(out, '1 min ago');
  });

  testWidgets('3 hr → "3 hr ago"', (tester) async {
    final out = await _resolve(
      tester,
      reference.subtract(const Duration(hours: 3)),
      now: reference,
    );
    expect(out, '3 hr ago');
  });

  testWidgets('2 days → "2 days ago"', (tester) async {
    final out = await _resolve(
      tester,
      reference.subtract(const Duration(days: 2)),
      now: reference,
    );
    expect(out, '2 days ago');
  });

  testWidgets('Somali plural — 5 minutes', (tester) async {
    final out = await _resolve(
      tester,
      reference.subtract(const Duration(minutes: 5)),
      now: reference,
      locale: const Locale('so'),
    );
    expect(out, '5 daqiiqo ka hor');
  });

  testWidgets('future timestamp → "just now"', (tester) async {
    final out = await _resolve(
      tester,
      reference.add(const Duration(minutes: 5)),
      now: reference,
    );
    expect(out, 'just now');
  });

  testWidgets('> 30 days falls back to absolute date', (tester) async {
    final out = await _resolve(
      tester,
      reference.subtract(const Duration(days: 90)),
      now: reference,
    );
    // The fallback is locale-dependent; just verify the "on" wrapper
    // is applied and contains some date-looking content.
    expect(out, startsWith('on '));
    expect(out.length, greaterThan(3));
  });
}
