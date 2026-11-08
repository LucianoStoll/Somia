import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/dashboard_summary.dart';
import '../dashboard_cubit.dart';

/// One selection shared by category and history charts, across month changes.
class DashboardAnalysisView extends StatelessWidget {
  const DashboardAnalysisView({
    super.key,
    required this.currency,
    required this.builder,
  });
  final DashboardCurrencySummary currency;
  final Widget Function(DashboardCurrencySummary view) builder;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DashboardCubit, DashboardState>(builder: (context, state) {
        final mode = state.analysisMode;
        Widget chart(bool realized) => Column(
              key: ValueKey(
                  realized ? 'analysis-realized' : 'analysis-projected'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (mode == DashboardAnalysisMode.both) ...[
                  Text(realized ? 'Valores realizados' : 'Previsão total',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                ],
                builder(currency.forAnalysis(
                    realized: realized,
                    compare: mode == DashboardAnalysisMode.both)),
              ],
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final option in [
                (DashboardAnalysisMode.realized, 'Realizado'),
                (DashboardAnalysisMode.projected, 'Previsto total'),
                (DashboardAnalysisMode.both, 'Ambos'),
              ])
                ChoiceChip(
                  label: Text(option.$2),
                  selected: mode == option.$1,
                  onSelected: (_) => context
                      .read<DashboardCubit>()
                      .selectAnalysisMode(option.$1),
                ),
            ]),
            const SizedBox(height: 8),
            Text(
              mode == DashboardAnalysisMode.realized
                  ? 'Somente valores realizados até hoje. Compras no cartão seguem o mês da fatura; seu pagamento não é contado novamente.'
                  : 'Previsto total = realizado + pendentes e agendados. Os dois valores não devem ser somados. Compras no cartão seguem o mês da fatura.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (mode != DashboardAnalysisMode.projected) chart(true),
            if (mode == DashboardAnalysisMode.both) const SizedBox(height: 20),
            if (mode != DashboardAnalysisMode.realized) chart(false),
          ],
        );
      });
}
