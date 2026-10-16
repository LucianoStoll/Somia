import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/filters/reference_month.dart';
import '../../../../core/widgets/month_selector.dart';
import '../../../../core/widgets/balance_help_button.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/routing/somia_shell.dart';
import '../widgets/dashboard_palette.dart';
import '../../../../core/widgets/somia_brand.dart';
import '../../../accounts/domain/money_minor.dart';
import '../../domain/dashboard_repository.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../dashboard_cubit.dart';
import '../widgets/mobile_dashboard.dart';
import '../widgets/desktop_history_chart.dart';
import '../widgets/dashboard_category_chart.dart';
import '../widgets/dashboard_overview.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => DashboardCubit(getIt<DashboardRepository>(),
            selection: referenceMonth),
        child: Builder(builder: (context) {
          final theme = Theme.of(context);
          return Theme(
              data: theme.copyWith(
                scaffoldBackgroundColor: SomiaColors.background,
                colorScheme: theme.colorScheme.copyWith(
                    primary: SomiaColors.blue, surface: SomiaColors.surface),
                appBarTheme: theme.appBarTheme
                    .copyWith(backgroundColor: SomiaColors.background),
                cardTheme: theme.cardTheme.copyWith(color: SomiaColors.surface),
                dividerColor: SomiaColors.outline,
              ),
              child: const _DashboardView());
        }),
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
        floatingActionButton: MediaQuery.sizeOf(context).width < 800
            ? null
            : const SomiaQuickActions(),
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
                                        const BoxConstraints(maxWidth: 1760),
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
    final code = currency.currencyCode;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (multipleCurrencies || code != 'BRL') Text(code),
      SummaryMetrics(currency: currency, month: month),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, box) {
        final evolution = BalanceEvolutionPanel(currency: currency);
        final categories = _categoryPanel(context, currency);
        return box.maxWidth >= 900 &&
                MediaQuery.textScalerOf(context).scale(16) < 24
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 6, child: evolution),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: categories)
              ])
            : Column(
                children: [evolution, const SizedBox(height: 16), categories]);
      }),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, box) {
        final history = _historyPanel(context, currency);
        final types = AccountTypesPanel(currency: currency);
        return box.maxWidth >= 900 &&
                MediaQuery.textScalerOf(context).scale(16) < 24
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 6, child: history),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: types)
              ])
            : Column(children: [history, const SizedBox(height: 16), types]);
      }),
      const SizedBox(height: 16),
      UpcomingPanel(currency: currency),
      const SizedBox(height: 6),
    ]);
  }

  Widget _panel(BuildContext context, String title, Widget content,
          {Widget? action}) =>
      SummaryPanel(title: title, action: action, child: content);

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
            'Últimos cadastrados',
            recent.isEmpty
                ? const Text('Nenhuma movimentação ainda.')
                : Column(children: [
                    for (final item in recent) _recentTile(context, item)
                  ]),
            action: TextButton(
                onPressed: () => context.goNamed(AppRoutes.transactions),
                child: const Text('Ver todos')));
        final accounts = SummaryAccounts(currencies: currencies);
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
