import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/entity_metadata.dart';
import '../../../core/database/financial_data.dart';
import '../../../core/series/movement_series.dart';
import '../../cards/data/cards_repository.dart';
import '../../transfers/data/sqlite_transfers_repository.dart';
import '../../transfers/domain/transfer.dart';
import '../domain/financial_transaction.dart';
import '../domain/movement_management.dart';
import '../domain/transaction_tags.dart';
import 'sqlite_transactions_repository.dart';

/// Each selection is applied atomically and only to the selected occurrences.
class MovementManagementRepository {
  const MovementManagementRepository(this.db);
  final AppDatabase db;

  Future<List<({String id, String label})>> accountOptions() async => (await db
          .customSelect(
              'SELECT id,name,currency_code FROM accounts WHERE deleted_at IS NULL AND is_archived=0 ORDER BY name')
          .get())
      .map((row) => (
            id: row.read<String>('id'),
            label:
                '${row.read<String>('name')} · ${row.read<String>('currency_code')}'
          ))
      .toList();
  Future<List<({String id, String label})>> categoryOptions() async => (await db
          .customSelect(
              'SELECT id,name,type FROM categories WHERE deleted_at IS NULL AND is_archived=0 ORDER BY type,name')
          .get())
      .map((row) => (
            id: row.read<String>('id'),
            label:
                '${row.read<String>('name')} · ${row.read<String>('type') == 'income' ? 'Receita' : 'Despesa'}'
          ))
      .toList();

  Future<QueryRow> _check(MovementReference ref, String state) async {
    final rows = await db.customSelect('SELECT * FROM ${ref.table} WHERE id=?',
        variables: [Variable.withString(ref.id)]).get();
    if (rows.isEmpty) throw StateError('O lançamento não existe mais.');
    final row = rows.single;
    final revision =
        '${row.read<int>('updated_at')}:${row.read<int>('sync_version')}';
    if (revision != ref.revision ||
        row.read<String>('trash_state') != state ||
        (state == 'active' && row.readNullable<int>('deleted_at') != null)) {
      throw StateError(
          'A seleção mudou. Atualize a lista e selecione novamente.');
    }
    return row;
  }

