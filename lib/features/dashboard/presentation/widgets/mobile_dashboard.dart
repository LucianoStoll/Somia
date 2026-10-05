import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dashboard_category_chart.dart';
import 'history_tooltip_chart.dart';
import 'balance_details_panel.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_router.dart';
import '../../../../core/filters/reference_month.dart';
import '../../../../core/widgets/month_selector.dart';
import '../../../../core/widgets/balance_help_button.dart';
import '../../../../core/routing/somia_shell.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/somia_brand.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../dashboard_cubit.dart';

String _money(int minor, String currencyCode) =>
    MoneyMinor.display(minor, currencyCode).replaceAllMapped(
        RegExp(r'\d{1,3}(?=(\d{3})+,)'), (match) => '${match[0]}.');

const _shortMonths = [
  'Jan',
  'Fev',
  'Mar',
  'Abr',
  'Mai',
  'Jun',
  'Jul',
  'Ago',
  'Set',
  'Out',
  'Nov',
  'Dez'
];

/// Cabeçalho compacto da referência mobile, com o período sempre acessível.
class MobileDashboardAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const MobileDashboardAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DashboardCubit, DashboardState>(builder: (context, state) {
        final width = MediaQuery.sizeOf(context).width;
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final symbolOnly = width < 390 || scale > 1.3;
        return AppBar(
          toolbarHeight: 64,
          leadingWidth: 48,
          titleSpacing: 4,
          leading: const SomiaMenuButton(),
          title: Row(children: [
            SomiaBrand(symbolOnly: symbolOnly, height: 30),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: MonthSelector(
                  key: const ValueKey('dashboard-month-selector'),
                  month: state.month,
                  header: true,
                  arrows: true,
                  onChanged: referenceMonth.select,
                ),
              ),
            ),
          ]),
        );
      });
}

/// Ordem no Android: saldo, receitas/despesas, gráficos e transações.
class MobileDashboardBody extends StatelessWidget {
  const MobileDashboardBody(
      {super.key, required this.state, required this.onRefresh});
  final DashboardState state;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          key: const ValueKey('dashboard-mobile-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            const Text('Olá, bem-vindo ao Somia!',
                style: TextStyle(color: SomiaColors.muted, fontSize: 14)),
            const SizedBox(height: 4),
            const Row(children: [
              Expanded(
                  child: Text('Resumo do mês',
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w700))),
              BalanceHelpButton(),
            ]),
            const SizedBox(height: 18),
            if (state.loading) const LinearProgressIndicator(),
            if (state.error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(state.error!)),
            if (state.summary!.currencies.isEmpty)
              const Card(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child:
                          Text('Cadastre uma conta para começar seu resumo.'))),
            for (final currency in state.summary!.currencies)
              _CurrencySection(
                currency: currency,
                month: state.month,
                showCurrency: state.summary!.currencies.length > 1 ||
                    currency.currencyCode != 'BRL',
              ),
            _RecentPanel(recent: state.summary!.recent),
          ],
        ),
      );
}

