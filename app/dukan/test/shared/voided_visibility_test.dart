import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/shared/voided_visibility.dart';
import 'package:dukan/storage/app_database.dart';

import 'test_database.dart';

void main() {
  setUp(() async {
    AppDatabase.seedSingletonForTesting(await openTestDatabase());
  });

  tearDown(() async {
    await AppDatabase.resetForTesting();
  });

  test('defaults to show when nothing is stored', () async {
    expect(await VoidedVisibility.showVoided(), isTrue);
  });

  test('setShowVoided(false) hides; setShowVoided(true) shows again', () async {
    await VoidedVisibility.setShowVoided(false);
    expect(await VoidedVisibility.showVoided(), isFalse);

    await VoidedVisibility.setShowVoided(true);
    expect(await VoidedVisibility.showVoided(), isTrue);
  });
}
