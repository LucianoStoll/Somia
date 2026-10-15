const schemaV14 = <String>[
  '''CREATE TABLE assets (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL CHECK(length(trim(name))>0),
    kind TEXT NOT NULL CHECK(kind IN ('vehicle','property','other')),
    acquired_at INTEGER NOT NULL CHECK(typeof(acquired_at)='integer' AND acquired_at>=-2208988800000 AND acquired_at<4133980800000),
    acquisition_minor INTEGER NOT NULL CHECK(typeof(acquisition_minor)='integer' AND acquisition_minor BETWEEN 0 AND 9000000000000000),
    notes TEXT NOT NULL DEFAULT '',
    is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN (0,1)),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,
    device_id TEXT,
    sync_version INTEGER NOT NULL DEFAULT 0 CHECK(sync_version>=0)
  )''',
  '''CREATE TABLE asset_valuations (
    id TEXT NOT NULL PRIMARY KEY,
    asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE RESTRICT,
    assessed_at INTEGER NOT NULL CHECK(typeof(assessed_at)='integer' AND assessed_at>=-2208988800000 AND assessed_at<4133980800000),
    value_minor INTEGER NOT NULL CHECK(typeof(value_minor)='integer' AND value_minor BETWEEN 0 AND 9000000000000000),
    debt_minor INTEGER NOT NULL CHECK(typeof(debt_minor)='integer' AND debt_minor BETWEEN 0 AND 9000000000000000),
    creditor TEXT NOT NULL DEFAULT '',
    notes TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,
    device_id TEXT,
    sync_version INTEGER NOT NULL DEFAULT 0 CHECK(sync_version>=0)
  )''',
  'CREATE INDEX asset_valuations_date ON asset_valuations(asset_id,assessed_at,created_at,id)',
];
