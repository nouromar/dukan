// In-memory sqflite database for unit + widget tests. Tests construct
// one with `await openTestDatabase()` and either inject DAOs against
// it or seed it as the singleton (flutter_test_config does the
// latter so production code paths that call AppDatabase.instance()
// transparently get the test DB).
//
// Uses sqflite_common_ffi's NoIsolate factory: keeps the SQL engine
// on the test's main isolate so widget tests' pumpAndSettle can
// drain the futures. The Isolate-based default factory uses cross-
// isolate message passing that the fake-async test binding can't
// see, which causes pumpAndSettle to time out waiting for the
// queries to resolve.
//
// Each call returns a FRESH in-memory database so tests stay
// isolated.

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dukan/storage/app_database.dart';

bool _ffiInitialized = false;

void _ensureFfiInitialized() {
  if (_ffiInitialized) return;
  sqfliteFfiInit();
  // NoIsolate: SQL runs on the calling isolate so widget tests'
  // pumpAndSettle can drain the futures. The default Isolate
  // factory blocks pumpAndSettle indefinitely.
  databaseFactory = databaseFactoryFfiNoIsolate;
  _ffiInitialized = true;
}

/// Open a fresh in-memory AppDatabase. Each call yields a new
/// instance — tests don't share state.
Future<AppDatabase> openTestDatabase() async {
  _ensureFfiInitialized();
  return AppDatabase.openAt(inMemoryDatabasePath);
}
