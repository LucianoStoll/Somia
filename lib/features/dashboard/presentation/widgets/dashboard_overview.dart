import '../../../../core/preferences/interface_preferences.dart';
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível lembrar esta escolha.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.somia;
    return Material(
      color: t.surface,
      clipBehavior: Clip.antiAlias,
      shape: somiaSurfaceShape(t),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: SomiaSpace.md,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Wrap(
                  spacing: SomiaSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (widget.action != null) widget.action!,
                    IconButton(
                      tooltip: collapsed ? 'Expandir bloco' : 'Recolher bloco',
                      onPressed: toggle,
                      visualDensity: VisualDensity.compact,
                      color: t.muted,
                      icon: Icon(
                          collapsed ? Icons.expand_more : Icons.expand_less),
                    ),
                  ],
                ),
              ],
            ),
            if (!collapsed) ...[
              const SizedBox(height: SomiaSpace.md),
              Padding(
                padding: const EdgeInsets.only(right: SomiaSpace.md),
                child: widget.child,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Forma das superfícies da direção Fluxo: sem borda no escuro, contorno
/// discreto no claro.
ShapeBorder somiaSurfaceShape(SomiaTokens t,
        [double radius = SomiaRadius.lg]) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: t.isDark ? BorderSide.none : BorderSide(color: t.outline),
    );

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
    final t = context.somia;
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final period = DateTime(widget.month.year, widget.month.month);
    final current = DateTime(now.year, now.month);
    String money(int value, [String sign = '']) =>
        hidden ? '••••' : '$sign${_money(value, c.currencyCode)}';
    Widget amount(String label, String value, Color color,
            {bool small = false}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(color: t.muted, fontSize: small ? 12 : 13)),
          const SizedBox(height: SomiaSpace.xs),
          FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: small ? 16 : 18,
                      fontWeight: FontWeight.w700))),
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
                  SizedBox(
                      height: 48,
                      child: VerticalDivider(width: 26, color: t.outline))
                else
                  const SizedBox(width: 10),
                Expanded(child: right),
              ]));
        });
    Widget pending(String title, String value, Color color, String route,
            String key) =>
        Material(
            color: t.surface,
            shape: somiaSurfaceShape(t, SomiaRadius.md),
            child: InkWell(
                key: ValueKey('dashboard-link-$route'),
                customBorder: somiaSurfaceShape(t, SomiaRadius.md),
                onTap: () => context.go(route),
                child: Padding(
                    key: ValueKey('mobile-$key-${c.currencyCode}'),
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            amount(title, value, color, small: true),
                            const SizedBox(height: SomiaSpace.sm),
                            Container(
                                height: 3,
                                width: 40,
                                decoration: BoxDecoration(
                                    color:
                                        key == 'income' ? t.income : t.expense,
                                    borderRadius: BorderRadius.circular(2))),
                          ])),
                      Icon(Icons.chevron_right, color: t.muted, size: 18),
                    ]))));
    final future = period.isAfter(current);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Material(
          color: t.surface,
          clipBehavior: Clip.antiAlias,
          shape: somiaSurfaceShape(t),
          child: BalanceDetailCard(
              currencyCode: c.currencyCode,
              child: Padding(
                  key: ValueKey('mobile-balance-${c.currencyCode}'),
                  padding: const EdgeInsets.fromLTRB(20, 14, 8, 20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(
                                  future
                                      ? 'Saldo previsto'
                                      : period.isBefore(current)
                                          ? 'Saldo efetivado no mês'
                                          : 'Saldo atual',
                                  style: text.bodyMedium
                                      ?.copyWith(color: t.muted))),
                          IconButton(
                              key: const ValueKey('summary-visibility'),
                              tooltip: hidden
                                  ? 'Mostrar valores do resumo'
                                  : 'Ocultar valores do resumo',
                              onPressed: () => setState(() => hidden = !hidden),
                              icon: Icon(
                                  hidden
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: t.muted)),
                        ]),
                        Padding(
                          padding: const EdgeInsets.only(right: SomiaSpace.md),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                                money(future
                                    ? c.projectedBalanceMinor
                                    : c.currentBalanceMinor),
                                style: text.displaySmall),
                          ),
                        ),
                        const SizedBox(height: SomiaSpace.sm),
                        Wrap(
                            spacing: SomiaSpace.sm,
                            runSpacing: SomiaSpace.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                      color: t.accent, shape: BoxShape.circle)),
                              Text('Previsto no fim do mês',
                                  style:
                                      TextStyle(color: t.muted, fontSize: 14)),
                              Text(money(c.projectedBalanceMinor),
                                  key: ValueKey(
                                      'desktop-projected-${c.currencyCode}'),
                                  style: TextStyle(
                                      color: t.accent,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ]),
                        Padding(
                          padding: const EdgeInsets.only(right: SomiaSpace.md),
                          child: Divider(height: 28, color: t.outline),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: SomiaSpace.md),
                          child: pair(
                              amount('Recebido no mês',
                                  money(d?.incomeMinor ?? 0, '+ '), t.income),
                              amount(
                                  'Pago no mês',
                                  money(
                                      (d?.expenseMinor ?? 0) +
                                          (d?.cardPaymentsMinor ?? 0),
                                      '− '),
                                  t.ink),
                              divider: true),
                        ),
                      ])))),
      const SizedBox(height: SomiaSpace.md),
      pair(
          pending('A receber', money(d?.pendingIncomeMinor ?? 0, '+ '),
              t.income, AppRoutes.incomePath, 'income'),
          pending(
              'A pagar',
              money(
                  (d?.pendingExpenseMinor ?? 0) +
                      (d?.pendingInvoicesMinor ?? 0),
                  '− '),
              t.ink,
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

  static const _months = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.somia;
    final code = widget.currency.currencyCode;
    final upcoming = widget.currency.upcoming;
    final total = upcoming.fold<int>(
        0,
        (sum, item) =>
            sum +
            (item.kind == 'income' ? item.amountMinor : -item.amountMinor));
    return SummaryPanel(
      title: 'Ainda este mês',
      action: upcoming.isEmpty
          ? null
          : Text(
              '${total >= 0 ? '+ ' : '− '}${_money(total.abs(), code)}',
              style: TextStyle(color: t.muted, fontSize: 13),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (upcoming.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Nenhum vencimento pendente.'),
            ),
          for (final item in widget.currency.upcoming.take(
            expanded ? widget.currency.upcoming.length : 3,
          ))
            InkWell(
              key: ValueKey('upcoming-open-${item.id}'),
              onTap: () => openDetails(item),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.outline)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: item.isOverdue(DateTime.now())
                            ? t.expense.withValues(alpha: 0.14)
                            : t.background,
                        borderRadius: BorderRadius.circular(SomiaRadius.sm),
                      ),
                      child: Column(
                        children: [
                          Text(
                            item.date.day.toString().padLeft(2, '0'),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            _months[item.date.month - 1],
                            style: TextStyle(fontSize: 11, color: t.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: SomiaSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: item.isOverdue(DateTime.now())
                                    ? 'Vencido, '
                                    : 'Pendente, ',
                                style: TextStyle(
                                  color: item.isOverdue(DateTime.now())
                                      ? t.expense
                                      : t.muted,
                                ),
                              ),
                              TextSpan(
                                text:
                                    '${item.kind == 'income' ? '+ ' : '− '}${_money(item.amountMinor, code)}',
                                style: TextStyle(
                                  color:
                                      item.kind == 'income' ? t.income : t.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ]),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (item.canSettle) ...[
                      const SizedBox(width: SomiaSpace.sm),
                      OutlinedButton(
                        onPressed: busy ? null : () => settle(item),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: t.accent,
                          side: BorderSide(color: t.accent),
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        child: const Text('Efetivar'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (upcoming.length > 3)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.outline)),
              ),
              child: TextButton(
                onPressed: () => setState(() => expanded = !expanded),
                child: Text(expanded ? 'Ver menos' : 'Ver todos'),
              ),
            ),
        ],
      ),
    );
  }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível lembrar esta escolha.')));
      }
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
                      style: TextStyle(color: SomiaColors.muted),
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
                                  style: TextStyle(
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
