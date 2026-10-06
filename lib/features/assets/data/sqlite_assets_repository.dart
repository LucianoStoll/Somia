import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/entity_metadata.dart';
import '../../accounts/data/sqlite_accounts_repository.dart';
import '../../cards/data/cards_repository.dart';
import '../domain/asset.dart';

class SqliteAssetsRepository implements AssetsRepository {
  const SqliteAssetsRepository(this.db);
  final AppDatabase db;
  static int day(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch;
  static DateTime date(int n) =>
      DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
  void _money(int n) {
    if (n < 0 || n > 9000000000000000) {
      throw const FormatException(
          'Informe um valor entre zero e 90 trilhões de reais.');
    }
  }

  void _date(DateTime d) {
    if (d.year < 1900 || day(d) > day(DateTime.now())) {
      throw const FormatException('Informe uma data entre 1900 e hoje.');
    }
  }

  Future<QueryRow> _find(String id) =>
      db.customSelect('SELECT * FROM assets WHERE id=? AND deleted_at IS NULL',
          variables: [Variable(id)]).getSingle();
  Future<List<AssetValuation>> _history(String id) async =>
      (await db.customSelect(
              'SELECT * FROM asset_valuations WHERE asset_id=? AND deleted_at IS NULL ORDER BY assessed_at DESC,created_at DESC,id DESC',
              variables: [
            Variable(id)
          ]).get())
          .map((r) => AssetValuation(
              id: r.read<String>('id'),
              date: date(r.read<int>('assessed_at')),
              valueMinor: r.read<int>('value_minor'),
              debtMinor: r.read<int>('debt_minor'),
              creditor: r.read<String>('creditor'),
              notes: r.read<String>('notes')))
          .toList();
  @override
  Future<AssetOverview> load() => db.transaction(() async {
        final rows = await db
            .customSelect(
                'SELECT * FROM assets WHERE deleted_at IS NULL ORDER BY is_archived,lower(name),id')
            .get();
        final assets = <Asset>[];
        for (final r in rows) {
          assets.add(Asset(
              id: r.read<String>('id'),
              name: r.read<String>('name'),
              kind: AssetKind.values.byName(r.read<String>('kind')),
              acquiredAt: date(r.read<int>('acquired_at')),
              acquisitionMinor: r.read<int>('acquisition_minor'),
              notes: r.read<String>('notes'),
              archived: r.read<int>('is_archived') == 1,
              history: await _history(r.read<String>('id'))));
        }
        final accounts = await SqliteAccountsRepository(db).list();
        final cards = await CardsRepository(db).list();
        return AssetOverview(assets,
            accountsMinor: accounts
                .where((a) => a.currencyCode == 'BRL')
                .fold(0, (s, a) => s + a.currentBalanceMinor),
            cardDebtMinor: cards.fold(0, (s, c) => s + c.committedMinor),
            cardCreditMinor: cards.fold(0, (s, c) => s + c.creditMinor));
      });
  @override
  Future<String> save(AssetDraft draft,
          {String? id, AssetValuationDraft? initial}) =>
      db.transaction(() async {
        if (draft.name.trim().isEmpty) {
          throw const FormatException('Informe o nome do bem.');
        }
        _money(draft.acquisitionMinor);
        _date(draft.acquiredAt);
        final now = EntityMetadata.nowUtcMillis();
        if (id != null) {
          await _find(id);
          final history = await _history(id);
          if (history.any((v) => day(v.date) < day(draft.acquiredAt))) {
            throw const FormatException(
                'A aquisição não pode ser posterior às avaliações.');
          }
          if (initial != null) {
            throw const FormatException(
                'Use Atualizar avaliação para alterar valores atuais.');
          }
          await db.customStatement(
              'UPDATE assets SET name=?,kind=?,acquired_at=?,acquisition_minor=?,notes=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
              [
                draft.name.trim(),
                draft.kind.name,
                day(draft.acquiredAt),
                draft.acquisitionMinor,
                draft.notes.trim(),
                now,
                id
              ]);
          return id;
        }
        if (initial == null) {
          throw const FormatException('Informe a avaliação inicial.');
        }
        final assetId = EntityMetadata.newId();
        await db.customStatement(
            'INSERT INTO assets(id,name,kind,acquired_at,acquisition_minor,notes,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)',
            [
              assetId,
              draft.name.trim(),
              draft.kind.name,
              day(draft.acquiredAt),
              draft.acquisitionMinor,
              draft.notes.trim(),
              now,
              now
            ]);
        await assess(assetId, initial);
        return assetId;
      });
  @override
  Future<void> assess(String id, AssetValuationDraft draft,
          {String? expectedLatestId}) =>
      db.transaction(() async {
        final asset = await _find(id);
        _money(draft.valueMinor);
        _money(draft.debtMinor);
        _date(draft.date);
        if (day(draft.date) < asset.read<int>('acquired_at')) {
          throw const FormatException(
              'A avaliação não pode ser anterior à aquisição.');
        }
        if (draft.debtMinor > 0 && draft.creditor.trim().isEmpty) {
          throw const FormatException('Informe o credor do financiamento.');
        }
        final history = await _history(id);
        if (expectedLatestId != null &&
            history.firstOrNull?.id != expectedLatestId) {
          throw StateError(
              'A avaliação mudou. Atualize a tela antes de salvar.');
        }
        // Monotonic timestamp provides deterministic same-day ordering on one device.
        final rows = await db.customSelect(
            'SELECT MAX(created_at) AS n FROM asset_valuations WHERE asset_id=?',
            variables: [Variable(id)]).getSingle();
        final previous = rows.readNullable<int>('n') ?? 0;
        final clock = EntityMetadata.nowUtcMillis();
        final now = clock > previous ? clock : previous + 1;
        await db.customStatement(
            'INSERT INTO asset_valuations(id,asset_id,assessed_at,value_minor,debt_minor,creditor,notes,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)',
            [
              EntityMetadata.newId(),
              id,
              day(draft.date),
              draft.valueMinor,
              draft.debtMinor,
              draft.creditor.trim(),
              draft.notes.trim(),
              now,
              now
            ]);
      });
  @override
  Future<void> archive(String id, bool archived) => db.transaction(() async {
        await _find(id);
        await db.customStatement(
            'UPDATE assets SET is_archived=?,updated_at=?,sync_version=sync_version+1 WHERE id=?',
            [archived ? 1 : 0, EntityMetadata.nowUtcMillis(), id]);
      });
}
