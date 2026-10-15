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
    transaction_id TEXT NOT NULL UNIQUE,
    source_line INTEGER NOT NULL,
    initial_updated_at INTEGER NOT NULL,
    initial_sync_version INTEGER NOT NULL)''',
  'CREATE INDEX import_batch_entries_batch ON import_batch_entries(batch_id)',
];
