/// Debit cards keep the existing transaction ledger; payment coverage and
/// cashback have their own identities for backup and synchronization.
const schemaV25 = <String>[
  '''CREATE TABLE debit_cards (
    id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL CHECK(length(trim(name))>0),
    account_id TEXT NOT NULL REFERENCES accounts(id), institution_id TEXT,
    color_argb INTEGER, is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN (0,1)),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    deleted_at INTEGER, sync_version INTEGER NOT NULL DEFAULT 0
  )''',
  '''CREATE TABLE debit_card_links (
    id TEXT PRIMARY KEY NOT NULL REFERENCES transactions(id),
    card_id TEXT NOT NULL REFERENCES debit_cards(id),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    deleted_at INTEGER, sync_version INTEGER NOT NULL DEFAULT 0
  )''',
  '''CREATE TABLE card_payment_allocations (
    id TEXT PRIMARY KEY NOT NULL,
    payment_id TEXT NOT NULL REFERENCES card_payments(id),
    entry_id TEXT NOT NULL REFERENCES card_entries(id),
    amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor>0),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    deleted_at INTEGER, sync_version INTEGER NOT NULL DEFAULT 0,
    UNIQUE(payment_id,entry_id)
  )''',
  '''CREATE TABLE cashback_rules (
    id TEXT PRIMARY KEY NOT NULL, card_kind TEXT NOT NULL CHECK(card_kind IN ('credit','debit')),
    card_id TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1)),
    account_id TEXT NOT NULL REFERENCES accounts(id),
    category_id TEXT REFERENCES categories(id), return_category_id TEXT REFERENCES categories(id),
    rule_json TEXT NOT NULL CHECK(json_valid(rule_json)),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    deleted_at INTEGER, sync_version INTEGER NOT NULL DEFAULT 0,
    UNIQUE(card_kind,card_id)
  )''',
  '''CREATE TABLE cashback_claims (
    id TEXT PRIMARY KEY NOT NULL, rule_id TEXT NOT NULL REFERENCES cashback_rules(id),
    purchase_id TEXT NOT NULL, first_payment_at INTEGER NOT NULL,
    rule_json TEXT NOT NULL CHECK(json_valid(rule_json)),
    confirmed_theory_minor INTEGER NOT NULL DEFAULT 0,
    accepted_difference_minor INTEGER NOT NULL DEFAULT 0,
    accepted_base_minor INTEGER NOT NULL DEFAULT 0,
    confirmed_rate INTEGER NOT NULL DEFAULT 0 CHECK(confirmed_rate BETWEEN 0 AND 10000),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    deleted_at INTEGER, sync_version INTEGER NOT NULL DEFAULT 0,
    UNIQUE(rule_id,purchase_id)
  )''',
  '''CREATE TABLE cashback_receipts (
    id TEXT PRIMARY KEY NOT NULL REFERENCES transactions(id),
    claim_id TEXT NOT NULL REFERENCES cashback_claims(id),
    kind TEXT NOT NULL CHECK(kind IN ('original','complement','return')),
    theory_minor INTEGER NOT NULL, base_minor INTEGER NOT NULL,
    reason TEXT NOT NULL DEFAULT 'forecast', confirmation_json TEXT CHECK(confirmation_json IS NULL OR json_valid(confirmation_json)),
    rate INTEGER NOT NULL CHECK(rate BETWEEN 0 AND 10000),
    confirmed INTEGER NOT NULL DEFAULT 0 CHECK(confirmed IN (0,1,2)),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    deleted_at INTEGER, sync_version INTEGER NOT NULL DEFAULT 0
  )''',
  'CREATE INDEX idx_debit_card_links_card ON debit_card_links(card_id)',
  'CREATE INDEX idx_card_payment_allocations_entry ON card_payment_allocations(entry_id)',
  'CREATE UNIQUE INDEX idx_cashback_pending ON cashback_receipts(claim_id) WHERE confirmed=0 AND deleted_at IS NULL',
];
