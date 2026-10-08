import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/entity_metadata.dart';
import '../../../core/database/reimbursement_integrity.dart';
import '../domain/reimbursement.dart';

class ReimbursementsRepository {
  const ReimbursementsRepository(this.db);
  final AppDatabase db;
  static int day(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch;
  Future<List<QueryRow>> _rows(String sql, [List<Object> args = const []]) => db
      .customSelect(sql,
          variables: args
              .map((a) => a is int
                  ? Variable.withInt(a)
                  : Variable.withString(a as String))
              .toList())
      .get();
  Future<List<Person>> people() async => (await _rows(
          'SELECT * FROM people WHERE deleted_at IS NULL ORDER BY lower(name),id'))
      .map((r) => Person(r.read<String>('id'), r.read<String>('name'),
          r.read<String>('aliases'), r.read<int>('is_archived') == 1))
      .toList();
  Future<String> savePerson(String name, {String? id, String aliases = ''}) =>
      db.transaction(() async {
        if (name.trim().isEmpty) {
          throw const FormatException('Informe o nome da pessoa.');
        }
        final now = EntityMetadata.nowUtcMillis(),
            key = id ?? EntityMetadata.newId();
        if (id == null) {
          await db.customStatement(
              'INSERT INTO people(id,name,aliases,created_at,updated_at) VALUES(?,?,?,?,?)',
              [key, name.trim(), aliases.trim(), now, now]);
        } else {
          if ((await _rows(
                  'SELECT id FROM people WHERE id=? AND deleted_at IS NULL',
                  [id]))
              .isEmpty) {
            throw StateError('Pessoa não encontrada.');
          }
          await db.customStatement(
              'UPDATE people SET name=?,aliases=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [name.trim(), aliases.trim(), now, id]);
        }
        return key;
      });
  Future<void> archivePerson(Person p) => db.customStatement(
      'UPDATE people SET is_archived=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
      [p.archived ? 0 : 1, EntityMetadata.nowUtcMillis(), p.id]);
  Future<void> mergePeople(String from, String into) =>
      db.transaction(() async {
        final all = await people();
        if (from == into ||
            !all.any((p) => p.id == from) ||
            !all.any((p) => p.id == into && !p.archived)) {
          throw const FormatException(
              'Escolha duas pessoas diferentes, com destino ativo.');
        }
        final source = all.singleWhere((p) => p.id == from),
            target = all.singleWhere((p) => p.id == into);
        final now = EntityMetadata.nowUtcMillis();
        await db.customStatement(
            'UPDATE reimbursements SET person_id=?,updated_at=?,sync_version=sync_version+1 WHERE person_id=?',
            [into, now, from]);
        await savePerson(target.name,
            id: into,
            aliases: [target.aliases, source.name, source.aliases]
                .where((s) => s.isNotEmpty)
                .join('; '));
        await db.customStatement(
            'UPDATE people SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
            [now, now, from]);
        await validateReimbursements(db);
      });
  Future<String> sourceForMovement(String movement) async {
    if (!movement.startsWith('card:')) {
      return movement;
    }
    final rows = await _rows('SELECT purchase_id FROM card_entries WHERE id=?',
        [movement.substring(5)]);
    if (rows.isEmpty) {
      throw StateError('Compra não encontrada.');
    }
    return 'purchase:${rows.single.read<String>('purchase_id')}';
  }

  Future<List<ReimbursementDraft>> drafts(String movement) async {
    final source = await sourceForMovement(movement);
    final card = source.startsWith('purchase:');
    return (await _rows(
            'SELECT * FROM reimbursements WHERE ${card ? 'purchase_id' : 'transaction_id'}=? AND deleted_at IS NULL',
            [
          card ? source.substring(9) : source
        ]))
        .map((r) => ReimbursementDraft(
            r.read<String>('person_id'), r.read<int>('amount_minor'),
            id: r.read<String>('id')))
        .toList();
  }

  Future<void> replace(String source, List<ReimbursementDraft> drafts) =>
      db.transaction(() async {
        final card = source.startsWith('purchase:'),
            key = source.startsWith('purchase:') ? source.substring(9) : source;
        final field = card ? 'purchase_id' : 'transaction_id';
        final old = await _rows(
            'SELECT * FROM reimbursements WHERE $field=? AND deleted_at IS NULL',
            [key]);
        if (drafts.where((d) => d.id != null).map((d) => d.id).toSet().length !=
            drafts.where((d) => d.id != null).length) {
          throw const FormatException(
              'Reembolso repetido. Atualize o lançamento.');
        }
        final persons = await people(), now = EntityMetadata.nowUtcMillis();
        for (final d in drafts) {
          if (d.amountMinor <= 0 ||
              d.amountMinor > 9000000000000000 ||
              !persons.any((p) =>
                  p.id == d.personId &&
                  (!p.archived ||
                      old.any((r) =>
                          r.read<String>('person_id') == p.id &&
                          r.read<String>('id') == d.id)))) {
            throw const FormatException(
                'Selecione pessoa ativa e valor maior que zero.');
          }
          if (d.id != null) {
            if (!old.any((r) => r.read<String>('id') == d.id)) {
              throw StateError('O reembolso mudou. Atualize o lançamento.');
            }
            final prior = old.singleWhere((r) => r.read<String>('id') == d.id);
            if (prior.read<String>('person_id') != d.personId &&
                (await _rows(
                        'SELECT id FROM reimbursement_receipts WHERE reimbursement_id=? AND deleted_at IS NULL',
                        [d.id!]))
                    .isNotEmpty) {
              throw const FormatException(
                  'Desvincule recebimentos antes de trocar a pessoa.');
            }
            await db.customStatement(
                'UPDATE reimbursements SET person_id=?,amount_minor=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
                [d.personId, d.amountMinor, now, d.id]);
          } else {
            await db.customStatement(
                'INSERT INTO reimbursements(id,person_id,transaction_id,purchase_id,amount_minor,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',
                [
                  EntityMetadata.newId(),
                  d.personId,
                  card ? null : key,
                  card ? key : null,
                  d.amountMinor,
                  now,
                  now
                ]);
          }
        }
        for (final r in old) {
          if (!drafts.any((d) => d.id == r.read<String>('id'))) {
            await db.customStatement(
                'UPDATE reimbursements SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
                [now, now, r.read<String>('id')]);
          }
        }
        await validateReimbursements(db);
      });
  Future<List<Reimbursement>> load({String? personId}) async {
    final rows = await _rows(
        '''SELECT r.*,p.name AS person_name,COALESCE(t.description,
      (SELECT e.description FROM card_entries e WHERE e.purchase_id=r.purchase_id LIMIT 1)) AS description,
      COALESCE(a.currency_code,'BRL') AS currency FROM reimbursements r JOIN people p ON p.id=r.person_id
      LEFT JOIN transactions t ON t.id=r.transaction_id LEFT JOIN accounts a ON a.id=t.account_id
      WHERE r.deleted_at IS NULL ${personId == null ? '' : 'AND r.person_id=?'} ORDER BY r.created_at DESC,r.id''',
        [if (personId != null) personId]);
    final end = day(DateTime.now().add(const Duration(days: 1))),
        result = <Reimbursement>[];
    for (final r in rows) {
      final receipts = await _rows(
          '''SELECT l.id,l.transaction_id,t.description,e.planned_amount_minor,e.effective_at,
        COALESCE(e.effective_at,e.due_at) AS date,e.deleted_at FROM reimbursement_receipts l JOIN transactions t ON t.id=l.transaction_id
        JOIN transaction_events e ON (e.id=t.id OR e.id IN (SELECT 'settlement:'||s.id FROM transaction_settlements s WHERE s.transaction_id=t.id))
        WHERE l.reimbursement_id=? AND l.deleted_at IS NULL ORDER BY date DESC,l.id''',
          [r.read<String>('id')]);
      result.add(Reimbursement(
          r.read<String>('id'),
          r.read<String>('person_id'),
          r.read<String>('person_name'),
          r.read<String>('description'),
          r.read<String>('currency'),
          r.read<int>('amount_minor'),
          receipts
              .map((l) => ReimbursementReceipt(
                  l.read<String>('id'),
                  l.read<String>('transaction_id'),
                  l.read<String>('description'),
                  l.read<int>('planned_amount_minor'),
                  DateTime.fromMillisecondsSinceEpoch(l.read<int>('date'),
                      isUtc: true),
                  l.readNullable<int>('effective_at') != null &&
                      l.read<int>('effective_at') < end,
                  l.readNullable<int>('deleted_at') != null))
              .toList()));
    }
    return result;
  }

  Future<void> link(String reimbursement, String income) =>
      db.transaction(() async {
        final source = await _rows(
            'SELECT id FROM reimbursements WHERE id=? AND deleted_at IS NULL',
            [reimbursement]);
        final tx = await _rows(
            "SELECT id FROM transactions WHERE id=? AND type='income' AND deleted_at IS NULL",
            [income]);
        if (source.isEmpty || tx.isEmpty) {
          throw const FormatException(
              'Selecione um reembolso e uma receita existentes.');
        }
        if ((await _rows(
                'SELECT id FROM reimbursement_receipts WHERE transaction_id=? AND deleted_at IS NULL',
                [income]))
            .isNotEmpty) {
          throw const FormatException('Esta receita já está vinculada.');
        }
        final now = EntityMetadata.nowUtcMillis();
        await db.customStatement(
            'INSERT INTO reimbursement_receipts(id,reimbursement_id,transaction_id,created_at,updated_at) VALUES(?,?,?,?,?)',
            [EntityMetadata.newId(), reimbursement, income, now, now]);
        await validateReimbursements(db);
      });
  Future<void> unlink(String id) => db.customStatement(
      'UPDATE reimbursement_receipts SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
      [EntityMetadata.nowUtcMillis(), EntityMetadata.nowUtcMillis(), id]);
  Future<List<QueryRow>> eligibleIncome(Reimbursement r) => _rows(
      '''SELECT t.id,t.description,t.planned_amount_minor,t.effective_at FROM transactions t JOIN accounts a ON a.id=t.account_id
    WHERE t.type='income' AND t.deleted_at IS NULL AND a.currency_code=? AND t.planned_amount_minor<=?
    AND NOT EXISTS(SELECT 1 FROM reimbursement_receipts l WHERE l.transaction_id=t.id AND l.deleted_at IS NULL)
    ORDER BY t.due_at DESC,t.id''', [r.currency, r.available]);
  Future<void> receive(Reimbursement r,
          {required int amount,
          required String accountId,
          required DateTime date,
          String? categoryId,
          bool effective = true}) =>
      db.transaction(() async {
        if (amount <= 0 ||
            amount > 9000000000000000 ||
            date.year < 2000 ||
            date.year > 2100) {
          throw const FormatException('Confira valor e data do recebimento.');
        }
        if ((await _rows(
                'SELECT id FROM accounts WHERE id=? AND currency_code=? AND is_archived=0 AND deleted_at IS NULL',
                [accountId, r.currency]))
            .isEmpty) {
          throw const FormatException(
              'Selecione uma conta ativa na moeda do reembolso.');
        }
        if (categoryId != null &&
            (await _rows(
                    "SELECT id FROM categories WHERE id=? AND type='income' AND is_archived=0 AND deleted_at IS NULL",
                    [categoryId]))
                .isEmpty) {
          throw const FormatException(
              'Selecione uma categoria de receita ativa.');
        }
        final now = EntityMetadata.nowUtcMillis(),
            id = EntityMetadata.newId(),
            at = day(date);
        await db.customStatement(
            '''INSERT INTO transactions(id,description,type,planned_amount_minor,actual_amount_minor,competence_at,posted_at,due_at,effective_at,account_id,category_id,created_at,updated_at)
      VALUES(?,?,'income',?,?,?,?,?,?,?,?,?,?)''',
            [
              id,
              'Reembolso · ${r.personName} · ${r.description}',
              amount,
              effective ? amount : null,
              at,
              day(DateTime.now()),
              at,
              effective ? at : null,
              accountId,
              categoryId,
              now,
              now
            ]);
        await link(r.id, id);
      });
}
