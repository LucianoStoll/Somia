const schemaV15 = <String>[
  '''CREATE TABLE debts (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL CHECK(length(trim(name))>0),
    creditor TEXT NOT NULL CHECK(length(trim(creditor))>0),
    kind TEXT NOT NULL CHECK(kind IN ('loan','financing','other')),
    balance_minor INTEGER NOT NULL CHECK(typeof(balance_minor)='integer' AND balance_minor BETWEEN 0 AND 9000000000000000),
    reference_at INTEGER NOT NULL CHECK(typeof(reference_at)='integer' AND reference_at>=-2208988800000 AND reference_at<4133980800000),
    asset_id TEXT REFERENCES assets(id) ON DELETE RESTRICT,
    notes TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,
    device_id TEXT,
    sync_version INTEGER NOT NULL DEFAULT 0 CHECK(sync_version>=0)
  )''',
  'CREATE UNIQUE INDEX debt_asset_unique ON debts(asset_id) WHERE deleted_at IS NULL AND asset_id IS NOT NULL',
  '''CREATE TABLE debt_payments (
    id TEXT NOT NULL PRIMARY KEY,
    debt_id TEXT NOT NULL REFERENCES debts(id) ON DELETE RESTRICT,
    transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE RESTRICT,
    principal_minor INTEGER NOT NULL CHECK(typeof(principal_minor)='integer' AND principal_minor BETWEEN 0 AND 9000000000000000),
    linked_amount_minor INTEGER NOT NULL CHECK(typeof(linked_amount_minor)='integer' AND linked_amount_minor>0 AND principal_minor<=linked_amount_minor),
    linked_description TEXT NOT NULL CHECK(length(trim(linked_description))>0),
    linked_at INTEGER NOT NULL CHECK(typeof(linked_at)='integer'),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,
    device_id TEXT,
    sync_version INTEGER NOT NULL DEFAULT 0 CHECK(sync_version>=0)
  )''',
  'CREATE UNIQUE INDEX debt_transaction_unique ON debt_payments(transaction_id) WHERE deleted_at IS NULL',
  'CREATE INDEX debt_payments_debt ON debt_payments(debt_id)',
];
