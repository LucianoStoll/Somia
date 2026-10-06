import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/entity_metadata.dart';
import 'movement_series.dart';

/// Metadados ficam junto às ocorrências; os backups SQLite preservam a série.
class SeriesStore {
  const SeriesStore(this.db, this.table);
  final AppDatabase db;
  final String table;

  static SeriesInfo? info(QueryRow row) {
    final id = row.readNullable<String>('series_id');
    if (id == null) return null;
    return SeriesInfo(
        id: id,
        index: row.read<int>('series_index'),
        plan: SeriesPlan(
            kind: SeriesKind.values.byName(row.read<String>('series_kind')),
            count: row.read<int>('series_count'),
            unit: SeriesUnit.values.byName(row.read<String>('series_unit')),
            interval: row.read<int>('series_interval')));
  }

  Future<String> create(SeriesPlan plan, int amount,
          Future<String> Function(int index, int amount) insert) =>
      db.transaction(() async {
        final amounts = plan.amounts(amount);
        final seriesId = EntityMetadata.newId();
        String? first;
        for (var i = 0; i < plan.count; i++) {
          final id = await insert(i, amounts[i]);
          first ??= id;
          await db.customStatement(
              '''UPDATE $table SET series_id = ?, series_index = ?,
        series_kind = ?, series_count = ?, series_unit = ?, series_interval = ? WHERE id = ?''',
              [
                seriesId,
                i,
                plan.kind.name,
                plan.count,
                plan.unit.name,
                plan.interval,
                id
              ]);
        }
        return first!;
      });

  Future<QueryRow> row(String id) async {
    final rows = await db.customSelect(
        'SELECT * FROM $table WHERE id = ? AND deleted_at IS NULL',
        variables: [Variable.withString(id)]).get();
    if (rows.isEmpty) throw StateError('Lançamento não encontrado.');
    return rows.single;
  }

  Future<List<QueryRow>> targets(String id, SeriesScope scope) async {
    final original = await row(id);
    final series = info(original);
    if (scope == SeriesScope.onlyThis || series == null) return [original];
    // Preserva inclusive efetivações agendadas: nenhuma data confirmada é removida.
    return db.customSelect('''SELECT * FROM $table WHERE series_id = ?
      AND series_index >= ? AND deleted_at IS NULL AND effective_at IS NULL
      ORDER BY series_index''', variables: [
      Variable.withString(series.id),
      Variable.withInt(series.index)
    ]).get();
  }

  Future<void> delete(String id, SeriesScope scope) => db.transaction(() async {
        final rows = await targets(id, scope);
        final now = EntityMetadata.nowUtcMillis();
        for (final row in rows) {
          await db.customStatement(
              '''UPDATE $table SET deleted_at = ?, updated_at = ?,
        sync_version = sync_version + 1 WHERE id = ? AND deleted_at IS NULL''',
              [now, now, row.read<String>('id')]);
        }
      });

  /// Quando a data não mudou, mantém exceções individuais e o dia original.
  static DateTime shiftedDate(
      QueryRow target, QueryRow original, String column, DateTime edited) {
    final originalDate = DateTime.fromMillisecondsSinceEpoch(
        original.read<int>(column),
        isUtc: true);
    if (originalDate.year == edited.year &&
        originalDate.month == edited.month &&
        originalDate.day == edited.day) {
      return DateTime.fromMillisecondsSinceEpoch(target.read<int>(column),
          isUtc: true);
    }
    final series = info(original)!;
    return series.plan
        .dateAt(edited, target.read<int>('series_index') - series.index);
  }
}
