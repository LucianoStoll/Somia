import '../../../../core/preferences/interface_preferences.dart';
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
export 'balance_evolution_panel.dart';

String _money(int minor, String code) => MoneyMinor.display(
      minor,
      code,
    ).replaceAllMapped(
        RegExp(r'\d{1,3}(?=(\d{3})+,)'), (match) => '${match[0]}.');

class SummaryPanel extends StatefulWidget {
  const SummaryPanel({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });
  final String title;
  final Widget child;
  final Widget? action;
  @override
  State<SummaryPanel> createState() => _SummaryPanelState();
}

class _SummaryPanelState extends State<SummaryPanel> {
  InterfacePreferences? get preferences =>
      getIt.isRegistered<InterfacePreferences>()
          ? getIt<InterfacePreferences>()
          : null;
  bool localCollapsed = false;
  bool get collapsed =>
      preferences?.read('summary.collapsed.${widget.title}') ?? localCollapsed;
  Future<void> toggle() async {
    final value = !collapsed;
    setState(() => localCollapsed = value);
    try {
      final save =
          preferences?.write('summary.collapsed.${widget.title}', value);
      setState(() {});
      await save;
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível lembrar esta escolha.')));
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (widget.action != null) widget.action!,
                    IconButton(
                        tooltip:
                            collapsed ? 'Expandir bloco' : 'Recolher bloco',
                        onPressed: toggle,
                        icon: Icon(
                            collapsed ? Icons.expand_more : Icons.expand_less)),
                  ]),
                ],
              ),
              if (!collapsed) ...[const SizedBox(height: 16), widget.child],
            ],
          ),
        ),
      );
}

class SummaryMetrics extends StatefulWidget {
  const SummaryMetrics(
      {super.key, required this.currency, required this.month});
  final DashboardCurrencySummary currency;
  final DateTime month;
  @override
  State<SummaryMetrics> createState() => _SummaryMetricsState();
}

