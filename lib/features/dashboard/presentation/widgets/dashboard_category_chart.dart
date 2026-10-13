import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../domain/entities/dashboard_summary.dart';

class DashboardCategoryChart extends StatelessWidget {
  const DashboardCategoryChart({super.key, required this.currency});
  final DashboardCurrencySummary currency;
  @override
  Widget build(BuildContext context) {
    final total = currency.expensesByCategory
        .fold<int>(0, (sum, c) => sum + c.amountMinor);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Inclui efetivados e previstos',
          style: TextStyle(color: SomiaColors.muted)),
      if (total == 0)
        const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Nenhuma despesa neste mês.')),
      for (final c in currency.expensesByCategory.take(5))
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(c.name),
                  const SizedBox(height: 4),
                  Text(
                      '${MoneyMinor.display(c.amountMinor, currency.currencyCode)} • ${(c.amountMinor * 100 / total).toStringAsFixed(1).replaceAll('.', ',')}%',
                      style: const TextStyle(color: SomiaColors.muted)),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                      value: c.amountMinor / total,
                      minHeight: 7,
                      borderRadius: BorderRadius.circular(4),
                      color: SomiaColors.blue)
                ])),
      Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed: () => context.go(AppRoutes.analysisPath),
              child: const Text('Ver todas'))),
    ]);
  }
}