class _CurrencySection extends StatelessWidget {
  const _CurrencySection(
      {required this.currency,
      required this.month,
      required this.showCurrency});
  final DashboardCurrencySummary currency;
  final DateTime month;
  final bool showCurrency;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final future = DateTime(month.year, month.month)
        .isAfter(DateTime(now.year, now.month));
    final code = currency.currencyCode;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (showCurrency)
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(code)),
      BalanceDetailCard(
          currencyCode: code,
          child: _MetricCard(
            key: ValueKey('mobile-balance-$code'),
            wide: true,
            label: future ? 'Saldo previsto' : 'Saldo do mês',
            amount: future
                ? currency.projectedBalanceMinor
                : currency.currentBalanceMinor,
            code: code,
            color: SomiaColors.blue,
            icon: Icons.account_balance_wallet_outlined,
            detail: future
                ? 'Saldo efetivado: ${_money(currency.currentBalanceMinor, code)}'
                : 'Saldo projetado: ${_money(currency.projectedBalanceMinor, code)}',
          )),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: _MetricCard(
          key: ValueKey('mobile-income-$code'),
          label: 'Receitas',
          amount: currency.incomeMinor,
          code: code,
          color: SomiaColors.green,
          icon: Icons.arrow_upward_rounded,
          detail: 'Efetivados e previstos',
        )),
        const SizedBox(width: 10),
        Expanded(
            child: _MetricCard(
          key: ValueKey('mobile-expense-$code'),
          label: 'Despesas',
          amount: currency.expenseMinor,
          code: code,
          color: SomiaColors.red,
          icon: Icons.arrow_downward_rounded,
          detail: 'Efetivados e previstos',
        )),
      ]),
      const SizedBox(height: 12),
      _HistoryPanel(key: ValueKey('mobile-history-$code'), currency: currency),
      const SizedBox(height: 12),
      _Panel(
          title: 'Gastos por categoria',
          child: DashboardCategoryChart(
              key: ValueKey('mobile-categories-$code'), currency: currency)),
      const SizedBox(height: 12),
    ]);
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {super.key,
      this.wide = false,
      required this.label,
      required this.amount,
      required this.code,
      required this.color,
      required this.icon,
      required this.detail});
  final bool wide;
  final String label;
  final int amount;
  final String code;
  final Color color;
  final IconData icon;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(wide ? 11 : 24)),
      child: Icon(icon, size: wide ? 22 : 19, color: color),
    );
    final chartIcon = ExcludeSemantics(
        child: Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(9)),
      child: Icon(Icons.bar_chart_rounded, size: wide ? 22 : 17, color: color),
    ));
    final value = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(_money(amount, code),
          style:
              TextStyle(fontSize: wide ? 24 : 21, fontWeight: FontWeight.w700)),
    );
    final caption = Text(detail,
        style: TextStyle(
            fontSize: 11, color: wide ? SomiaColors.blue : SomiaColors.muted));
    return Container(
      constraints: BoxConstraints(minHeight: wide ? 108 : 128),
      padding: EdgeInsets.all(wide ? 14 : 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.10), SomiaColors.surface]),
        border: Border.all(color: SomiaColors.outline, width: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              badge,
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 12, color: SomiaColors.muted)),
                    const SizedBox(height: 5),
                    value,
                    const SizedBox(height: 7),
                    caption,
                  ])),
              const SizedBox(width: 6),
              chartIcon,
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                badge,
                const SizedBox(width: 7),
                Expanded(
                    child: Text(label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: color))),
                chartIcon,
              ]),
              const SizedBox(height: 9),
              value,
              const SizedBox(height: 7),
              caption,
            ]),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600))),
            if (action != null) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 112),
                  child: action!),
            ],
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      ));
}

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({super.key, required this.currency});
  final DashboardCurrencySummary currency;

  String _axisLabel(int minor) {
    if (minor >= 100000) {
      final value = minor / 100000;
      return '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1).replaceAll('.', ',')} mil';
    }
    return (minor / 100)
        .toStringAsFixed(minor % 100 == 0 ? 0 : 2)
        .replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final maximum = currency.history.fold<int>(
        0,
        (value, item) =>
            math.max(value, math.max(item.incomeMinor, item.expenseMinor)));
    final magnitude = maximum <= 0
        ? 100.0
        : math.pow(10, (math.log(maximum / 4) / math.ln10).floor()).toDouble();
    final step = maximum <= 0
        ? 100
        : ((maximum / 4 / magnitude).ceil() * magnitude).ceil();
    final ceiling = step * 4;
    final plotHeight =
        MediaQuery.textScalerOf(context).scale(10) > 14 ? 160.0 : 122.0;
    return _Panel(
      title: 'Receitas vs Despesas',
      action: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(
            color: SomiaColors.surfaceHigh,
            borderRadius: BorderRadius.circular(8)),
        child: const Text('Últimos 6 meses',
            style: TextStyle(fontSize: 10, color: SomiaColors.muted)),
      ),
      child: Column(children: [
        const Text('Inclui efetivados e previstos',
            style: TextStyle(fontSize: 11, color: SomiaColors.muted)),
        const SizedBox(height: 10),
        if (currency.history.isEmpty)
          SizedBox(
              height: plotHeight,
              child:
                  const Center(child: Text('Histórico mensal indisponível.')))
        else
          SizedBox(
              height: plotHeight,
              child: Row(children: [
                SizedBox(
                    width: 34,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 22),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 4; i >= 0; i--)
                            FittedBox(
                                child: Text(_axisLabel(step * i),
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: SomiaColors.muted)))
                        ],
                      ),
                    )),
                const SizedBox(width: 7),
                Expanded(
                    child: HistoryTooltipChart(
                        history: currency.history,
                        currencyCode: currency.currencyCode,
                        builder: (target) =>
                            Stack(fit: StackFit.expand, children: [
                              Positioned.fill(
                                  bottom: 22,
                                  child: CustomPaint(painter: _GridPainter())),
                              Row(children: [
                                for (final item in currency.history)
                                  Expanded(
                                      child: target(
                                          item,
                                          ExcludeSemantics(
                                              child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(horizontal: 4),
                                                  child: Column(children: [
                                                    Expanded(
                                                        child: Row(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .end,
                                                            children: [
                                                          _bar(
                                                              item.incomeMinor,
                                                              ceiling,
                                                              SomiaColors
                                                                  .green),
                                                          const SizedBox(
                                                              width: 3),
                                                          _bar(
                                                              item.expenseMinor,
                                                              ceiling,
                                                              SomiaColors.red)
                                                        ])),
                                                    const SizedBox(height: 7),
                                                    FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        child: Text(
                                                            _shortMonths[item
                                                                    .month
                                                                    .month -
                                                                1],
                                                            style: const TextStyle(
                                                                fontSize: 10,
                                                                color:
                                                                    SomiaColors
                                                                        .muted)))
                                                  ])))))
                              ]),
                            ]))),
              ])),
        const SizedBox(height: 10),
        const Wrap(
            alignment: WrapAlignment.center,
            spacing: 18,
            runSpacing: 6,
            children: [
              _Legend('Receitas', SomiaColors.green),
              _Legend('Despesas', SomiaColors.red),
            ]),
      ]),
    );
  }

  Widget _bar(int value, int ceiling, Color color) => Expanded(
        child: value <= 0
            ? const SizedBox()
            : FractionallySizedBox(
                heightFactor: (value / ceiling).clamp(0.01, 1.0),
                alignment: Alignment.bottomCenter,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                  color: color,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(3)),
                )),
              ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 4, backgroundColor: color),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 11, color: SomiaColors.muted)),
      ]);
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SomiaColors.outline
      ..strokeWidth = 0.6;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