class _SummaryMetricsState extends State<SummaryMetrics> {
  bool hidden = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.currency, d = c.balanceDetails;
    final now = DateTime.now();
    final period = DateTime(widget.month.year, widget.month.month);
    final current = DateTime(now.year, now.month);
    String money(int value) => hidden ? '••••' : _money(value, c.currencyCode);
    Widget amount(String label, int value, Color color, {bool small = false}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: SomiaColors.muted, fontSize: small ? 12 : 13)),
          const SizedBox(height: 6),
          if (small)
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(money(value),
                    style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)))
          else
            Text(money(value),
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.w600)),
        ]);
    Widget pair(Widget left, Widget right, {bool divider = false}) =>
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 270 ||
              MediaQuery.textScalerOf(context).scale(16) > 22) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [left, const SizedBox(height: 12), right]);
          }
          return IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Expanded(child: left),
                if (divider)
                  const SizedBox(
                      height: 56,
                      child: VerticalDivider(
                          width: 26, color: SomiaColors.outline))
                else
                  const SizedBox(width: 10),
                Expanded(child: right),
              ]));
        });
    Widget pending(String title, int value, Color color, String route,
            String key, IconData icon) =>
        Material(
            color: color.withValues(alpha: .17),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
                key: ValueKey('dashboard-link-$route'),
                borderRadius: BorderRadius.circular(18),
                onTap: () => context.go(route),
                child: Padding(
                    key: ValueKey('mobile-$key-${c.currencyCode}'),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                    child: Row(children: [
                      Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: color, width: 1.5)),
                          child: Icon(icon, size: 20, color: color)),
                      const SizedBox(width: 9),
                      Expanded(child: amount(title, value, color, small: true)),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right,
                          color: SomiaColors.muted, size: 16),
                    ]))));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
          child: BalanceDetailCard(
              currencyCode: c.currencyCode,
              child: Padding(
                  key: ValueKey('mobile-balance-${c.currencyCode}'),
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(
                                        period.isAfter(current)
                                            ? 'Saldo previsto'
                                            : period.isBefore(current)
                                                ? 'Saldo efetivado no mês'
                                                : 'Saldo atual',
                                        style: const TextStyle(
                                            color: SomiaColors.blue,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 4),
                                    Text(
                                        money(period.isAfter(current)
                                            ? c.projectedBalanceMinor
                                            : c.currentBalanceMinor),
                                        style: const TextStyle(
                                            color: SomiaColors.blue,
                                            fontSize: 34,
                                            fontWeight: FontWeight.w700)),
                                  ])),
                              IconButton(
                                  key: const ValueKey('summary-visibility'),
                                  tooltip: hidden
                                      ? 'Mostrar valores do resumo'
                                      : 'Ocultar valores do resumo',
                                  onPressed: () =>
                                      setState(() => hidden = !hidden),
                                  icon: Icon(
                                      hidden
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: SomiaColors.blue)),
                            ]),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          const Text('Previsto no fim do mês',
                              style: TextStyle(
                                  color: SomiaColors.muted, fontSize: 13)),
                          Text(money(c.projectedBalanceMinor),
                              key: ValueKey(
                                  'desktop-projected-${c.currencyCode}'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                        ]),
                        const Divider(height: 26, color: SomiaColors.outline),
                        pair(
                            amount('Recebido no mês', d?.incomeMinor ?? 0,
                                SomiaColors.green),
                            amount(
                                'Pago no mês',
                                (d?.expenseMinor ?? 0) +
                                    (d?.cardPaymentsMinor ?? 0),
                                SomiaColors.red),
                            divider: true),
                      ])))),
      const SizedBox(height: 10),
      pair(
          pending('A receber', d?.pendingIncomeMinor ?? 0, SomiaColors.green,
              AppRoutes.incomePath, 'income', Icons.arrow_downward),
          pending(
              'A pagar',
              (d?.pendingExpenseMinor ?? 0) + (d?.pendingInvoicesMinor ?? 0),
              SomiaColors.red,
              AppRoutes.expensesPath,
              'expense',
              Icons.arrow_upward)),
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
      await getIt<TransactionsRepository>().setEffective(
        item.id,
        effective: true,
        effectiveDate: date,
      );
      if (mounted) await context.read<DashboardCubit>().load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível efetivar. Abra o lançamento para conferir seus vínculos e pagamentos.',
            ),
          ),
        );
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
              _money(item.amountMinor, widget.currency.currencyCode),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Vencimento: ${item.date.day}/${item.date.month}/${item.date.year}',
            ),
            const SizedBox(height: 8),
            Text(
              item.kind == 'invoice'
                  ? 'Saldo de fatura ainda não coberto por pagamentos.'
                  : 'Valor restante previsto. Abra a lista para editar ou consultar pagamentos parciais.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Fechar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(
              item.kind == 'invoice' ? 'Abrir fatura' : 'Abrir lançamento',
            ),
          ),
        ],
      ),
    );
    if (open != true || !mounted) return;
    referenceMonth.select(item.date);
    context.go(
      item.kind == 'invoice'
          ? '${AppRoutes.cardsPath}?card=${item.cardId}&month=${item.date.year}-${item.date.month.toString().padLeft(2, '0')}-01'
          : item.id.startsWith('cashback-receipt-')
              ? '${AppRoutes.cashbackPath}?receipt=${item.id}'
              : item.kind == 'income'
                  ? AppRoutes.incomePath
                  : AppRoutes.expensesPath,
    );
  }

  @override
  Widget build(BuildContext context) => SummaryPanel(
        title: 'Próximos vencimentos',
        action: widget.currency.upcoming.length > 3
            ? TextButton(
                onPressed: () => setState(() => expanded = !expanded),
                child: Text(expanded ? 'Ver menos' : 'Ver todos'),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pendências até o fim do mês selecionado, incluindo atrasadas.',
              style: TextStyle(color: SomiaColors.muted),
            ),
            if (widget.currency.upcoming.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('Nenhum vencimento pendente.'),
              ),
            for (final item in widget.currency.upcoming.take(
              expanded ? widget.currency.upcoming.length : 3,
            ))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${item.date.day.toString().padLeft(2, '0')}/${item.date.month.toString().padLeft(2, '0')}/${item.date.year} • ${item.isOverdue(DateTime.now()) ? 'Vencido' : 'Pendente'}',
                      style: const TextStyle(color: SomiaColors.muted),
                    ),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          _money(
                              item.amountMinor, widget.currency.currencyCode),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: item.kind == 'income'
                                ? SomiaColors.green
                                : SomiaColors.red,
                          ),
                        ),
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: () => openDetails(item),
                              child: const Text('Abrir'),
                            ),
                            if (item.canSettle)
                              TextButton(
                                onPressed: busy ? null : () => settle(item),
                                child: const Text('Efetivar'),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                  ],
                ),
              ),
          ],
        ),
      );
}

