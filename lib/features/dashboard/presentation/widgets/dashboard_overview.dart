import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/filters/reference_month.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/effectuation_date_dialog.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../../accounts/presentation/account_identity.dart';
import '../../../transactions/domain/transactions_repository.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../dashboard_cubit.dart';
import 'balance_details_panel.dart';

class SummaryPanel extends StatelessWidget {
  const SummaryPanel(
      {super.key, required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (action != null) action!
                ]),
            const SizedBox(height: 16),
            child
          ])));
}

class SummaryMetrics extends StatelessWidget {
  const SummaryMetrics(
      {super.key, required this.currency, required this.month});
  final DashboardCurrencySummary currency;
  final DateTime month;
  @override
  Widget build(BuildContext context) {
    final c = currency, d = c.balanceDetails;
    final now = DateTime.now();
    final future = DateTime(month.year, month.month)
        .isAfter(DateTime(now.year, now.month));
    final past = DateTime(month.year, month.month)
        .isBefore(DateTime(now.year, now.month));
    Widget metric(
        String title, int value, String detail, Color color, IconData icon,
        {String? route, bool balance = false, Key? key}) {
      final content = Container(
          key: key,
          padding: const EdgeInsets.all(18),
          constraints: const BoxConstraints(minHeight: 150),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              border: Border.all(color: SomiaColors.outline),
              borderRadius: BorderRadius.circular(16)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(color: color)),
            const SizedBox(height: 8),
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(MoneyMinor.display(value, c.currencyCode),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700))),
            const SizedBox(height: 8),
            Text(detail,
                style: const TextStyle(color: SomiaColors.muted, fontSize: 12))
          ]));
      if (balance) {
        return BalanceDetailCard(
            currencyCode: c.currencyCode,
            interactionKey: title == 'Saldo previsto no fim do mês'
                ? ValueKey('forecast-detail-${c.currencyCode}')
                : null,
            child: content);
      }
      return InkWell(
          key: ValueKey('dashboard-link-$route'),
          onTap: () => context.go(route!),
          borderRadius: BorderRadius.circular(16),
          child: content);
    }

    final cards = [
      metric(
          future
              ? 'Saldo previsto'
              : past
                  ? 'Saldo efetivado no mês'
                  : 'Saldo atual',
          future ? c.projectedBalanceMinor : c.currentBalanceMinor,
          'Contas incluídas no saldo • corte do mês selecionado',
          SomiaColors.blue,
          Icons.account_balance_wallet_outlined,
          balance: true,
          key: ValueKey('mobile-balance-${c.currencyCode}')),
      metric(
          'A receber',
          d?.pendingIncomeMinor ?? 0,
          'Recebido no mês: ${MoneyMinor.display(d?.incomeMinor ?? 0, c.currencyCode)}',
          SomiaColors.green,
          Icons.arrow_upward,
          route: AppRoutes.incomePath,
          key: ValueKey('mobile-income-${c.currencyCode}')),
      metric(
          'A pagar',
          (d?.pendingExpenseMinor ?? 0) + (d?.pendingInvoicesMinor ?? 0),
          'Pago no mês: ${MoneyMinor.display((d?.expenseMinor ?? 0) + (d?.cardPaymentsMinor ?? 0), c.currencyCode)} • inclui faturas',
          SomiaColors.red,
          Icons.arrow_downward,
          route: AppRoutes.expensesPath,
          key: ValueKey('mobile-expense-${c.currencyCode}')),
      metric(
          'Saldo previsto no fim do mês',
          c.projectedBalanceMinor,
          'Após pendências e transferências',
          SomiaColors.blue,
          Icons.event_available,
          balance: true,
          key: ValueKey('desktop-projected-${c.currencyCode}')),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, box) {
        final large = MediaQuery.textScalerOf(context).scale(16) > 22;
        final n = box.maxWidth >= 1050 && !large
            ? 4
            : box.maxWidth >= 600 && !large
                ? 2
                : 1;
        if (box.maxWidth < 600) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cards[0],
                const SizedBox(height: 12),
                if (large) ...[
                  cards[1],
                  const SizedBox(height: 12),
                  cards[2]
                ] else
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: cards[1]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[2])
                  ]),
                const SizedBox(height: 12),
                cards[3]
              ]);
        }
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final card in cards)
            SizedBox(width: (box.maxWidth - 12 * (n - 1)) / n, child: card)
        ]);
      }),
      const SizedBox(height: 12),
      Text(
          'Resultado do mês: ${MoneyMinor.display(c.monthlyResultMinor, c.currencyCode)} • receitas menos despesas, incluindo previstos; não é o saldo acumulado.',
          style: const TextStyle(color: SomiaColors.muted))
    ]);
  }
}

