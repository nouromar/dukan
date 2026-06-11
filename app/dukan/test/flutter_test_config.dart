// Package-wide test setup. Flutter's test runner picks this file up
// by convention (any file named flutter_test_config.dart sitting at
// or above a test) and wraps every test in this dartTestConfiguration
// so we get cross-test isolation for process-global state.
//
// Currently used for:
//   * FavoritesCache — process-global cache, cleared in setUp so a
//     prior test's cached favorites don't leak into the next test's
//     view of the Sale or Receive screens.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dukan/scanner/scanner_settings.dart';
import 'package:dukan/shared/favorites_cache.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    FavoritesCache.clear();
    FavoritesCache.nowForTesting = null;
    // Reset SharedPreferences so the TodaySummaryCache (and any
    // future persistent caches) start each test from a clean slate.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Scanner settings is a process-global; a previous test's custom
    // tuning would leak into the next test's HID listener / multi-
    // scan rearm window.
    ScannerSettings.resetForTesting();
  });
  await testMain();
}