class SummaryAccounts extends StatefulWidget {
  const SummaryAccounts({super.key, required this.currencies});
  final List<DashboardCurrencySummary> currencies;
  @override
  State<SummaryAccounts> createState() => _SummaryAccountsState();
}

class _SummaryAccountsState extends State<SummaryAccounts> {
  late bool hideZero;
  @override
  void initState() {
    super.initState();
    hideZero = getIt.isRegistered<InterfacePreferences>() &&
        getIt<InterfacePreferences>().read('summary.hideZeroAccounts');
  }

  Future<void> changeHideZero(bool value) async {
    setState(() => hideZero = value);
    if (!getIt.isRegistered<InterfacePreferences>()) return;
    try {
      await getIt<InterfacePreferences>()
          .write('summary.hideZeroAccounts', value);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível lembrar esta escolha.')));
    }
  }

  @override
  Widget build(BuildContext context) => SummaryPanel(
        title: 'Saldo por conta',
        action: TextButton(
          onPressed: () => context.go(AppRoutes.accountsPath),
          child: const Text('Ver todas'),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ocultar contas zeradas'),
              value: hideZero,
              onChanged: changeHideZero,
            ),
            for (final currency in widget.currencies) ...[
              for (final investment in [false, true]) ...[
                if (currency.accounts.any(
                  (a) =>
                      a.isInvestment == investment &&
                      (!hideZero || a.currentMinor != 0),
                ))
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Text(
                      '${investment ? 'Investimentos' : 'Dia a dia'} • ${currency.currencyCode}',
                      style: const TextStyle(color: SomiaColors.muted),
                    ),
                  ),
                for (final a in currency.accounts.where(
                  (a) =>
                      a.isInvestment == investment &&
                      (!hideZero || a.currentMinor != 0),
                ))
                  InkWell(
                    onTap: () => context.go(
                      a.id == null
                          ? AppRoutes.accountsPath
                          : '${AppRoutes.accountsPath}/${a.id}',
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
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
                                    color: SomiaColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _money(a.currentMinor, a.currencyCode),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                    color: a.currentMinor < 0
                                        ? SomiaColors.red
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
            if (widget.currencies.every(
              (c) => c.accounts.every((a) => hideZero && a.currentMinor == 0),
            ))
              const Text('Nenhuma conta para mostrar.'),
          ],
        ),
      );
}

class AccountTypesPanel extends StatelessWidget {
  const AccountTypesPanel({super.key, required this.currency});
  final DashboardCurrencySummary currency;

  static const _order = [
    'Conta corrente',
    'Carteira',
    'Investimentos',
    'Poupança',
    'Outras'
  ];

  String _label(String type) => switch (type) {
        'Carteira / dinheiro' || 'Carteira' => 'Carteira',
        'Investimento' || 'Investimentos' => 'Investimentos',
        'Outra' => 'Outras',
        _ => type,
      };

  (IconData, Color) _appearance(String type) => switch (type) {
        'Conta corrente' => (
            Icons.credit_card_outlined,
            const Color(0xFFA5CDE2)
          ),
        'Carteira' => (
            Icons.account_balance_wallet_outlined,
            const Color(0xFFBAA3DA)
          ),
        'Investimentos' => (Icons.trending_up, const Color(0xFF8FAFD4)),
        'Poupança' => (Icons.savings_outlined, SomiaColors.green),
        _ => (Icons.account_balance_outlined, SomiaColors.yellow),
      };

