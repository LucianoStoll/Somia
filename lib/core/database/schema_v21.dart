final schemaV21 = <String>[
  "ALTER TABLE transactions ADD COLUMN establishment TEXT NOT NULL DEFAULT '' CHECK(length(establishment)<=100)",
  "ALTER TABLE card_entries ADD COLUMN establishment TEXT NOT NULL DEFAULT '' CHECK(length(establishment)<=100)",
  for (final table in ['sync_versions', 'sync_outbox', 'sync_history'])
    "UPDATE $table SET data=json_set(data,'\$.establishment','') WHERE table_name IN ('transactions','card_entries') AND data IS NOT NULL",
];