class UpcomingPanel extends StatefulWidget {
  const UpcomingPanel({super.key, required this.currency});
  final DashboardCurrencySummary currency;
  @override
  State<UpcomingPanel> createState() => _UpcomingPanelState();
}

class _UpcomingPanelState extends State<UpcomingPanel> {
  bool busy = false;
  Future<void> settle(DashboardDue item) async {
    final date = await chooseEffectuationDate(context, item.date);
    if (date == null || !mounted) return;
    setState(() => busy = true);
    try {
      await getIt<TransactionsRepository>()
          .setEffective(item.id, effective: true, effectiveDate: date);
      if (mounted) await context.read<DashboardCubit>().load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Não foi possível efetivar. Abra o lançamento para conferir seus vínculos e pagamentos.')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openDetails(DashboardDue item) async {
    final open = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: Text(item.description),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          MoneyMinor.display(
                              item.amountMinor, widget.currency.currencyCode),
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      Text(
                          'Vencimento: ${item.date.day}/${item.date.month}/${item.date.year}'),
                      const SizedBox(height: 8),
                      Text(item.kind == 'invoice'
                          ? 'Saldo de fatura ainda não coberto por pagamentos.'
                          : 'Valor restante previsto. Abra a lista para editar ou consultar pagamentos parciais.'),
                    ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Fechar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: Text(item.kind == 'invoice'
                          ? 'Abrir fatura'
                          : 'Abrir lançamento'))
                ]));
    if (open != true || !mounted) return;
    referenceMonth.select(item.date);
    context.go(item.kind == 'invoice'
        ? '${AppRoutes.cardsPath}?card=${item.cardId}&month=${item.date.year}-${item.date.month.toString().padLeft(2, '0')}-01'
        : item.id.startsWith('cashback-receipt-')
            ? '${AppRoutes.cashbackPath}?receipt=${item.id}'
            : item.kind == 'income'
                ? AppRoutes.incomePath
                : AppRoutes.expensesPath);
  }

  @override
  Widget build(BuildContext context) => SummaryPanel(
      title: 'Próximos vencimentos',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
            'Pendências até o fim do mês selecionado, incluindo atrasadas.',
            style: TextStyle(color: SomiaColors.muted)),
        if (widget.currency.upcoming.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('Nenhum vencimento pendente.')),
        for (final item in widget.currency.upcoming.take(5))
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(item.description,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                        '${item.date.day.toString().padLeft(2, '0')}/${item.date.month.toString().padLeft(2, '0')}/${item.date.year} • ${item.date.isBefore(DateUtils.dateOnly(DateTime.now())) ? 'Vencido' : 'Pendente'}',
                        style: const TextStyle(color: SomiaColors.muted)),
                    Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(
                              MoneyMinor.display(item.amountMinor,
                                  widget.currency.currencyCode),
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: item.kind == 'income'
                                      ? SomiaColors.green
                                      : SomiaColors.red)),
                          Wrap(children: [
                            TextButton(
                                onPressed: () => openDetails(item),
                                child: const Text('Abrir')),
                            if (item.canSettle)
                              TextButton(
                                  onPressed: busy ? null : () => settle(item),
                                  child: const Text('Efetivar'))
                          ])
                        ]),
                    const Divider(height: 1)
                  ])),
        if (widget.currency.upcoming.length > 5)
          Text(
              '${widget.currency.upcoming.length - 5} outras pendências nas listas de receitas, despesas e cartões.',
              style: const TextStyle(color: SomiaColors.muted)),
      ]));
}

class BalanceEvolutionPanel extends StatefulWidget {
  const BalanceEvolutionPanel({super.key, required this.currency});
  final DashboardCurrencySummary currency;
  @override
  State<BalanceEvolutionPanel> createState() => _BalanceEvolutionPanelState();
}

