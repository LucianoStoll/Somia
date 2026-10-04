import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/financial_transaction.dart';

/// Uma fotografia do histórico ao abrir o formulário, sem dados de faturas
/// agrupadas ou ajustes. A primeira classificação válida vence.
class CategoryHistoryRepository {
  const CategoryHistoryRepository(this.db);
  final AppDatabase db;

  static String normalize(String description) =>
      description.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<List<HistorySuggestion>> suggestions(TransactionType type) async {
    final rows = await db.customSelect(
        '''SELECT h.*,c.id AS valid_category FROM (
      SELECT t.id,t.description,t.type,t.account_id,a.name AS account_name,a.currency_code,
        t.planned_amount_minor AS amount_minor,NULL AS card_id,t.category_id,t.updated_at,t.created_at
      FROM transactions t JOIN accounts a ON a.id=t.account_id
      WHERE t.deleted_at IS NULL AND a.deleted_at IS NULL AND a.is_archived=0
      UNION ALL
      SELECT e.id,e.description,'expense',k.payment_account_id,'Cartão ' || k.name,'BRL',
        e.amount_minor,e.card_id,e.category_id,e.updated_at,e.created_at
      FROM card_entries e JOIN credit_cards k ON k.id=e.card_id
      JOIN accounts a ON a.id=k.payment_account_id
      WHERE e.deleted_at IS NULL AND e.kind='purchase' AND k.deleted_at IS NULL AND k.is_archived=0
        AND a.deleted_at IS NULL AND a.is_archived=0
      ) h LEFT JOIN categories c ON c.id=h.category_id AND c.deleted_at IS NULL AND c.is_archived=0 AND c.type=h.type
        AND (c.parent_id IS NULL OR EXISTS (SELECT 1 FROM categories p WHERE p.id=c.parent_id AND p.parent_id IS NULL AND p.type=h.type AND p.deleted_at IS NULL AND p.is_archived=0))
      WHERE h.type=? ORDER BY h.updated_at DESC,h.created_at DESC,h.id DESC''',
        variables: [Variable.withString(type.name)]).get();
    final seen = <String>{};
    final result = <HistorySuggestion>[];
    for (final r in rows) {
      final card = r.readNullable<String>('card_id');
      final account = r.read<String>('account_id');
      final description = r.read<String>('description');
      final key = '${normalize(description)}|${card ?? account}';
      if (seen.add(key)) {
        result.add(HistorySuggestion(
            id: r.read<String>('id'),
            description: description,
            accountId: account,
            accountName: r.read<String>('account_name'),
            amountMinor: r.read<int>('amount_minor'),
            currencyCode: r.read<String>('currency_code'),
            cardId: card,
            categoryId: r.readNullable<String>('valid_category')));
      }
    }
    return result;
  }

  Future<Map<String, String>> load(TransactionType type) async {
    final rows = await db.customSelect('''
      SELECT h.description,c.id AS category_id FROM (
        SELECT id,description,type,category_id,updated_at,created_at
        FROM transactions WHERE deleted_at IS NULL AND category_id IS NOT NULL
        UNION ALL
        SELECT id,description,'expense' AS type,category_id,updated_at,created_at
        FROM card_entries WHERE deleted_at IS NULL AND kind='purchase' AND category_id IS NOT NULL
      ) h
      JOIN categories c ON c.id=h.category_id
      LEFT JOIN categories p ON p.id=c.parent_id
      WHERE h.type=? AND c.type=h.type AND c.deleted_at IS NULL AND c.is_archived=0
        AND (c.parent_id IS NULL OR
          (p.id IS NOT NULL AND p.parent_id IS NULL AND p.type=h.type AND p.deleted_at IS NULL AND p.is_archived=0))
      ORDER BY h.updated_at DESC,h.created_at DESC,h.id DESC
      ''', variables: [Variable.withString(type.name)]).get();
    final result = <String, String>{};
    for (final row in rows) {
      final text = normalize(row.read<String>('description'));
      if (text.isNotEmpty) {
        result.putIfAbsent(text, () => row.read<String>('category_id'));
      }
    }
    return result;
  }
}

class HistorySuggestion {
  const HistorySuggestion(
      {required this.id,
      required this.description,
      required this.accountId,
      required this.accountName,
      required this.amountMinor,
      required this.currencyCode,
      this.cardId,
      this.categoryId});
  final String id, description, accountId, accountName, currencyCode;
  final int amountMinor;
  final String? cardId, categoryId;
}
