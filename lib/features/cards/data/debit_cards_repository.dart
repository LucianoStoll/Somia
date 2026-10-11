import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/entity_metadata.dart';

class DebitCard {
  const DebitCard(
      {required this.id,
      required this.name,
      required this.accountId,
      this.institutionId,
      this.colorArgb,
      this.archived = false});
  final String id, name, accountId;
  final String? institutionId;
  final int? colorArgb;
  final bool archived;
}

class DebitCardsRepository {
  const DebitCardsRepository(this.db);
  final AppDatabase db;
  Future<List<DebitCard>> list() async => (await db
          .customSelect(
              'SELECT * FROM debit_cards WHERE deleted_at IS NULL ORDER BY is_archived,name,id')
          .get())
      .map((r) => DebitCard(
          id: r.read<String>('id'),
          name: r.read<String>('name'),
          accountId: r.read<String>('account_id'),
          institutionId: r.readNullable<String>('institution_id'),
          colorArgb: r.readNullable<int>('color_argb'),
          archived: r.read<int>('is_archived') == 1))
      .toList();

  Future<String> save(
          {String? id,
          required String name,
          required String accountId,
          String? institutionId,
          int? colorArgb}) =>
      db.transaction(() async {
        if (name.trim().isEmpty)
          throw const FormatException('Informe o nome do cartão.');
        if (colorArgb != null && (colorArgb < 0 || colorArgb > 0xffffffff))
          throw const FormatException('Cor inválida.');
        final accounts = await db.customSelect(
            "SELECT id FROM accounts WHERE id=? AND deleted_at IS NULL AND is_archived=0 AND currency_code='BRL'",
            variables: [Variable.withString(accountId)]).get();
        if (accounts.isEmpty)
          throw StateError('Selecione uma conta ativa em BRL.');
        final key = id ?? EntityMetadata.newId(),
            now = EntityMetadata.nowUtcMillis();
        if (id == null) {
          await db.customStatement(
              'INSERT INTO debit_cards(id,name,account_id,institution_id,color_argb,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',
              [
                key,
                name.trim(),
                accountId,
                institutionId,
                colorArgb,
                now,
                now
              ]);
        } else {
          await _existing(id);
          await db.customStatement(
              'UPDATE debit_cards SET name=?,account_id=?,institution_id=?,color_argb=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [name.trim(), accountId, institutionId, colorArgb, now, key]);
        }
        return key;
      });
  Future<void> _existing(String id) async {
    final rows = await db.customSelect(
        'SELECT id FROM debit_cards WHERE id=? AND deleted_at IS NULL',
        variables: [Variable.withString(id)]).get();
    if (rows.isEmpty) throw StateError('Cartão não encontrado.');
  }

  Future<void> archive(String id, bool value) => db.transaction(() async {
        await _existing(id);
        await db.customStatement(
            'UPDATE debit_cards SET is_archived=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
            [value ? 1 : 0, EntityMetadata.nowUtcMillis(), id]);
      });
  Future<void> delete(String id) => db.transaction(() async {
        await _existing(id);
        final now = EntityMetadata.nowUtcMillis();
        await db.customStatement(
            'UPDATE debit_cards SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
            [now, now, id]);
        // Links and their account transactions survive as historical facts.
      });
  Future<void> link(String transactionId, String? cardId, String accountId,
      {bool preserve = false}) async {
    final now = EntityMetadata.nowUtcMillis();
    if (cardId == null) {
      await db.customStatement(
          'UPDATE debit_card_links SET deleted_at=?,updated_at=?,sync_version=sync_version+1 WHERE id=? AND deleted_at IS NULL',
          [now, now, transactionId]);
      return;
    }
    final cards = await db.customSelect('SELECT * FROM debit_cards WHERE id=?',
        variables: [Variable.withString(cardId)]).get();
    if (cards.isEmpty) throw StateError('Cartão não encontrado.');
    final card = cards.single;
    if (!preserve &&
        (card.readNullable<int>('deleted_at') != null ||
            card.read<int>('is_archived') == 1 ||
            card.read<String>('account_id') != accountId)) {
      throw StateError(
          'Selecione um cartão de débito ativo da conta escolhida.');
    }
    await db.customStatement(
        '''INSERT INTO debit_card_links(id,card_id,created_at,updated_at) VALUES(?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET card_id=excluded.card_id,deleted_at=NULL,updated_at=excluded.updated_at,sync_version=debit_card_links.sync_version+1''',
        [transactionId, cardId, now, now]);
  }
}
