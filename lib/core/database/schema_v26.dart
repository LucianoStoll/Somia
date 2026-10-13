const _legacyAttachmentOwner =
    "(owner_table='transactions' AND EXISTS(SELECT 1 FROM transactions WHERE id=local_attachments.owner_id)) OR (owner_table='transfers' AND EXISTS(SELECT 1 FROM transfers WHERE id=local_attachments.owner_id)) OR (owner_table='card_entries' AND EXISTS(SELECT 1 FROM card_entries WHERE id=local_attachments.owner_id))";

const schemaV26 = <String>[
  '''CREATE TABLE attachment_blobs (
    id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=64),
    size INTEGER NOT NULL CHECK(size>0 AND size<=20971520),
    content BLOB NOT NULL CHECK(length(content)=size),
    needs_refresh INTEGER NOT NULL DEFAULT 0 CHECK(needs_refresh IN (0,1)))''',
  """CREATE TABLE attachment_manifest (
    id TEXT PRIMARY KEY NOT NULL,
    owner_table TEXT NOT NULL CHECK(owner_table IN ('transactions','transfers','card_entries')),
    owner_id TEXT NOT NULL, name TEXT NOT NULL,
    size INTEGER NOT NULL CHECK(size>0 AND size<=20971520),
    sha256 TEXT NOT NULL CHECK(length(sha256)=64), created_at INTEGER NOT NULL)""",
  'CREATE INDEX attachment_manifest_owner ON attachment_manifest(owner_table,owner_id)',
  'INSERT OR IGNORE INTO attachment_blobs(id,size,content) SELECT sha256,size,content FROM local_attachments WHERE $_legacyAttachmentOwner',
  'INSERT INTO attachment_manifest SELECT id,owner_table,owner_id,name,size,sha256,created_at FROM local_attachments WHERE $_legacyAttachmentOwner',
  'DELETE FROM local_attachments WHERE $_legacyAttachmentOwner',
];