class _RecentPanel extends StatelessWidget {
  const _RecentPanel({required this.recent});
  final List<DashboardActivity> recent;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Transações recentes',
        action: TextButton(
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(48, 36)),
          onPressed: () => context.goNamed(AppRoutes.transactions),
          child: const Text('Ver todas', style: TextStyle(fontSize: 11)),
        ),
        child: Column(key: const ValueKey('mobile-recent'), children: [
          if (recent.isEmpty)
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Nenhuma movimentação ainda.')),
          for (var i = 0; i < recent.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _RecentTile(item: recent[i]),
          ],
        ]),
      );
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.item});
  final DashboardActivity item;

  @override
  Widget build(BuildContext context) {
    final (color, icon, route) = switch (item.type) {
      DashboardActivityType.income => (
          SomiaColors.green,
          Icons.work_outline_rounded,
          AppRoutes.income
        ),
      DashboardActivityType.expense => (
          SomiaColors.red,
          Icons.shopping_cart_outlined,
          AppRoutes.expenses
        ),
      DashboardActivityType.transfer => (
          SomiaColors.blue,
          Icons.swap_horiz,
          AppRoutes.transfers
        ),
    };
    return InkWell(
      onTap: () => context.goNamed(route),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(item.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(
                      '${item.date.day.toString().padLeft(2, '0')}/${item.date.month.toString().padLeft(2, '0')} · ${item.accountLabel}${item.isEffective ? '' : ' · Pendente'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10, color: SomiaColors.muted)),
                ])),
            const SizedBox(width: 8),
            ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 112),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      '${item.type == DashboardActivityType.income ? '+ ' : item.type == DashboardActivityType.expense ? '- ' : ''}${_money(item.amountMinor, item.currencyCode)}',
                      style: TextStyle(
                          fontSize: 13,
                          color: color,
                          fontWeight: FontWeight.w600)),
                )),
            const SizedBox(width: 3),
            const Icon(Icons.chevron_right, size: 16, color: SomiaColors.muted),
          ])),
    );
  }
}
