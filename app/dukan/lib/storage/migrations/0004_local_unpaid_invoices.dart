// Schema migration #0004 — adds local_unpaid_invoice mirror table
// so the Payment allocation sheet (#391) reads from local cache
// when useLocalDb=true.
//
// Direction is stored as the same single-char encoding the server
// uses ('I' = inbound/sale, 'O' = outbound/receive). A row with
// remaining <= 0 is treated as a tombstone by
// LocalRepository.applyUnpaidInvoicesPayload — DELETE rather than
// upsert. The server's _build_unpaid_invoices_payload emits paid-
// off rows for one delta window so the local mirror can drop them.

import 'package:sqflite/sqflite.dart';

Future<void> applyLocalUnpaidInvoicesMigration(Database db) async {
  await db.execute('''
    CREATE TABLE local_unpaid_invoice (
      shop_id              TEXT NOT NULL,
      party_id             TEXT NOT NULL,
      direction            TEXT NOT NULL,
      txn_id               TEXT NOT NULL,
      occurred_at_ms       INTEGER NOT NULL,
      original_amount      REAL NOT NULL,
      already_paid         REAL NOT NULL,
      remaining            REAL NOT NULL,
      document_id          TEXT,
      server_updated_at_ms INTEGER NOT NULL,
      PRIMARY KEY (party_id, direction, txn_id)
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_local_unpaid_shop_party_dir '
    'ON local_unpaid_invoice(shop_id, party_id, direction)',
  );
}
