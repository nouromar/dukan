// Schema migration #0003 — adds client_op_id to local_transaction
// so optimistic-write rows (inserted at queue-enqueue time, per
// #385) can be deduped-and-replaced when the server's
// authoritative row arrives via delta sync.
//
// Optimistic rows are inserted at #383's `_saveWithQueue` shell
// with `txn_id = client_op_id` as a placeholder; the server later
// assigns its own UUID. The dedup lookup in
// `LocalRepository.applyTransactionsPayload` matches by
// `client_op_id` (NOT `txn_id`) and DELETEs the optimistic row
// inside the same sqflite transaction that INSERTs the server
// row, so history never shows a flash of missing-row or a
// duplicate.

import 'package:sqflite/sqflite.dart';

Future<void> applyLocalTransactionOptimisticMigration(Database db) async {
  await db.execute(
    'ALTER TABLE local_transaction ADD COLUMN client_op_id TEXT',
  );
  // Non-unique: optimistic rows + server rows may briefly coexist
  // inside the same dedup-and-replace transaction. The DELETE
  // happens before the INSERT, so no constraint violation either
  // way — but a UNIQUE index would have to be partial / deferred,
  // and a plain index is enough for the WHERE client_op_id = ?
  // lookup.
  await db.execute(
    'CREATE INDEX idx_local_txn_client_op_id '
    'ON local_transaction(client_op_id)',
  );
}
