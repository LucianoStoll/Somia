import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/filters/reference_month.dart';
import '../../../../core/routing/app_router.dart';
import 'dashboard_palette.dart';
import '../../../../core/widgets/effectuation_date_dialog.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../../accounts/presentation/account_identity.dart';
import '../../../transactions/domain/transactions_repository.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../dashboard_cubit.dart';
import 'balance_details_panel.dart';

String _money(int minor, String code) =>
    MoneyMinor.display(minor, code).replaceAllMapped(
        RegExp(r'\d{1,3}(?=(\d{3})+,)'), (match) => '${match[0]}.');

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
    final period = DateTime(month.year, month.month);
    final current = DateTime(now.year, now.month);
    Widget amount(String label, int value, Color color) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: SomiaColors.muted)),
          const SizedBox(height: 6),
          Text(_money(value, c.currencyCode),
              style: TextStyle(
                  color: color, fontSize: 20, fontWeight: FontWeight.w600)),
        ]);
    Widget pair(Widget left, Widget right) =>
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 270 ||
              MediaQuery.textScalerOf(context).scale(16) > 22) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [left, const SizedBox(height: 12), right]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: left),
            const SizedBox(width: 16),
            Expanded(child: right)
          ]);
        });
    Widget pending(
            String title, int value, Color color, String route, String key) =>
        Material(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
                key: ValueKey('dashboard-link-$route'),
                borderRadius: BorderRadius.circular(18),
                onTap: () => context.go(route),
                child: Padding(
                    key: ValueKey('mobile-$key-${c.currencyCode}'),
                    padding: const EdgeInsets.all(16),
                    child: amount(title, value, color))));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
          child: BalanceDetailCard(
              currencyCode: c.currencyCode,
              child: Padding(
                  key: ValueKey('mobile-balance-${c.currencyCode}'),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                            period.isAfter(current)
                                ? 'Saldo previsto'
                                : period.isBefore(current)
                                    ? 'Saldo efetivado no mês'
                                    : 'Saldo atual',
                            style: const TextStyle(color: SomiaColors.blue)),
                        const SizedBox(height: 6),
                        Text(
                            _money(
                                period.isAfter(current)
                                    ? c.projectedBalanceMinor
                                    : c.currentBalanceMinor,
                                c.currencyCode),
                            style: const TextStyle(
                                fontSize: 34, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          const Text('Saldo previsto no fim do mês',
                              style: TextStyle(color: SomiaColors.muted)),
                          Text(_money(c.projectedBalanceMinor, c.currencyCode),
                              key: ValueKey(
                                  'desktop-projected-${c.currencyCode}'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600))
                        ]),
                        const Divider(height: 28),
                        pair(
                            amount('Recebido no mês', d?.incomeMinor ?? 0,
                                SomiaColors.green),
                            amount(
                                'Pago no mês',
                                (d?.expenseMinor ?? 0) +
                                    (d?.cardPaymentsMinor ?? 0),
                                SomiaColors.red)),
                        const SizedBox(height: 16),
                        Text(
                            'Resultado do mês: ${_money(c.monthlyResultMinor, c.currencyCode)}',
                            style: const TextStyle(color: SomiaColors.muted)),
                      ])))),
      const SizedBox(height: 12),
      pair(
          pending('A receber', d?.pendingIncomeMinor ?? 0, SomiaColors.green,
              AppRoutes.incomePath, 'income'),
          pending(
              'A pagar',
              (d?.pendingExpenseMinor ?? 0) + (d?.pendingInvoicesMinor ?? 0),
              SomiaColors.red,
              AppRoutes.expensesPath,
              'expense')),
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
  bool expanded = false;
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
                          _money(
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
      action: widget.currency.upcoming.length > 3
          ? TextButton(
              onPressed: () => setState(() => expanded = !expanded),
              child: Text(expanded ? 'Ver menos' : 'Ver todos'))
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
            'Pendências até o fim do mês selecionado, incluindo atrasadas.',
            style: TextStyle(color: SomiaColors.muted)),
        if (widget.currency.upcoming.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('Nenhum vencimento pendente.')),
        for (final item in widget.currency.upcoming
            .take(expanded ? widget.currency.upcoming.length : 3))
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(item.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                        '${item.date.day.toString().padLeft(2, '0')}/${item.date.month.toString().padLeft(2, '0')}/${item.date.year} • ${item.isOverdue(DateTime.now()) ? 'Vencido' : 'Pendente'}',
                        style: const TextStyle(color: SomiaColors.muted)),
                    Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(
                              _money(item.amountMinor,
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
    final today = DateTime.now();
    final todayIndex = points.indexWhere((p) =>
        p.date.year == today.year &&
        p.date.month == today.month &&
        p.date.day == today.day);
    final index =
            (selected ?? (todayIndex >= 0 ? todayIndex : points.length - 1))
                .clamp(0, points.length - 1),
        p = points[index];
    final values = points.expand((p) => [p.currentMinor, p.projectedMinor]);
    final low = math.min(0, values.reduce(math.min)),
        high = math.max(0, values.reduce(math.max));
    return SummaryPanel(
        title: 'Evolução do saldo',
        action: const Tooltip(
            message:
                'A previsão inclui pendências cadastradas e faturas; não estima recorrências ainda não geradas. Valores diários são cumulativos, inclusive pendências vencidas.',
            child:
                Icon(Icons.info_outline, size: 20, color: SomiaColors.muted)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              'Dia ${p.date.day} • efetivado ${_money(p.currentMinor, widget.currency.currencyCode)} • previsto ${_money(p.projectedMinor, widget.currency.currencyCode)}'),
          const SizedBox(height: 12),
          Text(_money(high, widget.currency.currencyCode),
              style: const TextStyle(color: SomiaColors.muted, fontSize: 12)),
          LayoutBuilder(builder: (context, box) {
            void select(double x) => setState(() => selected =
                (x / box.maxWidth * (points.length - 1))
                    .round()
                    .clamp(0, points.length - 1));
            return Semantics(
                label: 'Consultar saldo diário',
                value: 'Dia ${p.date.day}',
                increasedValue: index < points.length - 1 ? 'Dia ${points[index + 1].date.day}' : null,
                decreasedValue: index > 0 ? 'Dia ${points[index - 1].date.day}' : null,
                onIncrease: index < points.length - 1
                    ? () => setState(() => selected = index + 1)
                    : null,
                onDecrease: index > 0
                    ? () => setState(() => selected = index - 1)
                    : null,
                child: GestureDetector(
                    key: const ValueKey('balance-evolution-plot'),
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (event) => select(event.localPosition.dx),
                    onHorizontalDragUpdate: (event) =>
                        select(event.localPosition.dx),
                    child: SizedBox(
                        height: 190,
                        width: double.infinity,
                        child: CustomPaint(
                            painter:
                                _BalancePainter(points, low, high, index)))));
          }),
          Text(_money(low, widget.currency.currencyCode),
              style: const TextStyle(color: SomiaColors.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (final i in {0, points.length ~/ 2, points.length - 1})
              Text('${points[i].date.day}',
                  style:
                      const TextStyle(color: SomiaColors.muted, fontSize: 12))
          ]),
          const SizedBox(height: 16),
          const Wrap(spacing: 16, runSpacing: 8, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.show_chart, size: 18, color: SomiaColors.blue),
              SizedBox(width: 6),
              Flexible(
                  child: Text('Efetivado',
                      style: TextStyle(color: SomiaColors.blue)))
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.more_horiz, size: 18, color: SomiaColors.green),
              SizedBox(width: 6),
              Flexible(
                  child: Text('Previsto',
                      style: TextStyle(color: SomiaColors.green)))
            ])
          ]),
          const SizedBox(height: 8),
          const Text('Toque ou arraste no gráfico para consultar o dia.',
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
            (i - 1) / math.max(1, points.length - 1) * size.width,
            y(projected
                ? points[i - 1].projectedMinor
                : points[i - 1].currentMinor));
        final b = Offset(i / math.max(1, points.length - 1) * size.width,
            y(projected ? points[i].projectedMinor : points[i].currentMinor));
        if (projected) {
          final distance = (b - a).distance;
          for (var offset = 0.0; offset < distance; offset += 9) {
            canvas.drawLine(
                Offset.lerp(a, b, offset / distance)!,
                Offset.lerp(a, b, math.min(offset + 4, distance) / distance)!,
                paint);
          }
        } else {
          canvas.drawLine(a, b, paint);
        }
      }
    }
    final now = DateTime.now();
    final today = points.indexWhere((p) =>
        p.date.year == now.year &&
        p.date.month == now.month &&
        p.date.day == now.day);
    if (today >= 0) {
      final tx = today / math.max(1, points.length - 1) * size.width;
      canvas.drawLine(Offset(tx, 0), Offset(tx, size.height),
          Paint()..color = SomiaColors.muted.withValues(alpha: .25));
      final label = TextPainter(
          text: const TextSpan(
              text: 'Hoje',
              style: TextStyle(color: SomiaColors.muted, fontSize: 11)),
          textDirection: TextDirection.ltr)
        ..layout();
      label.paint(
          canvas,
          Offset(tx.clamp(0, math.max(0, size.width - label.width)).toDouble(),
              0));
    }
    final x = selected / math.max(1, points.length - 1) * size.width;
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
                              Text(_money(a.currentMinor, a.currencyCode),
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

class AccountTypesPanel extends StatelessWidget {
  const AccountTypesPanel({super.key, required this.currency});
  final DashboardCurrencySummary currency;
  @override
  Widget build(BuildContext context) {
    final totals = <String, int>{};
    for (final account in currency.accounts) {
      totals.update(account.typeLabel, (value) => value + account.currentMinor,
          ifAbsent: () => account.currentMinor);
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final max = entries.fold<int>(
        1, (value, entry) => math.max(value, entry.value.abs()));
    return SummaryPanel(
        title: 'Saldo por tipo de conta',
        action: const Tooltip(
            message:
                'Saldos efetivados de todas as contas, inclusive as excluídas do saldo principal. Cada moeda é apresentada separadamente.',
            child:
                Icon(Icons.info_outline, color: SomiaColors.muted, size: 20)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (entries.isEmpty) const Text('Nenhuma conta para mostrar.'),
          for (final entry in entries)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text(entry.key),
                            Text(_money(entry.value, currency.currencyCode),
                                style: TextStyle(
                                    color: entry.value < 0
                                        ? SomiaColors.red
                                        : SomiaColors.blue,
                                    fontWeight: FontWeight.w600))
                          ]),
                      const SizedBox(height: 8),
                      Semantics(
                          label:
                              '${entry.key}: ${_money(entry.value, currency.currencyCode)}',
                          child: LinearProgressIndicator(
                              value: entry.value.abs() / max,
                              minHeight: 7,
                              borderRadius: BorderRadius.circular(8),
                              backgroundColor: SomiaColors.outline,
                              color: entry.value < 0
                                  ? SomiaColors.red
                                  : SomiaColors.blue)),
                    ])),
        ]));
  }
}
