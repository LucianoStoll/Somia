import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/month_selector.dart';
import '../../../core/widgets/module_surface.dart';
import '../../accounts/domain/money_minor.dart';
import '../domain/planning.dart';

class PlanningIndicators extends StatefulWidget {
  const PlanningIndicators(
      {super.key,
      required this.month,
      required this.currency,
      required this.spending});
  final DateTime month;
  final String currency;
  final List<MonthlySpend> spending;

  @override
  State<PlanningIndicators> createState() => _PlanningIndicatorsState();
}

class _PlanningIndicatorsState extends State<PlanningIndicators> {
  bool projected = false;

  @override
  Widget build(BuildContext context) {
    final data = PlanningMonthIndicators.fromSpending(widget.spending,
        currency: widget.currency, projected: projected);
    final hasRows = widget.spending.any((s) => s.currency == widget.currency);
    String money(int value) => MoneyMinor.display(value, widget.currency)
        .replaceAllMapped(RegExp(r'\d{1,3}(?=(\d{3})+,)'), (m) => '${m[0]}.');
    final rate = data.savingRate;
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text(
                  '${monthNames[widget.month.month - 1]} ${widget.month.year} · ${widget.currency}',
                  style:
                      const TextStyle(color: SomiaColors.muted, fontSize: 13))),
          IconButton(
              tooltip: 'Como os indicadores são calculados',
              icon: const Icon(Icons.info_outline, size: 20),
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                        title: const Text('Sobre os indicadores'),
                        content: const SingleChildScrollView(
                            child: Text(
                                'Realizado considera os valores efetivados. Previsto inclui o realizado e os lançamentos previstos do mês.\n\n'
                                'Resultado = receitas menos despesas do mês. O saldo das contas também considera meses anteriores.\n\n'
                                'Sobra da renda = resultado dividido pelas receitas. Sem receitas positivas, o percentual fica indisponível. Não representa aportes em investimentos.\n\n'
                                'Transferências entre contas não entram como renda ou despesa. Compras no cartão seguem o mês da fatura; o pagamento não duplica a despesa. Estornos reduzem despesas e reembolsos permanecem receitas separadas.')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Entendi'))
                        ],
                      ))),
        ]),
        const SizedBox(height: 4),
        SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Realizado')),
              ButtonSegment(value: true, label: Text('Previsto')),
            ],
            selected: {projected},
            onSelectionChanged: (selection) =>
                setState(() => projected = selection.single)),
        const SizedBox(height: 16),
        if (!hasRows)
          const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Sem movimentos nesta moeda e neste mês.',
                  style: TextStyle(color: SomiaColors.muted))),
        ModuleValueRow(label: 'Receitas', value: money(data.income)),
        ModuleValueRow(label: 'Despesas', value: money(data.expense)),
        const Divider(height: 24),
        const Text('Resultado do mês',
            style: TextStyle(color: SomiaColors.muted, fontSize: 13)),
        const SizedBox(height: 6),
        Text(money(data.result),
            key: const ValueKey('planning-indicator-result'),
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: data.result < 0
                    ? SomiaColors.red
                    : data.result > 0
                        ? SomiaColors.green
                        : SomiaColors.muted)),
        const SizedBox(height: 12),
        ModuleValueRow(
            label: 'Sobra da renda',
            value: rate == null
                ? '—'
                : '${rate.toStringAsFixed(1).replaceAll('.', ',')}%'),
        if (rate == null)
          const Text('Sem receitas positivas para calcular o percentual.',
              style: TextStyle(color: SomiaColors.muted, fontSize: 12)),
        if (data.result < 0)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  projected
                      ? 'Despesas previstas acima das receitas.'
                      : 'Despesas realizadas acima das receitas.',
                  style:
                      const TextStyle(color: SomiaColors.red, fontSize: 12))),
      ]),
    ));
  }
}
