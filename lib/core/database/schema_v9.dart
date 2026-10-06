/// Séries finitas; lançamentos antigos continuam independentes.
final schemaV9 = [
  for (final table in ['transactions', 'transfers']) ...[
    'ALTER TABLE $table ADD COLUMN series_id TEXT',
    'ALTER TABLE $table ADD COLUMN series_index INTEGER',
    'ALTER TABLE $table ADD COLUMN series_kind TEXT',
    'ALTER TABLE $table ADD COLUMN series_count INTEGER',
    'ALTER TABLE $table ADD COLUMN series_unit TEXT',
    'ALTER TABLE $table ADD COLUMN series_interval INTEGER',
    'CREATE INDEX ${table}_series_idx ON $table(series_id, series_index)',
  ],
];
