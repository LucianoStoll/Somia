/// Metadados locais de sincronização. Nunca recebem credenciais Google.
const schemaV11 = <String>[
  '''CREATE TABLE sync_state (
    id INTEGER PRIMARY KEY CHECK(id=1), base_id TEXT, email TEXT,
    device_id TEXT, capture_enabled INTEGER NOT NULL DEFAULT 0,
    clock INTEGER NOT NULL DEFAULT 0, last_sync_at INTEGER
  )''',
  'INSERT INTO sync_state(id) VALUES(1)',
  '''CREATE TABLE sync_versions (
    table_name TEXT NOT NULL, row_id TEXT NOT NULL, clock INTEGER NOT NULL,
    device_id TEXT NOT NULL, is_deleted INTEGER NOT NULL, data TEXT,
    PRIMARY KEY(table_name,row_id)
  )''',
  '''CREATE TABLE sync_outbox (
    table_name TEXT NOT NULL, row_id TEXT NOT NULL, clock INTEGER NOT NULL,
    device_id TEXT NOT NULL, is_deleted INTEGER NOT NULL, data TEXT,
    PRIMARY KEY(table_name,row_id)
  )''',
  '''CREATE TABLE sync_history (
    table_name TEXT NOT NULL, row_id TEXT NOT NULL, clock INTEGER NOT NULL,
    device_id TEXT NOT NULL, is_deleted INTEGER NOT NULL, data TEXT,
    reason TEXT NOT NULL, archived_at INTEGER NOT NULL,
    PRIMARY KEY(table_name,row_id,clock,device_id)
  )''',
  '''CREATE TABLE sync_applied (
    packet_id TEXT PRIMARY KEY NOT NULL, digest TEXT NOT NULL
  )''',
  '''CREATE TABLE sync_uploads (
    packet_id TEXT PRIMARY KEY NOT NULL, payload TEXT NOT NULL
  )''',
];