class _BalanceEvolutionPanelState extends State<BalanceEvolutionPanel> {
  int? selected;
  @override
  Widget build(BuildContext context) {
    final points = widget.currency.dailyBalances;
    if (points.isEmpty) {
      return const SummaryPanel(
          title: 'Evolução do saldo',
          child: Text('Sem histórico diário disponível.'));
    }
    final index = (selected ?? points.length - 1).clamp(0, points.length - 1),
        p = points[index];
    final values = points.expand((p) => [p.currentMinor, p.projectedMinor]);
    final low = math.min(0, values.reduce(math.min)),
        high = math.max(0, values.reduce(math.max));
    return SummaryPanel(
        title: 'Evolução do saldo',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              'Dia ${p.date.day} • efetivado ${MoneyMinor.display(p.currentMinor, widget.currency.currencyCode)} • previsto ${MoneyMinor.display(p.projectedMinor, widget.currency.currencyCode)}'),
          const SizedBox(height: 12),
          Text(MoneyMinor.display(high, widget.currency.currencyCode),
              style: const TextStyle(color: SomiaColors.muted, fontSize: 12)),
          SizedBox(
              height: 160,
              child: CustomPaint(
                  painter: _BalancePainter(points, low, high, index))),
          Text(MoneyMinor.display(low, widget.currency.currencyCode),
              style: const TextStyle(color: SomiaColors.muted, fontSize: 12)),
          Slider(
              label: 'Dia ${p.date.day}',
              value: index.toDouble(),
              min: 0,
              max: (points.length - 1).toDouble(),
              divisions: points.length - 1,
              onChanged: (v) => setState(() => selected = v.round())),
          const Wrap(spacing: 16, runSpacing: 8, children: [
            Text('━ Efetivado', style: TextStyle(color: SomiaColors.blue)),
            Text('┄ Previsto', style: TextStyle(color: SomiaColors.green))
          ]),
          const SizedBox(height: 8),
          const Text(
              'Arraste para consultar cada dia. A previsão inclui pendências cadastradas e faturas; não estima recorrências ainda não geradas.',
              style: TextStyle(color: SomiaColors.muted, fontSize: 12)),
        ]));
  }
}

class _BalancePainter extends CustomPainter {
  _BalancePainter(this.points, this.low, this.high, this.selected);
  final List<DashboardDailyBalance> points;
  final int low, high, selected;
  @override
  void paint(Canvas canvas, Size size) {
    double y(int value) =>
        size.height -
        (value - low) / (high == low ? 1 : high - low) * size.height;
    canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)),
        Paint()..color = SomiaColors.outline);
    for (final projected in [false, true]) {
      final paint = Paint()
        ..color = projected ? SomiaColors.green : SomiaColors.blue
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      for (var i = 1; i < points.length; i++) {
        final a = Offset(
            (i - 1) / (points.length - 1) * size.width,
            y(projected
                ? points[i - 1].projectedMinor
                : points[i - 1].currentMinor));
        final b = Offset(i / (points.length - 1) * size.width,
            y(projected ? points[i].projectedMinor : points[i].currentMinor));
        if (projected) {
          for (var t = 0.0; t < 1; t += 0.4) {
            canvas.drawLine(Offset.lerp(a, b, t)!,
                Offset.lerp(a, b, math.min(t + 0.23, 1))!, paint);
          }
        } else {
          canvas.drawLine(a, b, paint);
        }
      }
    }
    final x = selected / (points.length - 1) * size.width;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height),
        Paint()..color = SomiaColors.muted.withValues(alpha: 0.5));
  }

  @override
  bool shouldRepaint(covariant _BalancePainter old) => true;
}

class SummaryAccounts extends StatefulWidget {
  const SummaryAccounts({super.key, required this.currencies});
  final List<DashboardCurrencySummary> currencies;
  @override
  State<SummaryAccounts> createState() => _SummaryAccountsState();
}

class _SummaryAccountsState extends State<SummaryAccounts> {
  bool hideZero = false;
  @override
  Widget build(BuildContext context) => SummaryPanel(
      title: 'Saldo por conta',
      action: TextButton(
          onPressed: () => context.go(AppRoutes.accountsPath),
          child: const Text('Ver todas')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ocultar contas zeradas'),
            value: hideZero,
            onChanged: (v) => setState(() => hideZero = v)),
        for (final currency in widget.currencies) ...[
          for (final investment in [false, true]) ...[
            if (currency.accounts.any((a) =>
                a.isInvestment == investment &&
                (!hideZero || a.currentMinor != 0)))
              Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(
                      '${investment ? 'Investimentos' : 'Dia a dia'} • ${currency.currencyCode}',
                      style: const TextStyle(color: SomiaColors.muted))),
            for (final a in currency.accounts.where((a) =>
                a.isInvestment == investment &&
                (!hideZero || a.currentMinor != 0)))
              InkWell(
                  onTap: () => context.go(a.id == null
                      ? AppRoutes.accountsPath
                      : '${AppRoutes.accountsPath}/${a.id}'),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        AccountAvatar(institutionId: a.institutionId),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(a.name),
                              Text(
                                  a.includeInBalance
                                      ? 'Incluída no saldo'
                                      : 'Fora do saldo principal',
                                  style: const TextStyle(
                                      color: SomiaColors.muted, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(
                                  MoneyMinor.display(
                                      a.currentMinor, a.currencyCode),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                      color: a.currentMinor < 0
                                          ? SomiaColors.red
                                          : null))
                            ]))
                      ]))),
          ],
        ],
        if (widget.currencies.every(
            (c) => c.accounts.every((a) => hideZero && a.currentMinor == 0)))
          const Text('Nenhuma conta para mostrar.'),
      ]));
}
