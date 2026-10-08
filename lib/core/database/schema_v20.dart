final schemaV20 = <String>[
  "ALTER TABLE transactions ADD COLUMN tags_json TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(tags_json) AND json_type(tags_json)='array')",
  "ALTER TABLE card_entries ADD COLUMN tags_json TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(tags_json) AND json_type(tags_json)='array')",
  for (final table in ['sync_versions', 'sync_outbox', 'sync_history'])
    "UPDATE $table SET data=json_set(data,'\$.tags_json','[]') WHERE table_name IN ('transactions','card_entries') AND data IS NOT NULL",
];
