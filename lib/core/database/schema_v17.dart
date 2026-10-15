const schemaV17 = <String>[
  '''CREATE TABLE people (
    id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL CHECK(length(trim(name))>0),
    aliases TEXT NOT NULL DEFAULT '', is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN (0,1)),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
    device_id TEXT, sync_version INTEGER NOT NULL DEFAULT 0 CHECK(sync_version>=0))''',
  '''CREATE TABLE reimbursements (
    id TEXT PRIMARY KEY NOT NULL, person_id TEXT NOT NULL REFERENCES people(id),
    transaction_id TEXT REFERENCES transactions(id), purchase_id TEXT,
    amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor BETWEEN 1 AND 9000000000000000),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
    device_id TEXT, sync_version INTEGER NOT NULL DEFAULT 0 CHECK(sync_version>=0),
    CHECK((transaction_id IS NULL)<>(purchase_id IS NULL)))''',
  '''CREATE TABLE reimbursement_receipts (
    id TEXT PRIMARY KEY NOT NULL, reimbursement_id TEXT NOT NULL REFERENCES reimbursements(id),
    transaction_id TEXT NOT NULL REFERENCES transactions(id),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
    device_id TEXT, sync_version INTEGER NOT NULL DEFAULT 0 CHECK(sync_version>=0))''',
  'CREATE UNIQUE INDEX reimbursement_income_unique ON reimbursement_receipts(transaction_id) WHERE deleted_at IS NULL',
];
