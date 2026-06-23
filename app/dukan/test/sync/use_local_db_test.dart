// #382: dual-key resolution for `useLocalDb`. Locks in the
// backwards-compat mapping for `offline_mode` rows set before
// the rename. Pure logic test against the resolver layer — no
// widget tree.

import 'package:flutter_test/flutter_test.dart';

import 'package:dukan/config/config_keys.dart';
import 'package:dukan/config/config_resolver.dart';
import 'package:dukan/storage/app_database.dart';
import 'package:dukan/storage/device_config_dao.dart';
import 'package:dukan/sync/use_local_db.dart';

import '../shared/fakes.dart';
import '../shared/test_database.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = await openTestDatabase();
  });

  tearDown(() async {
    await database.close();
  });

  ConfigResolver makeResolver(Map<String, Object?> values) {
    return _FixedResolver(values, database);
  }

  group('resolveUseLocalDb — new key precedence', () {
    test('use_local_db = true → true', () {
      expect(
        resolveUseLocalDb(makeResolver({'use_local_db': true})),
        isTrue,
      );
    });

    test('use_local_db = false → false', () {
      expect(
        resolveUseLocalDb(makeResolver({'use_local_db': false})),
        isFalse,
      );
    });

    test('use_local_db string "true"/"false" round-trips through parser', () {
      expect(
        resolveUseLocalDb(makeResolver({'use_local_db': 'true'})),
        isTrue,
      );
      expect(
        resolveUseLocalDb(makeResolver({'use_local_db': 'false'})),
        isFalse,
      );
    });
  });

  group('resolveUseLocalDb — legacy offline_mode fallback', () {
    test('legacy offline_mode = "full" → true', () {
      expect(
        resolveUseLocalDb(makeResolver({'offline_mode': 'full'})),
        isTrue,
      );
    });

    test('legacy offline_mode = "light" → false', () {
      expect(
        resolveUseLocalDb(makeResolver({'offline_mode': 'light'})),
        isFalse,
      );
    });
  });

  group('resolveUseLocalDb — precedence + default', () {
    test('no override → default (true)', () {
      expect(resolveUseLocalDb(makeResolver({})), isTrue);
      expect(ConfigKeys.useLocalDb.defaultValue, isTrue);
    });

    test('new key wins over legacy when both set', () {
      // use_local_db=false beats legacy offline_mode=full.
      expect(
        resolveUseLocalDb(makeResolver({
          'use_local_db': false,
          'offline_mode': 'full',
        })),
        isFalse,
      );
      // And the reverse: use_local_db=true beats legacy offline_mode=light.
      expect(
        resolveUseLocalDb(makeResolver({
          'use_local_db': true,
          'offline_mode': 'light',
        })),
        isTrue,
      );
    });

    test('unparseable new key falls through to legacy', () {
      // Garbage `use_local_db` → parser throws → fall to legacy.
      expect(
        resolveUseLocalDb(makeResolver({
          'use_local_db': 'maybe',
          'offline_mode': 'light',
        })),
        isFalse,
      );
    });
  });
}

class _FixedResolver extends ConfigResolver {
  _FixedResolver(Map<String, Object?> values, AppDatabase db)
      : _values = values,
        super(
          shopApi: FakeShopApi(),
          deviceConfigDao: DeviceConfigDao(Future.value(db)),
        );
  final Map<String, Object?> _values;

  @override
  Object? rawOverride(String keyName) {
    if (_values.containsKey(keyName)) return _values[keyName];
    return super.rawOverride(keyName);
  }
}
