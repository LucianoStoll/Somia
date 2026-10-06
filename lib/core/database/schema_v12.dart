/// Atomic allocation payloads travel with the parent entity in backup/sync.
const schemaV12 = <String>[
  "ALTER TABLE transactions ADD COLUMN allocations_json TEXT NOT NULL DEFAULT '[]'",
  "ALTER TABLE card_entries ADD COLUMN allocations_json TEXT NOT NULL DEFAULT '[]'",
  for (final table in ['sync_versions', 'sync_outbox', 'sync_history'])
    "UPDATE $table SET data=json_set(data,'\$.allocations_json','[]') WHERE table_name IN ('transactions','card_entries') AND data IS NOT NULL",
];
