import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/module_surface.dart';
import '../../../core/widgets/month_selector.dart';
import '../../accounts/domain/money_minor.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_visuals.dart';
import '../domain/planning.dart';

class PlanningComparisonPanel extends StatelessWidget {
  const PlanningComparisonPanel(
      {super.key,
      required this.month,
      required this.currency,
      required this.type,
      required this.categoryId,
      required this.current,
      required this.previous,
      required this.categories});
  final DateTime month;
  final String currency, type;
  final String? categoryId;
  final List<MonthlySpend> current, previous;
  final List<FinanceCategory> categories;

  String money(int value) => MoneyMinor.display(value, currency)
      .replaceAllMapped(RegExp(r'\d{1,3}(?=(\d{3})+,)'), (m) => '${m[0]}.');
  String signed(int value) => '${value > 0 ? '+' : ''}${money(value)}';
  String period(DateTime date) => '${monthNames[date.month - 1]} ${date.year}';

  @override
  Widget build(BuildContext context) {
    final comparison = PlanningCategoryComparison.fromSpending(
        current: current,
        previous: previous,
        categoryId: categoryId,
        currency: currency,
        type: type);
    final total = comparison.total;
    final percent = total.percent;
    final favorable =
        type == 'income' ? total.difference > 0 : total.difference < 0;
    final color = total.difference == 0
        ? SomiaColors.muted
        : favorable
            ? SomiaColors.green
            : SomiaColors.red;
    return Column(
        key: const ValueKey('planning-comparison'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          const Text('Comparação do previsto',
              style: TextStyle(fontWeight: FontWeight.w600)),
          ModuleValueRow(label: period(month), value: money(total.current)),
          ModuleValueRow(
              label: period(DateTime(month.year, month.month - 1)),
              value: money(total.previous)),
          Text(
              total.difference == 0
                  ? 'Sem variação'
                  : 'Variação: ${signed(total.difference)}',
              key: const ValueKey('planning-change'),
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
              percent == null
                  ? 'Sem base positiva no mês anterior para calcular o percentual.'
                  : '${percent > 0 ? '+' : ''}${percent.toStringAsFixed(1).replaceAll('.', ',')}% em relação ao mês anterior',
              style: const TextStyle(fontSize: 12, color: SomiaColors.muted)),
          if (comparison.changes.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Maiores mudanças',
                style: TextStyle(fontWeight: FontWeight.w600)),
            for (final change in comparison.changes.take(3))
              Builder(builder: (context) {
                final category = categories
                    .where((c) => c.id == change.categoryId)
                    .firstOrNull;
                final name = change.categoryId == categoryId
                    ? 'Sem subcategoria'
                    : category?.name ?? 'Subcategoria indisponível';
                return Padding(
                    key: ValueKey('planning-contribution-${change.categoryId}'),
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(name,
                              style: TextStyle(
                                  color: category == null
                                      ? SomiaColors.muted
                                      : categoryDisplayColor(category))),
                          Text(signed(change.difference),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                              '${money(change.previous)} → ${money(change.current)}',
                              style: const TextStyle(
                                  fontSize: 12, color: SomiaColors.muted)),
                        ]));
              }),
          ],
          const SizedBox(height: 8),
        ]);
  }
}
