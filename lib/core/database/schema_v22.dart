final schemaV22 = <String>[
  for (final table in ['transactions', 'transfers', 'card_entries'])
    "ALTER TABLE $table ADD COLUMN trash_state TEXT NOT NULL DEFAULT 'active' CHECK(trash_state IN ('active','trashed','purged') AND (trash_state='active' OR deleted_at IS NOT NULL))",
  for (final local in ['sync_versions', 'sync_outbox', 'sync_history'])
    "UPDATE $local SET data=json_set(data,'\$.trash_state','active') WHERE table_name IN ('transactions','transfers','card_entries') AND data IS NOT NULL",
];