  Future<void> apply(
          List<MovementReference> selection, BulkMovementPatch patch) =>
      db.transaction(() async {
        if (selection.isEmpty || patch.isEmpty) {
          throw StateError('Selecione lançamentos e pelo menos um campo.');
        }
        final refs = {for (final ref in selection) ref.key: ref}.values;
        // Validate every revision before mutating any row.
        for (final ref in refs) {
          await _check(ref, 'active');
        }
        final transactions = SqliteTransactionsRepository(db);
        final transfers = SqliteTransfersRepository(db);
        final transactionItems =
            refs.any((ref) => ref.kind == MovementKind.transaction)
                ? {for (final item in await transactions.list()) item.id: item}
                : <String, FinancialTransaction>{};
        final transferItems =
            refs.any((ref) => ref.kind == MovementKind.transfer)
                ? {for (final item in await transfers.list()) item.id: item}
                : <String, Transfer>{};
        for (final ref in refs) {
          if (ref.kind == MovementKind.transfer) {
            if (patch.changeCategory ||
                patch.establishment != null ||
                patch.addTags.isNotEmpty ||
                patch.removeTags.isNotEmpty) {
              throw StateError(
                  'Transferências não possuem categoria, tags ou estabelecimento.');
            }
            final item = transferItems[ref.id]!;
            await _currency(item.currencyCode, patch.accountId);
            await _currency(item.currencyCode, patch.destinationAccountId);
            await transfers.update(
                item.id,
                TransferDraft(
                    description: patch.description ?? item.description,
                    sourceAccountId: patch.accountId ?? item.sourceAccountId,
                    destinationAccountId:
                        patch.destinationAccountId ?? item.destinationAccountId,
                    amountMinor: patch.amountMinor ?? item.amountMinor,
                    date: patch.postedDate ?? item.date,
                    dueDate: patch.dueDate ?? item.dueDate,
                    isEffective:
                        patch.effective ?? (item.effectiveDate != null),
                    effectiveDate: patch.effective == true
                        ? patch.effectiveDate ?? DateTime.now()
                        : item.effectiveDate));
          } else {
            final originalRow = await _check(ref, 'active');
            if (patch.destinationAccountId != null) {
              throw StateError(
                  'Conta de destino é exclusiva de transferências.');
            }
            final item = ref.kind == MovementKind.cardEntry
                ? await CardsRepository(db).findMovement(ref.id)
                : transactionItems[ref.id]!;
            if (patch.effective != null && item.settlementCount > 0) {
              throw const FormatException(
                  'Desfaça as baixas pelo histórico antes de alterar a efetivação em lote.');
            }
            if (patch.changeCategory && item.allocations.isNotEmpty) {
              throw StateError(
                  'Edite o rateio individualmente antes de trocar a categoria.');
            }
            if (ref.kind == MovementKind.cardEntry &&
                (patch.accountId != null ||
                    patch.effective != null ||
                    patch.dueDate != null ||
                    patch.postedDate != null)) {
              throw StateError(
                  'A conta, as datas e a efetivação das compras são gerenciadas pela fatura.');
            }
            await _currency(item.currencyCode, patch.accountId);
            final remove = patch.removeTags.map(TransactionTags.key).toSet();
            final tags = TransactionTags.normalize([
              ...item.tags
                  .where((tag) => !remove.contains(TransactionTags.key(tag))),
              ...patch.addTags,
            ]);
            await transactions.update(
                item.id,
                TransactionDraft(
                    description: patch.description ?? item.description,
                    type: item.type,
                    amountMinor: patch.amountMinor ?? item.amountMinor,
                    date: patch.postedDate ?? item.date,
                    dueDate: patch.dueDate ?? item.dueDate,
                    isEffective:
                        patch.effective ?? (item.effectiveDate != null),
                    effectiveDate: patch.effective == true
                        ? patch.effectiveDate ?? DateTime.now()
                        : item.effectiveDate,
                    accountId: patch.accountId ?? item.accountId,
                    cardId: item.cardId,
                    cardInvoiceMonth: item.cardInvoiceMonth,
                    categoryId: patch.changeCategory
                        ? patch.categoryId
                        : item.categoryId,
                    allocations: item.allocations,
                    tags: tags,
                    establishment: patch.establishment ?? item.establishment));
            if (ref.kind == MovementKind.transaction) {
              final fields = <String>[];
              final args = <Object?>[];
              if (patch.amountMinor == null &&
                  patch.effective == null &&
                  originalRow.readNullable<int>('actual_amount_minor') !=
                      (item.effectiveDate == null ? null : item.amountMinor)) {
                fields.add('actual_amount_minor=?');
                args.add(originalRow.readNullable<int>('actual_amount_minor'));
              }
              if (patch.postedDate == null &&
                  originalRow.read<int>('competence_at') !=
                      originalRow.read<int>('posted_at')) {
                fields.add('competence_at=?');
                args.add(originalRow.read<int>('competence_at'));
              }
              if (fields.isNotEmpty) {
                await db.customStatement(
                    'UPDATE transactions SET ${fields.join(',')} WHERE id=?',
                    [...args, ref.id]);
              }
            }
          }
        }
        await _validate();
      });

  Future<void> _currency(String currency, String? accountId) async {
    if (accountId == null) return;
    final rows = await db.customSelect(
        'SELECT currency_code FROM accounts WHERE id=? AND deleted_at IS NULL AND is_archived=0',
        variables: [Variable.withString(accountId)]).get();
    if (rows.isEmpty || rows.single.read<String>('currency_code') != currency) {
      throw StateError(
          'Escolha uma conta ativa com a mesma moeda dos lançamentos.');
    }
  }

  Future<void> trash(List<MovementReference> selection) =>
      db.transaction(() async {
        final refs = {for (final ref in selection) ref.key: ref}.values;
        for (final ref in refs) {
          await _check(ref, 'active');
        }
        for (final ref in refs) {
          switch (ref.kind) {
            case MovementKind.transaction:
              await SqliteTransactionsRepository(db).delete(ref.id);
            case MovementKind.transfer:
              await SqliteTransfersRepository(db).delete(ref.id);
            case MovementKind.cardEntry:
              final cards = CardsRepository(db);
              final entry = await cards.entry(ref.id);
              if (entry.kind == 'purchase') {
                await cards.deletePurchase(ref.id, SeriesScope.onlyThis);
              } else {
                await cards.removeAdjustment(ref.id);
              }
          }
        }
        await _validate();
      });

