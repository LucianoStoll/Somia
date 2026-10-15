const schemaV27 = <String>[
  '''CREATE TABLE import_batches (
    id TEXT PRIMARY KEY NOT NULL,
    account_id TEXT NOT NULL,
    source_name TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    undone_at INTEGER)''',
  '''CREATE TABLE import_batch_entries (
    id TEXT PRIMARY KEY NOT NULL,
    batch_id TEXT NOT NULL,
    target_table TEXT NOT NULL CHECK(target_table IN
      ('transactions','transfers','transaction_settlements','card_payments')),
    target_id TEXT NOT NULL,
    action TEXT NOT NULL CHECK(action IN ('created','linked')),
    source_line INTEGER NOT NULL,
    initial_updated_at INTEGER NOT NULL,
    initial_sync_version INTEGER NOT NULL,
    undone_at INTEGER)''',
  'CREATE INDEX import_batch_entries_batch ON import_batch_entries(batch_id)',
  'CREATE INDEX import_batch_entries_target ON import_batch_entries(target_table,target_id,undone_at)',
];
