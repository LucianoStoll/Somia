import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_router.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../domain/entities/dashboard_summary.dart';
import 'dashboard_overview.dart' show SummaryPanel;
import 'dashboard_palette.dart';

String _money(int value, String code) => MoneyMinor.display(value, code)
    .replaceAllMapped(RegExp(r'\d{1,3}(?=(\d{3})+,)'), (m) => '${m[0]}.');

/// Keeps analytical spending separate from cash payments and invoice debt.
class SummaryInsights extends StatelessWidget {
  const SummaryInsights(
      {super.key,
      required this.currency,
      required this.month,
      this.referenceDate});
  final DashboardCurrencySummary currency;
  final DateTime month;
  final DateTime? referenceDate;

  @override
  Widget build(BuildContext context) {
    final c = currency;
    final d = c.balanceDetails;
    final categories = c.expensesByCategory
        .where((e) => e.amountMinor > 0)
        .toList()
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    final total = categories.fold<int>(0, (sum, e) => sum + e.amountMinor);
    final bills = c.upcoming
        .where((e) => e.kind == 'expense' || e.kind == 'invoice')
        .toList();
    final now = referenceDate ?? DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final end = DateTime.utc(month.year, month.month + 1);
    final groups = <String, List<DashboardDue>>{
      'Vencidas': [],
      'Hoje e próximos 7 dias': [],
      'Mais adiante': [],
    };
    for (final bill in bills) {
      final date = DateTime.utc(bill.date.year, bill.date.month, bill.date.day);
      if (!date.isBefore(end)) continue;
      final days = date.difference(today).inDays;
      groups[days < 0
              ? 'Vencidas'
              : days <= 7
                  ? 'Hoje e próximos 7 dias'
                  : 'Mais adiante']!
          .add(bill);
    }
    Widget row(String label, int value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(label),
                Text(_money(value, c.currencyCode),
                    style: TextStyle(color: color, fontWeight: FontWeight.w600))
              ]),
        );
    final cash = SummaryPanel(
        title: 'Composição do caixa',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (d == null)
            const Text('Composição indisponível.')
          else ...[
            row('Saldo inicial', d.openingMinor),
            row('Receitas recebidas', d.incomeMinor, color: SomiaColors.green),
            row('Despesas pagas', d.expenseMinor, color: SomiaColors.red),
            row('Pagamentos de cartões', d.cardPaymentsMinor,
                color: SomiaColors.red),
            row('Transferências recebidas', d.transferInMinor),
            row('Transferências enviadas', d.transferOutMinor),
            const Divider(),
            row('Saldo consolidado', c.currentBalanceMinor,
                color: SomiaColors.blue),
            row('Saldo previsto no fim do mês', c.projectedBalanceMinor),
          ],
          const Text(
              'Caixa das contas incluídas no saldo. Compras no cartão entram no caixa pelo pagamento.',
              style: TextStyle(color: SomiaColors.muted, fontSize: 12)),
        ]));
    final due = SummaryPanel(
        title: 'Situação dos compromissos',
        action: TextButton(
            onPressed: () => context.go(AppRoutes.expensesPath),
            child: const Text('Ver despesas')),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
              'Despesas e faturas em aberto com vencimento até o fim do mês selecionado, incluindo atrasos anteriores.',
              style: TextStyle(color: SomiaColors.muted, fontSize: 12)),
          const SizedBox(height: 8),
          for (final group in groups.entries)
            row('${group.key} · ${group.value.length}',
                group.value.fold<int>(0, (sum, e) => sum + e.amountMinor),
                color: group.key == 'Vencidas' ? SomiaColors.red : null),
          const Divider(),
          row(
              'Total em aberto',
              groups.values
                  .expand((e) => e)
                  .fold<int>(0, (sum, e) => sum + e.amountMinor)),
          const Text('Faixas de vencimento calculadas em relação a hoje.',
              style: TextStyle(color: SomiaColors.muted, fontSize: 12)),
        ]));
    final ranking = SummaryPanel(
        title: 'Ranking de despesas',
        action: TextButton(
            onPressed: () => context.go(AppRoutes.analysisPath),
            child: const Text('Ver análises')),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Efetivadas e previstas por categoria · mês selecionado',
              style: TextStyle(color: SomiaColors.muted, fontSize: 12)),
          if (categories.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Sem categorias com despesas neste mês.')),
          for (final category in categories.take(6)) ...[
            const SizedBox(height: 14),
            Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text(category.name),
                  Text(
                      '${_money(category.amountMinor, c.currencyCode)} · ${(category.amountMinor * 100 / total).toStringAsFixed(1).replaceAll('.', ',')}%')
                ]),
            const SizedBox(height: 7),
            LinearProgressIndicator(
                value: category.amountMinor / total,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
                color: SomiaColors.blue,
                backgroundColor: SomiaColors.outline),
          ],
          const SizedBox(height: 12),
          row('Total por categorias', total),
          if (categories.length > 6)
            const Text(
                'As 6 maiores estão acima. Consulte as demais em Análises.',
                style: TextStyle(color: SomiaColors.muted, fontSize: 12)),
        ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, box) {
        if (box.maxWidth >= 900 &&
            MediaQuery.textScalerOf(context).scale(16) < 24) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: due),
            const SizedBox(width: 16),
            Expanded(child: cash)
          ]);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [due, const SizedBox(height: 12), cash]);
      }),
      const SizedBox(height: 12),
      ranking,
    ]);
  }
}
