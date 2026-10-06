/// Aplicações usam o saldo da conta vinculada, nunca um segundo saldo.
const schemaV13 = <String>[
  '''CREATE TABLE investments (
    id TEXT NOT NULL PRIMARY KEY,
    account_id TEXT NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE RESTRICT,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    kind TEXT NOT NULL CHECK (kind IN ('cdb', 'cdi', 'savings')),
    institution TEXT NOT NULL DEFAULT '',
    notes TEXT NOT NULL DEFAULT '',
    maturity_at INTEGER CHECK (maturity_at IS NULL OR
      (typeof(maturity_at)='integer' AND maturity_at >= -2208988800000
        AND maturity_at < 4133980800000)),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,
    device_id TEXT,
    sync_version INTEGER NOT NULL DEFAULT 0 CHECK (sync_version >= 0)
  )''',
];
