import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/filters/reference_month.dart';
import '../../../../core/widgets/month_selector.dart';
import '../../../../core/widgets/balance_help_button.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/routing/somia_shell.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/somia_brand.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../domain/dashboard_repository.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../dashboard_cubit.dart';
import '../widgets/mobile_dashboard.dart';
import '../widgets/desktop_history_chart.dart';
import '../widgets/balance_details_panel.dart';
import '../widgets/dashboard_category_chart.dart';

const _chartColors = [
  SomiaColors.blue,
  SomiaColors.red,
  SomiaColors.purple,
  SomiaColors.green,
  SomiaColors.yellow,
  Color(0xFF8F9BB7)
];

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => DashboardCubit(getIt<DashboardRepository>(),
            selection: referenceMonth),
        child: const _DashboardView(),
      );
}

class _DashboardView extends StatefulWidget {
  const _DashboardView();
  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<DashboardCubit>().load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: MediaQuery.sizeOf(context).width < 800
            ? const MobileDashboardAppBar()
            : AppBar(
                title: const SomiaBrand(height: 32),
                leading: somiaMenuLeading(context),
                actions: [
                    IconButton(
                        tooltip: 'Atualizar resumo',
                        icon: const Icon(Icons.refresh),
                        onPressed: context.read<DashboardCubit>().load)
                  ]),
        floatingActionButton: const SomiaQuickActions(),
        body: BlocBuilder<DashboardCubit, DashboardState>(
            builder: (context, state) {
          if (state.loading && state.summary == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.summary == null) {
            return Center(
                child: TextButton(
                    onPressed: context.read<DashboardCubit>().load,
                    child: Text(
                        '${state.error ?? 'Resumo indisponível.'} Tentar novamente')));
          }
          if (MediaQuery.sizeOf(context).width < 800) {
            return MobileDashboardBody(
                state: state, onRefresh: context.read<DashboardCubit>().load);
          }
          return RefreshIndicator(
              onRefresh: context.read<DashboardCubit>().load,
              child: LayoutBuilder(
                  builder: (context, box) => ListView(
                          padding: EdgeInsets.fromLTRB(
                              box.maxWidth < 600 ? 16 : 28,
                              12,
                              box.maxWidth < 600 ? 16 : 28,
                              100),
                          children: [
                            Center(
                                child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 1260),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _header(context, state),
                                          if (state.loading)
                                            const LinearProgressIndicator(),
                                          if (state.error != null)
                                            Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 8),
                                                child: Text(state.error!)),
                                          if (state.summary!.currencies.isEmpty)
                                            const Card(
                                                child: Padding(
                                                    padding: EdgeInsets.all(24),
                                                    child: Text(
                                                        'Cadastre uma conta para começar seu resumo.'))),
                                          for (final currency
                                              in state.summary!.currencies)
                                            _currencySection(
                                                context,
                                                currency,
                                                state.month,
                                                state.summary!.currencies
                                                        .length >
                                                    1),
                                          const SizedBox(height: 14),
                                          _bottomPanels(
                                              context,
                                              state.summary!.recent,
                                              state.summary!.currencies),
                                        ])))
                          ])));
        }),
      );

  Widget _header(BuildContext context, DashboardState state) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 14,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Olá, bem-vindo ao Somia!',
                  style: const TextStyle(color: SomiaColors.muted)),
              const SizedBox(height: 3),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                    child: Text('Resumo do mês',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700))),
                const BalanceHelpButton(),
              ]),
            ]),
            MonthSelector(month: state.month, onChanged: referenceMonth.select),
          ]));

  Widget _currencySection(
      BuildContext context,
      DashboardCurrencySummary currency,
      DateTime month,
      bool multipleCurrencies) {
    final now = DateTime.now();
    final future = DateTime(month.year, month.month)
        .isAfter(DateTime(now.year, now.month));
    final code = currency.currencyCode;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (multipleCurrencies || code != 'BRL')
        Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 10),
            child: Text(code, style: Theme.of(context).textTheme.titleMedium)),
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth >= 940
            ? 4
            : constraints.maxWidth >= 480
                ? 2
                : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        final tiles = [
          BalanceDetailCard(
              currencyCode: code,
              child: _metric(
                  context,
                  future ? 'Saldo previsto' : 'Saldo total',
                  future
                      ? currency.projectedBalanceMinor
                      : currency.currentBalanceMinor,
                  code,
                  Icons.account_balance_wallet_outlined,
                  SomiaColors.blue,
                  future
                      ? 'Saldo efetivado: ${MoneyMinor.display(currency.currentBalanceMinor, code)}'
                      : 'Saldo projetado: ${MoneyMinor.display(currency.projectedBalanceMinor, code)}')),
          _sectionLink(
              context,
              AppRoutes.incomePath,
              'Receitas',
              _metric(
                  context,
                  'Receitas',
                  currency.incomeMinor,
                  code,
                  Icons.arrow_upward_rounded,
                  SomiaColors.green,
                  'Efetivados e previstos')),
          _sectionLink(
              context,
              AppRoutes.expensesPath,
              'Despesas',
              _metric(
                  context,
                  'Despesas',
                  currency.expenseMinor,
                  code,
                  Icons.arrow_downward_rounded,
                  SomiaColors.red,
                  'Efetivados e previstos')),
          BalanceDetailCard(
              key: ValueKey('desktop-projected-$code'),
              currencyCode: code,
              child: _metric(
                  context,
                  'Saldo projetado',
                  currency.projectedBalanceMinor,
                  code,
                  Icons.bar_chart_rounded,
                  SomiaColors.blue,
                  MoneyMinor.display(currency.monthlyResultMinor, code))),
        ];
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final tile in tiles) SizedBox(width: width, child: tile)
        ]);
      }),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 790 &&
            MediaQuery.textScalerOf(context).scale(16) < 24;
        final chart = _historyPanel(context, currency);
        final donut = _categoryPanel(context, currency);
        return wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 11, child: chart),
                const SizedBox(width: 12),
                Expanded(flex: 9, child: donut),
              ])
            : Column(children: [chart, const SizedBox(height: 12), donut]);
      }),
      const SizedBox(height: 6),
    ]);
  }

  Widget _sectionLink(
          BuildContext context, String path, String label, Widget child) =>
      Semantics(
          button: true,
          label: 'Abrir $label',
          child: InkWell(
              key: ValueKey('dashboard-link-$path'),
              onTap: () => context.go(path),
              borderRadius: BorderRadius.circular(15),
              child: child));

  Widget _metric(BuildContext context, String label, int amount, String code,
          IconData icon, Color tint, String detail) =>
      Container(
          constraints: const BoxConstraints(minHeight: 146),
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [tint.withValues(alpha: 0.12), SomiaColors.surface]),
              border: Border.all(color: SomiaColors.outline),
              borderRadius: BorderRadius.circular(15)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 19, color: tint)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tint))),
            ]),
            const SizedBox(height: 15),
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(MoneyMinor.display(amount, code),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700))),
            const SizedBox(height: 8),
            if (label == 'Saldo projetado') ...[
              Text('Resultado do mês',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: SomiaColors.muted)),
              Text(detail,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: SomiaColors.muted)),
            ] else
              Text(detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: SomiaColors.muted)),
          ]));

  Widget _panel(BuildContext context, String title, Widget content,
          {Widget? action}) =>
      Card(
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(builder: (context, box) {
                      final heading = Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600));
                      if (action == null) return heading;
                      if (box.maxWidth < 400 ||
                          MediaQuery.textScalerOf(context).scale(16) >= 24) {
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              heading,
                              Align(
                                  alignment: Alignment.centerRight,
                                  child: action)
                            ]);
                      }
                      return Row(children: [Expanded(child: heading), action]);
                    }),
                    const SizedBox(height: 16),
                    content,
                  ])));

  Widget _historyPanel(
          BuildContext context, DashboardCurrencySummary currency) =>
      _panel(
          context,
          'Receitas vs Despesas',
          Column(children: [
            const Text('Inclui efetivados e previstos',
                style: TextStyle(color: SomiaColors.muted)),
            const SizedBox(height: 12),
            if (currency.history.isEmpty)
              const SizedBox(
                  height: 190,
                  child: Center(child: Text('Histórico mensal indisponível.')))
            else
              DesktopHistoryChart(currency: currency),
            const SizedBox(height: 12),
            const Wrap(alignment: WrapAlignment.center, spacing: 18, children: [
              _LegendDot('Receitas', SomiaColors.green),
              _LegendDot('Despesas', SomiaColors.red),
            ]),
          ]),
          action: Text('Últimos 6 meses',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: SomiaColors.muted)));

  Widget _categoryPanel(
          BuildContext context, DashboardCurrencySummary currency) =>
      _panel(context, 'Gastos por categoria',
          DashboardCategoryChart(currency: currency));

  Widget _bottomPanels(BuildContext context, List<DashboardActivity> recent,
          List<DashboardCurrencySummary> currencies) =>
      LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 790 &&
            MediaQuery.textScalerOf(context).scale(16) < 24;
        final transactions = _panel(
            context,
            'Últimos lançamentos',
            recent.isEmpty
                ? const Text('Nenhuma movimentação ainda.')
                : Column(children: [
                    for (final item in recent) _recentTile(context, item)
                  ]),
            action: TextButton(
                onPressed: () => context.goNamed(AppRoutes.transactions),
                child: const Text('Ver todos')));
        final accounts = _panel(
            context,
            'Saldo por conta',
            currencies.every((c) => c.accounts.isEmpty)
                ? const Text('Nenhuma conta cadastrada.')
                : Column(children: [
                    for (final currency in currencies)
                      for (final account in currency.accounts.take(5))
                        _accountTile(context, account)
                  ]),
            action: TextButton(
                onPressed: () => context.goNamed(AppRoutes.accounts),
                child: const Text('Ver todas')));
        return wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: transactions),
                const SizedBox(width: 12),
                Expanded(child: accounts),
              ])
            : Column(
                children: [transactions, const SizedBox(height: 12), accounts]);
      });

  Widget _recentTile(BuildContext context, DashboardActivity item) {
    final color = switch (item.type) {
      DashboardActivityType.income => SomiaColors.green,
      DashboardActivityType.expense => SomiaColors.red,
      DashboardActivityType.transfer => SomiaColors.blue,
    };
    return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.16),
            child: Icon(
                switch (item.type) {
                  DashboardActivityType.income => Icons.arrow_upward,
                  DashboardActivityType.expense => Icons.shopping_cart_outlined,
                  DashboardActivityType.transfer => Icons.swap_horiz,
                },
                color: color,
                size: 20)),
        title: Text(item.description,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
            '${item.date.day.toString().padLeft(2, '0')}/'
            '${item.date.month.toString().padLeft(2, '0')}/${item.date.year} · '
            '${item.accountLabel}${item.isEffective ? '' : ' · Pendente'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        trailing: Text(
            '${item.type == DashboardActivityType.income ? '+' : item.type == DashboardActivityType.expense ? '-' : ''}'
            '${MoneyMinor.display(item.amountMinor, item.currencyCode)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        onTap: () => context.goNamed(item.type == DashboardActivityType.transfer
            ? AppRoutes.transfers
            : item.type == DashboardActivityType.income
                ? AppRoutes.income
                : AppRoutes.expenses));
  }

  Widget _accountTile(BuildContext context, DashboardAccountBalance account) {
    final color = _chartColors[
        account.name.codeUnits.fold<int>(0, (value, code) => value + code) %
            _chartColors.length];
    return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.22),
            child: Text(
                account.name.isEmpty ? '?' : account.name[0].toUpperCase(),
                style: TextStyle(color: color, fontWeight: FontWeight.w700))),
        title: Text(account.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(account.typeLabel),
        trailing: Text(
            MoneyMinor.display(account.currentMinor, account.currencyCode),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => context.goNamed(AppRoutes.accounts));
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 5, backgroundColor: color),
        const SizedBox(width: 7),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: SomiaColors.muted))
      ]);
}