  @override
  Widget build(BuildContext context) {
    final totals = <String, int>{};
    for (final account in currency.accounts) {
      totals.update(
          _label(account.typeLabel), (value) => value + account.currentMinor,
          ifAbsent: () => account.currentMinor);
    }
    final entries = totals.entries.toList()
      ..sort((a, b) {
        int rank(String name) =>
            _order.contains(name) ? _order.indexOf(name) : _order.length;
        final result = rank(a.key).compareTo(rank(b.key));
        return result == 0 ? a.key.compareTo(b.key) : result;
      });
    // A shared scale with headroom preserves relative amounts and visible tracks.
    final scale = entries.fold<int>(
            1, (value, entry) => math.max(value, entry.value.abs())) *
        1.5;
    return SummaryPanel(
      title: 'Saldo por tipo de conta',
      child: entries.isEmpty
          ? const Text('Nenhuma conta para mostrar.')
          : LayoutBuilder(builder: (context, constraints) {
              final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontSize: constraints.maxWidth < 500 ? 12 : 14,
                  color: const Color(0xFFCED4DC),
                  fontWeight: FontWeight.w400);
              final scaler = MediaQuery.textScalerOf(context);
              double measure(String value) => (TextPainter(
                      text: TextSpan(text: value, style: style),
                      textScaler: scaler,
                      textDirection: Directionality.of(context))
                    ..layout())
                  .width;
              final labelWidth =
                  entries.map((e) => measure(e.key)).reduce(math.max);
              final amountWidth = entries
                  .map((e) => measure(_money(e.value, currency.currencyCode)))
                  .reduce(math.max);
              final compact =
                  constraints.maxWidth < labelWidth + amountWidth + 108;
              return Column(children: [
                for (final entry in entries)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                          label:
                              '${entry.key}: ${_money(entry.value, currency.currencyCode)}',
                          child: ExcludeSemantics(
                              child: Builder(builder: (context) {
                            final (icon, color) = _appearance(entry.key);
                            final negative = entry.value < 0;
                            final amount = Text(
                                _money(entry.value, currency.currencyCode),
                                textAlign: TextAlign.right,
                                style: style.copyWith(
                                    color: negative
                                        ? SomiaColors.red
                                        : style.color));
                            final bar = Tooltip(
                                message:
                                    'Saldos efetivados de todas as contas deste tipo, inclusive as excluídas do saldo principal. ${currency.currencyCode}.',
                                child: LinearProgressIndicator(
                                    key: ValueKey(
                                        'account-type-bar-${entry.key}'),
                                    value: entry.value.abs() / scale,
                                    minHeight:
                                        constraints.maxWidth < 500 ? 9 : 12,
                                    borderRadius: BorderRadius.circular(20),
                                    backgroundColor: const Color(0xFF303640),
                                    color: negative ? SomiaColors.red : color));
                            return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(icon,
                                      size:
                                          constraints.maxWidth < 500 ? 22 : 26,
                                      color: SomiaColors.blue),
                                  const SizedBox(width: 12),
                                  if (compact)
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                          Wrap(
                                              alignment:
                                                  WrapAlignment.spaceBetween,
                                              spacing: 12,
                                              runSpacing: 6,
                                              children: [
                                                Text(entry.key, style: style),
                                                amount
                                              ]),
                                          const SizedBox(height: 10),
                                          bar,
                                        ]))
                                  else ...[
                                    SizedBox(
                                        width: labelWidth + 12,
                                        child: Text(entry.key, style: style)),
                                    Expanded(child: bar),
                                    const SizedBox(width: 16),
                                    SizedBox(
                                        width: amountWidth + 1, child: amount),
                                  ],
                                ]);
                          })))),
              ]);
            }),
    );
  }
}