  Future<List<TrashedMovement>> listTrash() async {
    final result = <TrashedMovement>[];
    for (final kind in MovementKind.values) {
      final table = MovementReference(kind, '', '').table;
      final rows = await db
          .customSelect(
              'SELECT * FROM $table WHERE trash_state=\'trashed\' AND deleted_at IS NOT NULL')
          .get();
      for (final row in rows) {
        String currency = 'BRL', label = 'Compra / ajuste de cartão';
        if (kind != MovementKind.cardEntry) {
          final accountId = row.read<String>(kind == MovementKind.transaction
              ? 'account_id'
              : 'source_account_id');
          final account = await db.customSelect(
              'SELECT name,currency_code FROM accounts WHERE id=?',
              variables: [Variable.withString(accountId)]).getSingle();
          currency = account.read<String>('currency_code');
          label =
              '${kind == MovementKind.transfer ? 'Transferência' : row.read<String>('type') == 'income' ? 'Receita' : 'Despesa'} · ${account.read<String>('name')}';
        }
        result.add(TrashedMovement(
            ref: MovementReference(kind, row.read<String>('id'),
                '${row.read<int>('updated_at')}:${row.read<int>('sync_version')}'),
            description: row.read<String>('description'),
            amountMinor: row.read<int>(kind == MovementKind.transaction
                ? 'planned_amount_minor'
                : 'amount_minor'),
            currencyCode: currency,
            contextLabel: label,
            deletedAt: DateTime.fromMillisecondsSinceEpoch(
                row.read<int>('deleted_at'))));
      }
    }
    result.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return result;
  }

  Future<void> restore(List<MovementReference> selection) =>
      _changeTrash(selection, restore: true);
  Future<void> purge(List<MovementReference> selection) =>
      _changeTrash(selection, restore: false);
  Future<void> _changeTrash(List<MovementReference> selection,
          {required bool restore}) =>
      db.transaction(() async {
        final refs = {for (final ref in selection) ref.key: ref}.values;
        for (final ref in refs) {
          await _check(ref, 'trashed');
        }
        final now = EntityMetadata.nowUtcMillis();
        for (final ref in refs) {
          if (restore) {
            final row = await _check(ref, 'trashed');
            final links = switch (ref.kind) {
              MovementKind.transaction => {
                  'accounts': [row.read<String>('account_id')]
                },
              MovementKind.transfer => {
                  'accounts': [
                    row.read<String>('source_account_id'),
                    row.read<String>('destination_account_id')
                  ]
                },
              MovementKind.cardEntry => {
                  'credit_cards': [row.read<String>('card_id')],
                  'card_invoices': [row.read<String>('invoice_id')]
                },
            };
            for (final link in links.entries) {
              for (final id in link.value) {
                final live = await db.customSelect(
                    "SELECT id FROM ${link.key} WHERE id=? ${link.key == 'card_invoices' ? '' : 'AND deleted_at IS NULL'}",
                    variables: [Variable.withString(id)]).get();
                if (live.isEmpty) {
                  throw StateError(
                      'Restaure a conta ou o cartão vinculado antes deste lançamento.');
                }
              }
            }
          }
          if (ref.kind == MovementKind.cardEntry) {
            final row = await _check(ref, 'trashed');
            await db.customStatement(
                'INSERT INTO card_entry_history(id,entry_id,action,previous_invoice_id,invoice_id,previous_amount_minor,amount_minor,changed_at) VALUES(?,?,?,?,?,?,?,?)',
                [
                  EntityMetadata.newId(),
                  ref.id,
                  restore ? 'restore' : 'purge',
                  row.read<String>('invoice_id'),
                  row.read<String>('invoice_id'),
                  row.read<int>('amount_minor'),
                  restore ? row.read<int>('amount_minor') : 0,
                  now
                ]);
          }
          await db.customStatement(
              'UPDATE ${ref.table} SET trash_state=?,deleted_at=${restore ? 'NULL' : 'deleted_at'},updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [restore ? 'active' : 'purged', now, ref.id]);
          if (!restore) {
            await db.customStatement(
                'DELETE FROM local_attachments WHERE owner_table=? AND owner_id=?',
                [ref.table, ref.id]);
          }
        }
        await _validate();
      });

  Future<void> _validate() async {
    await validateFinancial(db);
    final invalid = await db.customSelect('''SELECT source_id FROM card_entries
      WHERE kind='refund' AND deleted_at IS NULL GROUP BY source_id
      HAVING SUM(-amount_minor) > COALESCE((SELECT SUM(p.amount_minor) FROM card_entries p
        WHERE p.purchase_id=card_entries.source_id AND p.kind='purchase' AND p.deleted_at IS NULL),0) LIMIT 1''').get();
    if (invalid.isNotEmpty) {
      throw StateError('O estorno excederia o valor das compras ativas.');
    }
  }
}
