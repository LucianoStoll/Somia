import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../core/filters/reference_month.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/month_selector.dart';
import '../data/account_statement_repository.dart';
import '../domain/account_statement.dart';
import '../domain/money_minor.dart';
import 'account_identity.dart';
import 'account_statement_cubit.dart';

class AccountStatementPage extends StatelessWidget {
  const AccountStatementPage({super.key, required this.accountId});
  final String accountId;
  @override
  Widget build(BuildContext context) => BlocProvider(
      create: (_) =>
          AccountStatementCubit(getIt<AccountStatementRepository>(), accountId),
      child: const _StatementView());
}

class _StatementView extends StatefulWidget {
  const _StatementView();
  @override
  State<_StatementView> createState() => _StatementViewState();
}

class _StatementViewState extends State<_StatementView> {
  bool projected = false;
  String _money(int amount, String currency) =>
      MoneyMinor.display(amount, currency);
  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Detalhes da conta'),
          leading: BackButton(onPressed: () => context.go('/accounts')),
          actions: [
            IconButton(
                tooltip: 'Atualizar extrato',
                onPressed: () => context.read<AccountStatementCubit>().load(),
                icon: const Icon(Icons.refresh))
          ]),
      body: BlocBuilder<AccountStatementCubit, AccountStatementState>(
          builder: (context, state) {
        if (state.error != null) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(state.error!),
            TextButton(
                onPressed: () => context.read<AccountStatementCubit>().load(),
                child: const Text('Tentar novamente'))
          ]));
        }
        final s = state.statement;
        if (s == null) return const Center(child: CircularProgressIndicator());
        final account = s.account,
            currency = account.currencyCode,
            section = projected ? s.projected : s.realized;
        return RefreshIndicator(
            onRefresh: () => context.read<AccountStatementCubit>().load(),
            child: ListView(
                key: const ValueKey('account-statement-scroll'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (state.loading) const LinearProgressIndicator(),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: AccountAvatar(
                          institutionId: account.institutionId,
                          type: account.type),
                      title: Text(account.name,
                          style: Theme.of(context).textTheme.titleLarge),
                      subtitle: Text(
                          '${account.type.label} · $currency${account.isArchived ? ' · Arquivada' : ''}${account.includeInBalance ? '' : ' · Fora do saldo consolidado'}')),
                  ValueListenableBuilder<DateTime>(
                      valueListenable: referenceMonth,
                      builder: (_, month, __) => MonthSelector(
                          month: month, onChanged: referenceMonth.select)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    ChoiceChip(
                        key: const ValueKey('statement-realized'),
                        label: const Text('Realizado'),
                        selected: !projected,
                        onSelected: (_) => setState(() => projected = false)),
                    ChoiceChip(
                        key: const ValueKey('statement-projected'),
                        label: const Text('Previsto'),
                        selected: projected,
                        onSelected: (_) => setState(() => projected = true))
                  ]),
                  const SizedBox(height: 8),
                  Text(
                      projected
                          ? 'Inclui realizados, pendentes pelo vencimento e agendados pela efetivação.'
                          : 'Somente movimentações efetivadas até hoje, no mês selecionado.',
                      style: const TextStyle(
                          color: SomiaColors.muted, fontSize: 12)),
                  const SizedBox(height: 16),
                  LayoutBuilder(builder: (_, constraints) {
                    final width = constraints.maxWidth < 600
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 12) / 2;
                    Widget metric(String label, int amount, {Color? color}) =>
                        SizedBox(
                            width: width,
                            child: Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(label),
                                          const SizedBox(height: 4),
                                          Text(_money(amount, currency),
                                              style: TextStyle(
                                                  fontSize: 19,
                                                  fontWeight: FontWeight.w600,
                                                  color: color))
                                        ]))));
                    return Wrap(spacing: 12, runSpacing: 8, children: [
                      metric('Saldo inicial do mês', section.openingMinor),
                      metric(
                          projected
                              ? 'Saldo previsto no fim do mês'
                              : 'Saldo realizado no mês',
                          section.closingMinor,
                          color: SomiaColors.blue),
                      metric('Receitas', section.total(StatementKind.income),
                          color: SomiaColors.green),
                      metric('Despesas', section.total(StatementKind.expense),
                          color: SomiaColors.red),
                      metric('Transferências recebidas',
                          section.total(StatementKind.transferIn)),
                      metric('Transferências enviadas',
                          section.total(StatementKind.transferOut)),
                      if (section.total(StatementKind.cardPayment) > 0)
                        metric('Pagamentos de cartão',
                            section.total(StatementKind.cardPayment)),
                      if (section.total(StatementKind.invoice) > 0)
                        metric('Faturas previstas',
                            section.total(StatementKind.invoice)),
                      if (section.adjustmentsMinor != 0)
                        metric('Compensações de faturas previstas',
                            section.adjustmentsMinor,
                            color: SomiaColors.purple),
                    ]);
                  }),
                  const SizedBox(height: 16),
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Evolução do saldo diário',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 12),
                                Text(
                                    'Faixa: ${_money([section.openingMinor, ...section.dailyBalances].reduce(math.min), currency)} a ${_money([
                                          section.openingMinor,
                                          ...section.dailyBalances
                                        ].reduce(math.max), currency)}',
                                    style: const TextStyle(
                                        color: SomiaColors.muted,
                                        fontSize: 12)),
                                const SizedBox(height: 8),
                                Semantics(
                                    label:
                                        'Saldo inicial ${_money(section.openingMinor, currency)}, final ${_money(section.closingMinor, currency)}',
                                    child: SizedBox(
                                        height: 130,
                                        width: double.infinity,
                                        child: CustomPaint(
                                            painter: _BalancePainter([
                                          section.openingMinor,
                                          ...section.dailyBalances
                                        ])))),
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Expanded(child: Text('Início')),
                                      Expanded(
                                          child: Text(
                                              'Dia ${(section.dailyBalances.length / 2).round()}',
                                              textAlign: TextAlign.center)),
                                      Expanded(
                                          child: Text(
                                              'Dia ${section.dailyBalances.length}',
                                              textAlign: TextAlign.end))
                                    ]),
                                const SizedBox(height: 8),
                                Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    spacing: 16,
                                    children: [
                                      Text(
                                          'Início: ${_money(section.openingMinor, currency)}'),
                                      Text(
                                          'Final: ${_money(section.closingMinor, currency)}')
                                    ])
                              ]))),
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Entradas e saídas do mês',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 12),
                                for (final data in [
                                  (
                                    'Entradas',
                                    section.incomingMinor,
                                    SomiaColors.green
                                  ),
                                  (
                                    'Saídas',
                                    section.outgoingMinor,
                                    SomiaColors.red
                                  )
                                ]) ...[
                                  Wrap(spacing: 12, children: [
                                    Text(data.$1),
                                    Text(_money(data.$2, currency),
                                        style: TextStyle(color: data.$3))
                                  ]),
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                      value: math.max(section.incomingMinor,
                                                  section.outgoingMinor) ==
                                              0
                                          ? 0
                                          : data.$2 /
                                              math.max(section.incomingMinor,
                                                  section.outgoingMinor),
                                      color: data.$3,
                                      minHeight: 8),
                                  const SizedBox(height: 12)
                                ],
                                const Text(
                                    'Transferências incluídas. Compensações de previsão de cartão aparecem separadamente.',
                                    style: TextStyle(
                                        color: SomiaColors.muted, fontSize: 12))
                              ]))),
                  const SizedBox(height: 16),
                  Text('Extrato diário',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (section.days.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nenhuma movimentação neste mês.')),
                  for (final day in section.days)
                    Card(
                        key: ValueKey('statement-day-${day.date.day}'),
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_date(day.date),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  const Divider(),
                                  for (final entry in day.entries)
                                    _entry(entry, currency),
                                  const Divider(),
                                  Wrap(spacing: 12, children: [
                                    const Text('Saldo ao fim do dia'),
                                    Text(_money(day.closingMinor, currency),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: SomiaColors.blue))
                                  ])
                                ])))
                ]));
      }));
  Widget _entry(StatementEntry entry, String currency) {
    final adjustment = entry.kind == StatementKind.adjustment;
    final color = adjustment
        ? SomiaColors.purple
        : entry.amountMinor >= 0
            ? SomiaColors.green
            : SomiaColors.red;
    return Padding(
        key: ValueKey('statement-entry-${entry.id}'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LayoutBuilder(
            builder: (_, constraints) =>
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(
                        adjustment
                            ? Icons.balance
                            : entry.kind == StatementKind.transferIn ||
                                    entry.kind == StatementKind.transferOut
                                ? Icons.swap_horiz
                                : entry.kind == StatementKind.cardPayment ||
                                        entry.kind == StatementKind.invoice
                                    ? Icons.credit_card
                                    : entry.amountMinor >= 0
                                        ? Icons.arrow_upward
                                        : Icons.arrow_downward,
                        size: 18,
                        color: color),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(entry.description,
                            maxLines: 2, overflow: TextOverflow.ellipsis))
                  ]),
                  if (entry.detail?.isNotEmpty ?? false)
                    Padding(
                        padding: const EdgeInsets.only(left: 26, top: 3),
                        child: Text(entry.detail!,
                            style: const TextStyle(
                                color: SomiaColors.muted, fontSize: 12))),
                  Padding(
                      padding: const EdgeInsets.only(left: 26, top: 4),
                      child: Wrap(spacing: 12, runSpacing: 4, children: [
                        Text(
                            '${entry.amountMinor >= 0 ? '+' : '-'}${_money(entry.amountMinor.abs(), currency)}',
                            style: TextStyle(
                                color: color, fontWeight: FontWeight.w600)),
                        Text(
                            adjustment
                                ? 'Compensação'
                                : entry.effective
                                    ? 'Efetivado'
                                    : entry.kind == StatementKind.invoice
                                        ? 'Previsto'
                                        : 'Pendente / agendado',
                            style: const TextStyle(
                                color: SomiaColors.muted, fontSize: 12))
                      ]))
                ])));
  }
}

class _BalancePainter extends CustomPainter {
  _BalancePainter(this.points);
  final List<int> points;
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final min = points.reduce(math.min).toDouble(),
        max = points.reduce(math.max).toDouble();
    final range = max == min ? 1.0 : max - min;
    final grid = Paint()
      ..color = SomiaColors.outline
      ..strokeWidth = 1;
    for (var n = 0; n < 4; n++) {
      final y = 8 + (size.height - 16) * n / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / math.max(1, points.length - 1);
      final y = max == min
          ? size.height / 2
          : 8 + (size.height - 16) * (max - points[i]) / range;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = SomiaColors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(covariant _BalancePainter oldDelegate) =>
      oldDelegate.points != points;
}
