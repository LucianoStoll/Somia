import 'summary_insights.dart';
import 'dashboard_transfers_card.dart';
import 'dashboard_analysis_view.dart';
import 'recent_activity_details.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fluxo_category_bars.dart';
import 'balance_details_panel.dart';
import '../../../../core/theme/app_theme.dart';
import 'dashboard_overview.dart';
import 'history_tooltip_chart.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_router.dart';
import '../../../../core/routing/somia_shell.dart';
import '../../../../core/filters/reference_month.dart';
import '../../../../core/widgets/month_selector.dart';
import '../../../../core/widgets/balance_help_button.dart';
import '../../../../core/widgets/somia_brand.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../dashboard_cubit.dart';

String _money(int minor, String currencyCode) => MoneyMinor.display(
      minor,
      currencyCode,
    ).replaceAllMapped(
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
  'Dez',
];

/// Cabeçalho do Resumo no celular (direção Fluxo): menu, marca e mês.
class MobileDashboardAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const MobileDashboardAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DashboardCubit, DashboardState>(
        builder: (context, state) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final width = MediaQuery.sizeOf(context).width;
          return AppBar(
            toolbarHeight: 64,
            titleSpacing: 4,
            automaticallyImplyLeading: false,
            leading: somiaMenuLeading(context),
            title: Row(
              children: [
                const SomiaBrand(symbolOnly: true, height: 28),
                if (width >= 340 && scale <= 1.3) ...[
                  const SizedBox(width: SomiaSpace.sm),
                  const Text(
                    'Somia',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
                const Spacer(),
                Flexible(
                  flex: 6,
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
              ],
            ),
          );
        },
      );
}

/// Resumo no celular, na ordem e no desenho do protótipo P-03.
class MobileDashboardBody extends StatefulWidget {
  const MobileDashboardBody({
    super.key,
    required this.state,
    required this.onRefresh,
  });
  final DashboardState state;
  final Future<void> Function() onRefresh;

  @override
  State<MobileDashboardBody> createState() => _MobileDashboardBodyState();
}

class _MobileDashboardBodyState extends State<MobileDashboardBody> {
  bool hidden = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final t = context.somia;
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        key: const ValueKey('dashboard-mobile-scroll'),
        scrollCacheExtent: const ScrollCacheExtent.pixels(2400),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 12, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Resumo do mês',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                IconTheme.merge(
                  data: IconThemeData(color: t.muted),
                  child: const BalanceHelpButton(),
                ),
                IconButton(
                  key: const ValueKey('summary-visibility'),
                  tooltip: hidden
                      ? 'Mostrar valores do resumo'
                      : 'Ocultar valores do resumo',
                  color: t.muted,
                  onPressed: () => setState(() => hidden = !hidden),
                  icon: Icon(hidden
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                ),
              ],
            ),
          ),
          if (state.loading)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: LinearProgressIndicator(),
            ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(state.error!),
            ),
          if (state.summary!.currencies.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Text('Cadastre uma conta para começar seu resumo.',
                  style: TextStyle(color: t.muted)),
            ),
          for (final currency in state.summary!.currencies)
            _CurrencySection(
              currency: currency,
              month: state.month,
              hidden: hidden,
              showCurrency: state.summary!.currencies.length > 1 ||
                  currency.currencyCode != 'BRL',
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SummaryAccounts(currencies: state.summary!.currencies),
                const SizedBox(height: 12),
                _RecentPanel(recent: state.summary!.recent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrencySection extends StatelessWidget {
  const _CurrencySection({
    required this.currency,
    required this.month,
    required this.hidden,
    required this.showCurrency,
  });
  final DashboardCurrencySummary currency;
  final DateTime month;
  final bool hidden;
  final bool showCurrency;

  @override
  Widget build(BuildContext context) {
    final t = context.somia;
    final code = currency.currencyCode;
    final d = currency.balanceDetails;
    final now = DateTime.now();
    final period = DateTime(month.year, month.month);
    final current = DateTime(now.year, now.month);
    final future = period.isAfter(current);
    String money(int value, [String sign = '']) =>
        hidden ? '••••' : '$sign${_money(value, code)}';

    Widget figure(String label, String value, Color color,
        {String? route, String? key}) {
      final content = Padding(
        key: key == null ? null : ValueKey('mobile-$key-$code'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: t.muted, fontSize: 13)),
            const SizedBox(height: SomiaSpace.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(
                      color: color, fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      return Material(
        color: t.surface,
        shape: somiaSurfaceShape(t, SomiaRadius.md),
        child: route == null
            ? content
            : InkWell(
                key: ValueKey('dashboard-link-$route'),
                customBorder: somiaSurfaceShape(t, SomiaRadius.md),
                onTap: () => context.go(route),
                child: content,
              ),
      );
    }

    Widget row(Widget left, Widget right) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 10),
            Expanded(child: right),
          ],
        );

    Widget section(Widget child) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: child,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showCurrency)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Text(code,
                style: TextStyle(color: t.muted, fontWeight: FontWeight.w700)),
          ),
        BalanceDetailCard(
          currencyCode: code,
          child: Padding(
            key: ValueKey('mobile-balance-$code'),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  future
                      ? 'Saldo previsto'
                      : period.isBefore(current)
                          ? 'Saldo efetivado no mês'
                          : 'Saldo atual',
                  style: TextStyle(color: t.muted, fontSize: 14),
                ),
                const SizedBox(height: SomiaSpace.xs),
                LayoutBuilder(builder: (context, box) {
                  final balance = FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      money(future
                          ? currency.projectedBalanceMinor
                          : currency.currentBalanceMinor),
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        height: 1.1,
                      ),
                    ),
                  );
                  final stacked = box.maxWidth < 330 ||
                      MediaQuery.textScalerOf(context).scale(14) > 18;
                  final projected = Column(
                    crossAxisAlignment: stacked
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.end,
                    children: [
                      Text('Previsto no fim do mês',
                          style: TextStyle(color: t.muted, fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(
                        money(currency.projectedBalanceMinor),
                        key: ValueKey('desktop-projected-$code'),
                        style: TextStyle(
                          color: t.accent,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  );
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        balance,
                        const SizedBox(height: SomiaSpace.sm),
                        projected,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: balance),
                      const SizedBox(width: SomiaSpace.md),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: projected,
                      ),
                    ],
                  );
                }),
                const SizedBox(height: SomiaSpace.xs),
                Row(
                  children: [
                    Flexible(
                      child: Text('Ver detalhamento do saldo',
                          style: TextStyle(color: t.muted, fontSize: 13)),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: t.muted),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: BalanceEvolutionPanel(currency: currency, bare: true),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            children: [
              row(
                figure('Recebido no mês', money(d?.incomeMinor ?? 0, '+ '),
                    t.income),
                figure(
                    'Pago no mês',
                    money((d?.expenseMinor ?? 0) + (d?.cardPaymentsMinor ?? 0),
                        '− '),
                    t.ink),
              ),
              const SizedBox(height: 10),
              row(
                figure('A receber', money(d?.pendingIncomeMinor ?? 0, '+ '),
                    t.income,
                    route: AppRoutes.incomePath, key: 'income'),
                figure(
                    'A pagar',
                    money(
                        (d?.pendingExpenseMinor ?? 0) +
                            (d?.pendingInvoicesMinor ?? 0),
                        '− '),
                    t.ink,
                    route: AppRoutes.expensesPath,
                    key: 'expense'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        section(UpcomingPanel(currency: currency)),
        section(_Panel(
          title: 'Gastos por categoria',
          child: DashboardAnalysisView(
            currency: currency,
            builder: (view) => FluxoCategoryBars(
              key: ValueKey('mobile-categories-$code'),
              currency: view,
            ),
          ),
        )),
        section(SummaryInsights(currency: currency, month: month)),
        section(_HistoryPanel(
          key: ValueKey('mobile-history-$code'),
          currency: currency,
        )),
        section(DashboardTransfersCard(currency: currency, month: month)),
        section(AccountTypesPanel(currency: currency)),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) =>
      SummaryPanel(title: title, action: action, child: child);
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
  Widget build(BuildContext context) => _Panel(
        title: 'Receitas vs Despesas',
        action: const Text('Últimos 6 meses'),
        child: DashboardAnalysisView(
          currency: currency,
          builder: (view) => _history(context, view),
        ),
      );

  Widget _history(BuildContext context, DashboardCurrencySummary currency) {
    final maximum = currency.historyAxisMaximumMinor ??
        currency.history.fold<int>(
          0,
          (value, item) =>
              math.max(value, math.max(item.incomeMinor, item.expenseMinor)),
        );
    final magnitude = maximum <= 0
        ? 100.0
        : math.pow(10, (math.log(maximum / 4) / math.ln10).floor()).toDouble();
    final step = maximum <= 0
        ? 100
        : ((maximum / 4 / magnitude).ceil() * magnitude).ceil();
    final ceiling = step * 4;
    final plotHeight =
        MediaQuery.textScalerOf(context).scale(10) > 14 ? 160.0 : 122.0;
    return Column(
      children: [
        if (currency.history.isEmpty)
          SizedBox(
            height: plotHeight,
            child: const Center(
              child: Text('Histórico mensal indisponível.'),
            ),
          )
        else
          SizedBox(
            height: plotHeight,
            child: Row(
              children: [
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
                            child: Text(
                              _axisLabel(step * i),
                              style: TextStyle(
                                fontSize: 10,
                                color: SomiaColors.muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: HistoryTooltipChart(
                    history: currency.history,
                    currencyCode: currency.currencyCode,
                    builder: (target) => Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          bottom: 22,
                          child: CustomPaint(painter: _GridPainter()),
                        ),
                        Row(
                          children: [
                            for (final item in currency.history)
                              Expanded(
                                child: target(
                                  item,
                                  ExcludeSemantics(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                _bar(
                                                  item.incomeMinor,
                                                  ceiling,
                                                  SomiaColors.green,
                                                ),
                                                const SizedBox(width: 3),
                                                _bar(
                                                  item.expenseMinor,
                                                  ceiling,
                                                  SomiaColors.red,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 7),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              _shortMonths[
                                                  item.month.month - 1],
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: SomiaColors.muted,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 18,
          runSpacing: 6,
          children: [
            _Legend('Receitas', SomiaColors.green),
            _Legend('Despesas', SomiaColors.red),
          ],
        ),
      ],
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
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ),
              ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 4, backgroundColor: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: SomiaColors.muted),
          ),
        ],
      );
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
        title: 'Últimos cadastrados',
        action: TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(48, 36),
          ),
          onPressed: () => context.goNamed(AppRoutes.transactions),
          child: const Text('Ver todas', style: TextStyle(fontSize: 11)),
        ),
        child: Column(
          key: const ValueKey('mobile-recent'),
          children: [
            if (recent.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Nenhuma movimentação ainda.'),
              ),
            for (var i = 0; i < recent.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _RecentTile(item: recent[i]),
            ],
          ],
        ),
      );
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.item});
  final DashboardActivity item;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (item.type) {
      DashboardActivityType.income => (
          SomiaColors.green,
          Icons.work_outline_rounded,
        ),
      DashboardActivityType.expense => (
          SomiaColors.red,
          Icons.shopping_cart_outlined,
        ),
      DashboardActivityType.transfer => (
          SomiaColors.blue,
          Icons.swap_horiz,
        ),
    };
    return InkWell(
      onTap: () => showRecentActivityDetails(context, item),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.date.day.toString().padLeft(2, '0')}/${item.date.month.toString().padLeft(2, '0')} · ${item.accountLabel}${item.isEffective ? '' : ' · Pendente'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: SomiaColors.muted,
                    ),
                  ),
                ],
              ),
            ),
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.chevron_right, size: 16, color: SomiaColors.muted),
          ],
        ),
      ),
    );
  }
}
