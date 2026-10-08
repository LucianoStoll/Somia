import 'dart:convert';
import 'app_database.dart';

Future<void> validatePlanning(AppDatabase db) async {
  final invalid = await db.customSelect('''
    SELECT 1 FROM budget_limits b JOIN categories c ON c.id=b.category_id WHERE b.deleted_at IS NULL AND (c.type<>'expense' OR c.deleted_at IS NOT NULL OR
      strftime('%d',b.month_at/1000,'unixepoch')<>'01' OR b.month_at % 86400000<>0 OR b.month_at<946684800000 OR b.month_at>4131302400000)
    UNION ALL SELECT 1 FROM budget_limits b JOIN categories c ON c.id=b.category_id JOIN budget_limits p ON p.category_id=c.parent_id
      WHERE b.deleted_at IS NULL AND p.deleted_at IS NULL AND b.month_at=p.month_at AND b.currency_code=p.currency_code
    UNION ALL SELECT 1 FROM goal_accounts l JOIN planning_goals g ON g.id=l.goal_id JOIN accounts a ON a.id=l.account_id
      WHERE l.deleted_at IS NULL AND g.deleted_at IS NULL AND (a.deleted_at IS NOT NULL OR a.currency_code<>g.currency_code)
    UNION ALL SELECT 1 FROM goal_accounts l JOIN planning_goals g ON g.id=l.goal_id WHERE l.deleted_at IS NULL AND g.deleted_at IS NULL AND g.is_archived=0
      AND (SELECT COUNT(*) FROM goal_accounts x JOIN planning_goals p ON p.id=x.goal_id WHERE x.account_id=l.account_id AND x.deleted_at IS NULL AND p.deleted_at IS NULL AND p.is_archived=0)>1
    UNION ALL SELECT 1 FROM planning_goals WHERE deleted_at IS NULL AND (kind='goal' AND target_minor<=0 OR target_at IS NOT NULL AND (target_at<946684800000 OR target_at>4133980800000 OR target_at % 86400000<>0)) LIMIT 1
  ''').get();
  if (invalid.isNotEmpty) {
    throw const FormatException(
        'Planejamento incompatível: confira categoria, mês, moeda e contas. Uma conta só pode financiar uma meta ativa.');
  }
  final categories = await db
      .customSelect('SELECT id,type,parent_id,deleted_at FROM categories')
      .get();
  final byId = {for (final c in categories) c.read<String>('id'): c};
  for (final g in await db
      .customSelect(
          'SELECT essential_json,kind FROM planning_goals WHERE deleted_at IS NULL')
      .get()) {
    final ids = jsonDecode(g.read<String>('essential_json')) as List;
    if (ids.any((id) =>
            id is! String ||
            !byId.containsKey(id) ||
            byId[id]!.read<String>('type') != 'expense' ||
            byId[id]!.readNullable<int>('deleted_at') != null) ||
        ids.toSet().length != ids.length ||
        ids.any((id) =>
            ids.contains(byId[id]?.readNullable<String>('parent_id'))) ||
        (g.read<String>('kind') == 'reserve' && ids.isEmpty)) {
      throw const FormatException(
          'Selecione categorias essenciais de despesa sem repetir categoria e subcategoria.');
    }
  }
}
