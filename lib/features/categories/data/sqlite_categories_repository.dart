import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/entity_metadata.dart';
import '../domain/categories_repository.dart';
import '../domain/category.dart';

class SqliteCategoriesRepository implements CategoriesRepository {
  const SqliteCategoriesRepository(this._db);
  final AppDatabase _db;

  @override
  Future<List<FinanceCategory>> list() async {
    final rows = await _db.customSelect('''
      SELECT id, name, type, parent_id, is_archived, icon_key, color_argb
      FROM categories WHERE deleted_at IS NULL
      ORDER BY type, parent_id IS NOT NULL, lower(name), id
    ''').get();
    return rows.map(_map).toList();
  }

  @override
  Future<FinanceCategory> create(CategoryDraft draft) async {
    await _validate(draft);
    final id = EntityMetadata.newId();
    final now = EntityMetadata.nowUtcMillis();
    await _db.customStatement('''
      INSERT INTO categories
        (id, name, type, parent_id, icon_key, color_argb, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      id,
      draft.name.trim(),
      draft.type.name,
      draft.parentId,
      draft.iconKey,
      draft.colorArgb,
      now,
      now
    ]);
    return _find(id);
  }

  @override
  Future<FinanceCategory> update(String id, CategoryDraft draft) async {
    final original = await _find(id);
    if (original.type != draft.type) {
      final used = await _db.customSelect(
        '''SELECT 1 FROM transactions t,json_each(t.allocations_json) p WHERE json_extract(p.value,'\$.categoryId')=?
        UNION ALL SELECT 1 FROM card_entries e,json_each(e.allocations_json) p WHERE json_extract(p.value,'\$.categoryId')=? LIMIT 1''',
        variables: [Variable.withString(id), Variable.withString(id)],
      ).get();
      if (used.isNotEmpty) {
        throw StateError('Preserve o tipo da categoria usada em rateios.');
      }
    }
    await _validate(draft, id: id);
    await _db.customStatement('''
      UPDATE categories SET name = ?, type = ?, parent_id = ?, icon_key = ?,
        color_argb = ?, updated_at = ?, sync_version = sync_version + 1
      WHERE id = ? AND deleted_at IS NULL
    ''', [
      draft.name.trim(),
      draft.type.name,
      draft.parentId,
      draft.iconKey,
      draft.colorArgb,
      EntityMetadata.nowUtcMillis(),
      id
    ]);
    return _find(id);
  }

  @override
  Future<FinanceCategory> setArchived(String id,
      {required bool archived}) async {
    final category = await _find(id);
    if (!archived && category.parentId != null) {
      final parent = await _find(category.parentId!);
      if (parent.isArchived) {
        throw StateError('Reative primeiro a categoria principal.');
      }
    }
    // Filhas arquivadas junto da principal; reativar a principal não reativa
    // filhas automaticamente, preservando a escolha anterior de cada uma.
    await _db.transaction(() async {
      final now = EntityMetadata.nowUtcMillis();
      await _db.customStatement('''
        UPDATE categories SET is_archived = ?, updated_at = ?,
          sync_version = sync_version + 1
        WHERE id = ? AND deleted_at IS NULL
      ''', [archived ? 1 : 0, now, id]);
      if (archived && category.parentId == null) {
        await _db.customStatement('''
          UPDATE categories SET is_archived = 1, updated_at = ?,
            sync_version = sync_version + 1
          WHERE parent_id = ? AND deleted_at IS NULL AND is_archived = 0
        ''', [now, id]);
      }
    });
    return _find(id);
  }

  Future<void> _validate(CategoryDraft draft, {String? id}) async {
    if (draft.name.trim().isEmpty) {
      throw const FormatException('Informe o nome da categoria.');
    }
    if (draft.parentId == null) return;
    if (draft.parentId == id) {
      throw StateError('Uma categoria não pode ser filha dela mesma.');
    }
    final parent = await _find(draft.parentId!);
    if (parent.isSubcategory ||
        parent.isArchived ||
        parent.type != draft.type) {
      throw StateError('Escolha uma categoria principal ativa do mesmo tipo.');
    }
    if (id != null) {
      final children = await list();
      if (children.any((child) => child.parentId == id)) {
        throw StateError(
            'Uma categoria com subcategorias não pode virar subcategoria.');
      }
    }
  }

  Future<FinanceCategory> _find(String id) async {
    final rows = await _db.customSelect('''
      SELECT id, name, type, parent_id, is_archived, icon_key, color_argb
      FROM categories WHERE id = ? AND deleted_at IS NULL
    ''', variables: [Variable.withString(id)]).get();
    if (rows.isEmpty) throw StateError('Categoria não encontrada.');
    return _map(rows.single);
  }

  FinanceCategory _map(QueryRow row) => FinanceCategory(
        id: row.read<String>('id'),
        name: row.read<String>('name'),
        type: CategoryType.values.byName(row.read<String>('type')),
        parentId: row.readNullable<String>('parent_id'),
        isArchived: row.read<int>('is_archived') == 1,
        iconKey: row.readNullable<String>('icon_key'),
        colorArgb: row.readNullable<int>('color_argb'),
      );
}
