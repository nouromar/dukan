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

import 'package:dukan/shared/favorites_cache.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    FavoritesCache.clear();
    FavoritesCache.nowForTesting = null;
  });
  await testMain();
}
