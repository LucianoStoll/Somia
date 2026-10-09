final schemaV23 = <String>[
  """CREATE TABLE local_attachments (
    id TEXT PRIMARY KEY, owner_table TEXT NOT NULL CHECK(owner_table IN ('transactions','transfers','card_entries')),
    owner_id TEXT NOT NULL, name TEXT NOT NULL, size INTEGER NOT NULL CHECK(size > 0 AND size <= 20971520),
    sha256 TEXT NOT NULL, content BLOB NOT NULL, created_at INTEGER NOT NULL,
    CHECK(length(content)=size)
  )""",
  'CREATE INDEX local_attachments_owner ON local_attachments(owner_table,owner_id)',
];
