import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/month_selector.dart';
import '../../../accounts/domain/money_minor.dart';
import '../dashboard_cubit.dart';

class BalanceDetailCard extends StatelessWidget {
  const BalanceDetailCard(
      {super.key, required this.currencyCode, required this.child});
  final String currencyCode;
  final Widget child;
  @override
  Widget build(BuildContext context) => Semantics(
      button: true,
      label: 'Detalhar saldo em $currencyCode',
      child: Material(
          color: Colors.transparent,
          child: InkWell(
              key: ValueKey('balance-detail-$currencyCode'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => showBalanceDetails(context, currencyCode),
              child: child)));
}

Future<void> showBalanceDetails(
    BuildContext context, String currencyCode) async {
  final cubit = context.read<DashboardCubit>();
  final content = BlocProvider.value(
      value: cubit, child: _Details(currencyCode: currencyCode));
  cubit.load();
  if (Theme.of(context).platform == TargetPlatform.android ||
      Theme.of(context).platform == TargetPlatform.iOS) {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.86, child: content));
  } else {
    await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
            child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: 620,
                    maxHeight: MediaQuery.sizeOf(context).height * 0.86),
                child: content)));
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.currencyCode});
  final String currencyCode;
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DashboardCubit, DashboardState>(builder: (context, state) {
        final currency = state.summary?.currencies
            .where((c) => c.currencyCode == currencyCode)
            .firstOrNull;
        final details = currency?.balanceDetails;
        Widget row(String label, int amount,
                {bool total = false, Color? color, String? key}) =>
            Padding(
                key: key == null ? null : ValueKey(key),
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: LayoutBuilder(builder: (_, box) {
                  final value = Text(MoneyMinor.display(amount, currencyCode),
                      style: TextStyle(
                          fontWeight: total ? FontWeight.w700 : FontWeight.w500,
                          color: color));
                  final title = Text(label,
                      style: TextStyle(
                          fontWeight: total ? FontWeight.w700 : null));
                  if (box.maxWidth < 380 ||
                      MediaQuery.textScalerOf(context).scale(14) > 20) {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 3), value]);
                  }
                  return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 16),
                        value
                      ]);
                }));
        return Column(key: const ValueKey('balance-details-panel'), children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              child: Row(children: [
                Expanded(
                    child: Text('Detalhamento do saldo',
                        style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                    tooltip: 'Fechar detalhamento',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close))
              ])),
          if (state.loading) const LinearProgressIndicator(),
          Expanded(
              child: SingleChildScrollView(
                  key: const ValueKey('balance-details-scroll'),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                            '${monthNames[state.month.month - 1]} ${state.month.year} · $currencyCode',
                            style: const TextStyle(
                                color: SomiaColors.blue,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(
                            'Corte: ${DateTime(state.month.year, state.month.month + 1, 0).day}/${state.month.month.toString().padLeft(2, '0')}/${state.month.year}. Inclui efetivações agendadas até essa data.',
                            style: const TextStyle(
                                color: SomiaColors.muted, fontSize: 12)),
                        if (state.error != null) ...[
                          Text(state.error!),
                          TextButton(
                              onPressed: () =>
                                  context.read<DashboardCubit>().load(),
                              child: const Text('Tentar novamente'))
                        ],
                        if (details == null && !state.loading)
                          const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                  'Detalhamento indisponível para esta moeda.')),
                        if (details != null) ...[
                          const SizedBox(height: 20),
                          Text('Consolidado',
                              style: Theme.of(context).textTheme.titleMedium),
                          row('Saldo inicial do período', details.openingMinor,
                              key: 'balance-opening'),
                          row('Receitas efetivadas', details.incomeMinor,
                              color: SomiaColors.green),
                          row('Despesas pagas', -details.expenseMinor,
                              color: SomiaColors.red),
                          row('Transferências recebidas',
                              details.transferInMinor),
                          row('Transferências enviadas',
                              -details.transferOutMinor),
                          if (details.cardPaymentsMinor != 0)
                            row('Pagamentos de cartão',
                                -details.cardPaymentsMinor,
                                color: SomiaColors.red),
                          const Divider(),
                          row('Saldo efetivado', details.currentMinor,
                              total: true,
                              color: SomiaColors.blue,
                              key: 'balance-current'),
                          const SizedBox(height: 20),
                          Text('Previsto',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          const Text(
                              'Parte do saldo efetivado e inclui pendências com vencimento até o corte, inclusive de meses anteriores.',
                              style: TextStyle(
                                  color: SomiaColors.muted, fontSize: 12)),
                          row('Saldo efetivado', details.currentMinor),
                          row('Receitas pendentes', details.pendingIncomeMinor,
                              color: SomiaColors.green),
                          row('Despesas pendentes',
                              -details.pendingExpenseMinor,
                              color: SomiaColors.red),
                          row('Transferências a receber',
                              details.pendingTransferInMinor),
                          row('Transferências a enviar',
                              -details.pendingTransferOutMinor),
                          if (details.pendingInvoicesMinor != 0)
                            row('Faturas de cartão pendentes',
                                -details.pendingInvoicesMinor,
                                color: SomiaColors.red),
                          const Divider(),
                          row('Saldo previsto ao final do mês',
                              details.projectedMinor,
                              total: true,
                              color: SomiaColors.blue,
                              key: 'balance-projected'),
                          const SizedBox(height: 12),
                          const Text(
                              'Somente contas incluídas no saldo consolidado. Transferências entre elas se compensam. Pagamentos de cartão debitam a conta; a previsão inclui apenas a dívida restante.',
                              style: TextStyle(
                                  color: SomiaColors.muted, fontSize: 12)),
                        ]
                      ])))
        ]);
      });
}
