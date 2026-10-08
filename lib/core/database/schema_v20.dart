const schemaV20 = <String>[
  "ALTER TABLE transactions ADD COLUMN tags_json TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(tags_json) AND json_type(tags_json)='array')",
  "ALTER TABLE card_entries ADD COLUMN tags_json TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(tags_json) AND json_type(tags_json)='array')",
];
