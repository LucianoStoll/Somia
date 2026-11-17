import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_router.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../domain/entities/dashboard_summary.dart';
import 'dashboard_overview.dart' show SummaryPanel;
import '../../../../core/theme/app_theme.dart';

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
    final t = context.somia;
    String money(int value, [String sign = '']) =>
        '$sign${_money(value, c.currencyCode)}';
    Widget row(String label, String value,
            {Color? color, bool strong = false, Widget? leading}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 10)],
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              strong ? FontWeight.w700 : FontWeight.w400,
                          color: strong ? t.ink : t.muted)),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * .45),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(value,
                        style: TextStyle(
                            fontSize: 15,
                            color: color ?? t.ink,
                            fontWeight:
                                strong ? FontWeight.w800 : FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        );
    Widget note(String text) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(text, style: TextStyle(color: t.muted, fontSize: 12)),
        );
    Widget divider() => Divider(height: 16, color: t.outline);
    Widget dot(Color color) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle));
    final cash = SummaryPanel(
        title: 'Composição do caixa',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (d == null)
            const Text('Composição indisponível.')
          else ...[
            row('Saldo inicial', money(d.openingMinor)),
            row('Receitas recebidas', money(d.incomeMinor, '+ '),
                color: t.income),
            row('Despesas pagas', money(d.expenseMinor, '− ')),
            row('Pagamentos de cartões', money(d.cardPaymentsMinor, '− ')),
            row('Transferências recebidas', money(d.transferInMinor, '+ ')),
            row('Transferências enviadas', money(d.transferOutMinor, '− ')),
            divider(),
            row('Saldo consolidado', money(c.currentBalanceMinor),
                strong: true),
            row('Saldo previsto no fim do mês', money(c.projectedBalanceMinor),
                color: t.accent),
          ],
          note(
              'Caixa das contas incluídas no saldo. Compras no cartão entram no caixa pelo pagamento.'),
        ]));
    final groupColors = {
      'Vencidas': t.expense,
      'Hoje e próximos 7 dias': t.accent,
      'Mais adiante': t.muted,
    };
    final due = SummaryPanel(
        title: 'Situação dos compromissos',
        action: TextButton(
            onPressed: () => context.go(AppRoutes.expensesPath),
            child: const Text('Ver despesas')),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          note(
              'Despesas e faturas em aberto com vencimento até o fim do mês selecionado, incluindo atrasos anteriores.'),
          const SizedBox(height: 4),
          for (final group in groups.entries)
            row(
                '${group.key}, ${group.value.length}',
                money(group.value.fold<int>(0, (sum, e) => sum + e.amountMinor),
                    '− '),
                color: group.key == 'Vencidas' && group.value.isNotEmpty
                    ? t.expense
                    : null,
                leading: dot(groupColors[group.key]!)),
          divider(),
          row(
              'Total em aberto',
              money(
                  groups.values
                      .expand((e) => e)
                      .fold<int>(0, (sum, e) => sum + e.amountMinor),
                  '− '),
              strong: true),
          note('Faixas de vencimento calculadas em relação a hoje.'),
        ]));
    final ranking = SummaryPanel(
        title: 'Ranking de despesas',
        action: TextButton(
            onPressed: () => context.go(AppRoutes.analysisPath),
            child: const Text('Ver análises')),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          note('Efetivadas e previstas por categoria no mês selecionado.'),
          if (categories.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Sem categorias com despesas neste mês.')),
          for (final (i, category) in categories.take(6).indexed) ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: Text(category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15))),
              const SizedBox(width: 12),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        '${(category.amountMinor * 100 / total).toStringAsFixed(1).replaceAll('.', ',')}%',
                        style: TextStyle(color: t.muted, fontSize: 13)),
                    const SizedBox(width: 12),
                    Text(money(category.amountMinor),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: category.amountMinor / total,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                color: t.categories[i % t.categories.length],
                backgroundColor: t.isDark ? t.background : t.outline),
          ],
          const SizedBox(height: 8),
          divider(),
          row('Total por categorias', money(total), strong: true),
          if (categories.length > 6)
            note('As 6 maiores estão acima. Consulte as demais em Análises.'),
        ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, box) {
        if (box.maxWidth >= 900 &&
            MediaQuery.textScalerOf(context).scale(16) < 24) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: cash),
            const SizedBox(width: 16),
            Expanded(child: due)
          ]);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [cash, const SizedBox(height: 12), due]);
      }),
      const SizedBox(height: 12),
      ranking,
    ]);
  }
}
