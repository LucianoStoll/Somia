import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/filters/reference_month.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/module_surface.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../domain/entities/dashboard_summary.dart';

class DashboardTransfersCard extends StatelessWidget {
  const DashboardTransfersCard(
      {super.key, required this.currency, required this.month});
  final DashboardCurrencySummary currency;
  final DateTime month;
  @override
  Widget build(BuildContext context) {
    final c = currency;
    String money(int value) => MoneyMinor.display(value, c.currencyCode)
        .replaceAllMapped(RegExp(r'\d{1,3}(?=(\d{3})+,)'), (m) => '${m[0]}.');
    void open([bool create = false]) {
      referenceMonth.select(month);
      context.go(create ? '/transfers?create=1' : '/transfers');
    }

    return Card(
        key: ValueKey('dashboard-transfers-${c.currencyCode}'),
        child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.swap_horiz, color: SomiaColors.blue),
                    const SizedBox(width: 10),
                    const Expanded(
                        child: Text('Transferências',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600))),
                    IconButton(
                        tooltip: 'Nova transferência',
                        onPressed: () => open(true),
                        icon: const Icon(Icons.add, color: SomiaColors.blue)),
                  ]),
                  if (c.transferCount == 0)
                    const Text('Nenhuma transferência neste mês.',
                        style: TextStyle(color: SomiaColors.muted))
                  else ...[
                    Text(
                        '${c.transferCount} ${c.transferCount == 1 ? 'transferência' : 'transferências'} no mês',
                        style: const TextStyle(
                            fontSize: 12, color: SomiaColors.muted)),
                    const SizedBox(height: 8),
                    ModuleValueRow(
                        label: 'Realizadas', value: money(c.transferredMinor)),
                    ModuleValueRow(
                        label: 'Pendentes / agendadas',
                        value: money(c.pendingTransferMinor)),
                  ],
                  Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                          onPressed: () => open(),
                          label: const Text('Ver transferências'),
                          icon: const Icon(Icons.chevron_right))),
                ])));
  }
}
