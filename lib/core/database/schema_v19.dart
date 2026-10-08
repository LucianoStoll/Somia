const schemaV19 = <String>[
  """CREATE TABLE transaction_settlements (
    id TEXT PRIMARY KEY NOT NULL, transaction_id TEXT NOT NULL REFERENCES transactions(id),
    account_id TEXT NOT NULL REFERENCES accounts(id),
    amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor BETWEEN 1 AND 9000000000000000),
    effective_at INTEGER NOT NULL,
    allocations_json TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(allocations_json)),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
    device_id TEXT, sync_version INTEGER NOT NULL DEFAULT 0 CHECK(sync_version>=0))""",
  'CREATE INDEX settlements_transaction ON transaction_settlements(transaction_id)',
  r"""CREATE VIEW transaction_events AS
    SELECT t.id,t.description,t.type,
      t.planned_amount_minor-COALESCE((SELECT SUM(s.amount_minor) FROM transaction_settlements s WHERE s.transaction_id=t.id AND s.deleted_at IS NULL),0) AS planned_amount_minor,
      t.actual_amount_minor,t.competence_at,t.posted_at,t.due_at,t.effective_at,t.account_id,t.category_id,
      t.ignore_balance,t.ignore_analytics,t.created_at,t.updated_at,t.deleted_at,
      CASE WHEN EXISTS(SELECT 1 FROM transaction_settlements s WHERE s.transaction_id=t.id AND s.deleted_at IS NULL)
      THEN (SELECT json_group_array(json_object('categoryId',json_extract(p.value,'$.categoryId'),'amountMinor',
        json_extract(p.value,'$.amountMinor')-COALESCE((SELECT SUM(json_extract(q.value,'$.amountMinor'))
          FROM transaction_settlements s,json_each(s.allocations_json) q
          WHERE s.transaction_id=t.id AND s.deleted_at IS NULL AND json_extract(q.value,'$.categoryId')=json_extract(p.value,'$.categoryId')),0)))
        FROM json_each(t.allocations_json) p)
      ELSE t.allocations_json END AS allocations_json
    FROM transactions t
    WHERE t.planned_amount_minor>COALESCE((SELECT SUM(s.amount_minor) FROM transaction_settlements s WHERE s.transaction_id=t.id AND s.deleted_at IS NULL),0)
    UNION ALL
    SELECT 'settlement:'||s.id,t.description,t.type,s.amount_minor,s.amount_minor,
      s.effective_at,s.created_at,s.effective_at,s.effective_at,s.account_id,t.category_id,
      t.ignore_balance,t.ignore_analytics,s.created_at,s.updated_at,
      COALESCE(t.deleted_at,s.deleted_at),s.allocations_json
    FROM transaction_settlements s JOIN transactions t ON t.id=s.transaction_id""",
];
