const schemaV18 = <String>[
  '''CREATE TABLE budget_limits (
    id TEXT PRIMARY KEY NOT NULL, category_id TEXT NOT NULL REFERENCES categories(id),
    month_at INTEGER NOT NULL, currency_code TEXT NOT NULL CHECK(length(currency_code)=3),
    amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor BETWEEN 1 AND 9000000000000000),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
    device_id TEXT, sync_version INTEGER NOT NULL DEFAULT 0 CHECK(sync_version>=0))''',
  'CREATE UNIQUE INDEX budget_month_category ON budget_limits(month_at,currency_code,category_id) WHERE deleted_at IS NULL',
  '''CREATE TABLE planning_goals (
    id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL CHECK(length(trim(name))>0),
    kind TEXT NOT NULL CHECK(kind IN ('goal','reserve')), currency_code TEXT NOT NULL CHECK(length(currency_code)=3),
    target_minor INTEGER NOT NULL CHECK(typeof(target_minor)='integer' AND target_minor BETWEEN 0 AND 9000000000000000),
    target_at INTEGER, reserve_months INTEGER NOT NULL DEFAULT 6 CHECK(reserve_months BETWEEN 1 AND 36),
    essential_json TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(essential_json) AND json_type(essential_json)='array'),
    is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN (0,1)),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
    device_id TEXT, sync_version INTEGER NOT NULL DEFAULT 0 CHECK(sync_version>=0))''',
  '''CREATE TABLE goal_accounts (
    id TEXT PRIMARY KEY NOT NULL, goal_id TEXT NOT NULL REFERENCES planning_goals(id), account_id TEXT NOT NULL REFERENCES accounts(id),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
    device_id TEXT, sync_version INTEGER NOT NULL DEFAULT 0 CHECK(sync_version>=0))''',
  'CREATE UNIQUE INDEX goal_account_pair ON goal_accounts(goal_id,account_id) WHERE deleted_at IS NULL',
];
