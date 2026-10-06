import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'category_allocation.dart';

Future<void> validateAllocationReferences(
  AppDatabase db,
  List<CategoryAllocation> parts,
  String type, {
  Set<String> historicalIds = const {},
}) async {
  for (final part in parts) {
    final row = await db.customSelect(
      '''SELECT c.type,c.is_archived,c.deleted_at,
      p.is_archived AS parent_archived,p.deleted_at AS parent_deleted
      FROM categories c LEFT JOIN categories p ON p.id=c.parent_id WHERE c.id=?''',
      variables: [Variable.withString(part.categoryId)],
    ).get();
    if (row.isEmpty ||
        row.single.read<String>('type') != type ||
        row.single.readNullable<int>('deleted_at') != null ||
        (!historicalIds.contains(part.categoryId) &&
            (row.single.read<int>('is_archived') == 1 ||
                row.single.readNullable<int>('parent_archived') == 1 ||
                row.single.readNullable<int>('parent_deleted') != null))) {
      throw StateError(
        'Selecione categorias ativas do mesmo tipo para o rateio.',
      );
    }
  }
}
