const schemaV26 = <String>[
  '''CREATE TABLE attachment_blobs (
    sha256 TEXT PRIMARY KEY NOT NULL CHECK(length(sha256)=64),
    size INTEGER NOT NULL CHECK(size>0 AND size<=20971520),
    content BLOB NOT NULL CHECK(length(content)=size))''',
  """CREATE TABLE attachment_manifest (
    id TEXT PRIMARY KEY NOT NULL,
    owner_table TEXT NOT NULL CHECK(owner_table IN ('transactions','transfers','card_entries')),
    owner_id TEXT NOT NULL, name TEXT NOT NULL,
    size INTEGER NOT NULL CHECK(size>0 AND size<=20971520),
    sha256 TEXT NOT NULL CHECK(length(sha256)=64), created_at INTEGER NOT NULL)""",
  'CREATE INDEX attachment_manifest_owner ON attachment_manifest(owner_table,owner_id)',
  'INSERT OR IGNORE INTO attachment_blobs SELECT sha256,size,content FROM local_attachments',
  'INSERT INTO attachment_manifest SELECT id,owner_table,owner_id,name,size,sha256,created_at FROM local_attachments',
  'DELETE FROM local_attachments',
];
