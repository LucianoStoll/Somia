/// Cartões são passivos próprios. Liquidações são caixa, nunca uma segunda despesa.
const schemaV10 = <String>[
  '''CREATE TABLE credit_cards (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL CHECK(length(trim(name)) > 0),
    institution_id TEXT,
    payment_account_id TEXT NOT NULL REFERENCES accounts(id),
    limit_minor INTEGER CHECK(limit_minor IS NULL OR limit_minor >= 0),
    closing_day INTEGER NOT NULL CHECK(closing_day BETWEEN 1 AND 31),
    due_day INTEGER NOT NULL CHECK(due_day BETWEEN 1 AND 31),
    is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN (0,1)),
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    deleted_at INTEGER, sync_version INTEGER NOT NULL DEFAULT 0
  )''',
  '''CREATE TABLE card_limit_history (
    id TEXT PRIMARY KEY NOT NULL, card_id TEXT NOT NULL REFERENCES credit_cards(id),
    limit_minor INTEGER, changed_at INTEGER NOT NULL
  )''',
  '''CREATE TABLE card_invoices (
    id TEXT PRIMARY KEY NOT NULL, card_id TEXT NOT NULL REFERENCES credit_cards(id),
    month_at INTEGER NOT NULL, closing_at INTEGER NOT NULL, due_at INTEGER NOT NULL,
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 0,
    UNIQUE(card_id, month_at), CHECK(closing_at <= due_at)
  )''',
  '''CREATE TABLE card_entries (
    id TEXT PRIMARY KEY NOT NULL, card_id TEXT NOT NULL REFERENCES credit_cards(id),
    invoice_id TEXT NOT NULL REFERENCES card_invoices(id),
    purchase_id TEXT NOT NULL, installment_index INTEGER NOT NULL DEFAULT 0,
    installment_count INTEGER NOT NULL DEFAULT 1,
    description TEXT NOT NULL CHECK(length(trim(description)) > 0),
    category_id TEXT REFERENCES categories(id),
    kind TEXT NOT NULL CHECK(kind IN ('purchase','opening','refund','fee','discount')),
    amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor) = 'integer' AND amount_minor <> 0),
    posted_at INTEGER NOT NULL,
    source_id TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    deleted_at INTEGER, sync_version INTEGER NOT NULL DEFAULT 0,
    CHECK(installment_index >= 0 AND installment_index < installment_count)
  )''',
  '''CREATE TABLE card_payments (
    id TEXT PRIMARY KEY NOT NULL, invoice_id TEXT NOT NULL REFERENCES card_invoices(id),
    account_id TEXT NOT NULL REFERENCES accounts(id),
    amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor) = 'integer' AND amount_minor > 0),
    effective_at INTEGER NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    deleted_at INTEGER, sync_version INTEGER NOT NULL DEFAULT 0
  )''',
  '''CREATE TABLE card_entry_history (
    id TEXT PRIMARY KEY NOT NULL, entry_id TEXT NOT NULL REFERENCES card_entries(id),
    action TEXT NOT NULL, previous_invoice_id TEXT REFERENCES card_invoices(id),
    invoice_id TEXT REFERENCES card_invoices(id), previous_amount_minor INTEGER,
    amount_minor INTEGER, changed_at INTEGER NOT NULL
  )''',
  'CREATE INDEX idx_card_entries_invoice ON card_entries(invoice_id, deleted_at)',
  'CREATE INDEX idx_card_entries_purchase ON card_entries(purchase_id, installment_index)',
  'CREATE INDEX idx_card_payments_account_date ON card_payments(account_id, effective_at)',
  'CREATE INDEX idx_card_invoices_card_month ON card_invoices(card_id, month_at)',
];
