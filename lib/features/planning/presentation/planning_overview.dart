import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/month_selector.dart';
import '../../../core/widgets/module_surface.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/money_minor.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_visuals.dart';
import '../domain/planning.dart';

String _money(int amount, String code) => MoneyMinor.display(amount, code)
    .replaceAllMapped(RegExp(r'\d{1,3}(?=(\d{3})+,)'), (m) => '${m[0]}.');

class PlanningOverview extends StatefulWidget {
  const PlanningOverview(
      {super.key,
      required this.month,
      required this.accounts,
      required this.categories,
      required this.spending,
      required this.budgets,
      required this.onRefresh,
      required this.indicators});
  final DateTime month;
  final List<Account> accounts;
  final List<FinanceCategory> categories;
  final List<MonthlySpend> spending;
  final List<BudgetLimit> budgets;
  final Future<void> Function() onRefresh;
  final Widget indicators;
  @override
  State<PlanningOverview> createState() => _PlanningOverviewState();
}

class _PlanningOverviewState extends State<PlanningOverview> {
  String? currency;
  String type = 'expense';

  @override
  Widget build(BuildContext context) {
    final codes = <String>{
      ...widget.accounts.map((a) => a.currencyCode),
      ...widget.spending.map((s) => s.currency),
      ...widget.budgets.map((b) => b.currency),
    }.toList()
      ..sort();
    final code = codes.contains(currency)
        ? currency!
        : codes.contains('BRL')
            ? 'BRL'
            : codes.firstOrNull ?? 'BRL';
    final accounts = widget.accounts
        .where((a) => a.currencyCode == code && a.includeInBalance)
        .toList();
    final rows = widget.spending.where((s) => s.currency == code).toList();
    final income = rows
        .where((s) => s.type == 'income')
        .fold<int>(0, (sum, s) => sum + s.projected);
    final expense = rows
        .where((s) => s.type == 'expense')
        .fold<int>(0, (sum, s) => sum + s.projected);
    final total =
        accounts.fold<int>(0, (sum, a) => sum + a.projectedBalanceMinor);
    final warnings = widget.budgets
        .where((b) => b.currency == code && b.projected * 100 >= b.amount * 80)
        .toList()
      ..sort((a, b) {
        final ratio =
            (b.projected * a.amount).compareTo(a.projected * b.amount);
        return ratio != 0 ? ratio : a.name.compareTo(b.name);
      });
    Widget metric(String label, int value, Color color) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: SomiaColors.muted)),
          const SizedBox(height: 4),
          Text(_money(value, code),
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: color)),
        ]);
    return RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
            key: const PageStorageKey('planning-overview'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (codes.length > 1)
                Wrap(spacing: 8, children: [
                  for (final value in codes)
                    ChoiceChip(
                        label: Text(value),
                        selected: value == code,
                        onSelected: (_) => setState(() => currency = value)),
                ]),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                                'Saldo previsto em ${monthNames[widget.month.month - 1].toLowerCase()}',
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 10),
                            Text(_money(total, code),
                                key: const ValueKey('planning-forecast-total'),
                                style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w700,
                                    color: total < 0
                                        ? SomiaColors.red
                                        : SomiaColors.blue)),
                            const SizedBox(height: 4),
                            Text(
                                'Contas até ${DateTime(widget.month.year, widget.month.month + 1, 0).day}/${widget.month.month}/${widget.month.year}',
                                style: const TextStyle(
                                    fontSize: 12, color: SomiaColors.muted)),
                            ModuleDetails(
                                title: 'Ver contas (${accounts.length})',
                                children: [
                                  if (accounts.isEmpty)
                                    const Text(
                                        'Nenhuma conta incluída no saldo.'),
                                  for (final a in accounts)
                                    ModuleValueRow(
                                        label: a.name,
                                        value: _money(
                                            a.projectedBalanceMinor, code)),
                                ]),
                            const Divider(height: 20),
                            LayoutBuilder(builder: (context, box) {
                              final values = [
                                metric('Receitas previstas', income,
                                    SomiaColors.green),
                                metric('Despesas previstas', expense,
                                    SomiaColors.red),
                              ];
                              if (box.maxWidth < 280 ||
                                  MediaQuery.textScalerOf(context).scale(14) >
                                      19) {
                                return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      values[0],
                                      const SizedBox(height: 12),
                                      values[1]
                                    ]);
                              }
                              return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: values[0]),
                                    const SizedBox(width: 12),
                                    Expanded(child: values[1]),
                                  ]);
                            }),
                          ]))),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Por categoria',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 10),
                            SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(
                                      value: 'expense',
                                      label: Text('Despesas')),
                                  ButtonSegment(
                                      value: 'income', label: Text('Receitas')),
                                ],
                                selected: {
                                  type
                                },
                                showSelectedIcon: false,
                                onSelectionChanged: (value) =>
                                    setState(() => type = value.single)),
                            const SizedBox(height: 8),
                            const Text('Previsto no mês',
                                style: TextStyle(
                                    fontSize: 12, color: SomiaColors.muted)),
                            const SizedBox(height: 14),
                            PlanningCategoryChart(
                                spending:
                                    rows.where((s) => s.type == type).toList(),
                                categories: widget.categories,
                                currency: code,
                                label:
                                    type == 'income' ? 'Receitas' : 'Despesas'),
                          ]))),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              const Expanded(
                                  child: Text('Atenção aos limites',
                                      style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600))),
                              TextButton(
                                  onPressed: () =>
                                      DefaultTabController.of(context)
                                          .animateTo(1),
                                  child: const Text('Ver todos')),
                            ]),
                            if (warnings.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                      'Nenhum limite em atenção neste mês.',
                                      style:
                                          TextStyle(color: SomiaColors.muted))),
                            for (var i = 0;
                                i < math.min(3, warnings.length);
                                i++) ...[
                              if (i > 0) const Divider(height: 24),
                              _BudgetWarning(budget: warnings[i]),
                            ],
                          ]))),
              ModuleDetails(
                  title: 'Indicadores do mês', children: [widget.indicators]),
            ]));
  }
}

class _BudgetWarning extends StatelessWidget {
  const _BudgetWarning({required this.budget});
  final BudgetLimit budget;
  @override
  Widget build(BuildContext context) {
    final b = budget;
    final color = b.projected > b.amount ? SomiaColors.red : SomiaColors.yellow;
    final left = b.amount - b.projected;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
            child: Text(b.name,
                style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(width: 8),
        Text('${b.amount <= 0 ? 0 : (b.projected * 100 / b.amount).round()}%',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 8),
      LinearProgressIndicator(
          value: b.amount <= 0 ? 0 : (b.projected / b.amount).clamp(0.0, 1.0),
          color: color,
          minHeight: 6),
      const SizedBox(height: 8),
      Text(
          'Previsto ${_money(b.projected, b.currency)} de ${_money(b.amount, b.currency)}',
          style: const TextStyle(fontSize: 12, color: SomiaColors.muted)),
      const SizedBox(height: 4),
      Text(
          left < 0
              ? 'Excedido em ${_money(-left, b.currency)}'
              : 'Resta ${_money(left, b.currency)}',
          style: TextStyle(
              fontSize: 12,
              color: left < 0 ? SomiaColors.red : SomiaColors.muted)),
    ]);
  }
}

class PlanningCategoryChart extends StatelessWidget {
  const PlanningCategoryChart(
      {super.key,
      required this.spending,
      required this.categories,
      required this.currency,
      required this.label});
  final List<MonthlySpend> spending;
  final List<FinanceCategory> categories;
  final String currency, label;

  @override
  Widget build(BuildContext context) {
    final grouped = <String?, int>{};
    for (final row in spending) {
      final key = row.parentId ?? row.categoryId;
      grouped.update(key, (sum) => sum + row.projected,
          ifAbsent: () => row.projected);
    }
    final all = grouped.entries.where((e) => e.value != 0).map((entry) {
      final category = categories.where((c) => c.id == entry.key).firstOrNull;
      return _CategorySlice(
          category?.name ?? 'Sem categoria',
          entry.value,
          category == null
              ? SomiaColors.muted
              : categoryDisplayColor(category));
    }).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final positive = all.where((s) => s.amount > 0).toList();
    final credits = all.where((s) => s.amount < 0).toList();
    final total = positive.fold<int>(0, (sum, s) => sum + s.amount);
    final slices = positive.length <= 4
        ? positive
        : [
            ...positive.take(3),
            _CategorySlice(
                'Outras',
                positive.skip(3).fold<int>(0, (sum, s) => sum + s.amount),
                SomiaColors.muted),
          ];
    if (all.isEmpty) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
              'Nenhuma ${label == 'Receitas' ? 'receita' : 'despesa'} neste mês.',
              style: const TextStyle(color: SomiaColors.muted)));
    }
    void details() {
      showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (sheet) => SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('$label por categoria',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    for (final item in all)
                      ModuleValueRow(
                          label: item.name,
                          value: _money(item.amount, currency)),
                    TextButton(
                        onPressed: () => Navigator.pop(sheet),
                        child: const Text('Fechar')),
                  ])));
    }

    final legend =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final s in slices)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Container(
                  width: 9,
                  height: 9,
                  decoration:
                      BoxDecoration(color: s.color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(s.name, style: const TextStyle(fontSize: 12))),
              const SizedBox(width: 6),
              Text(_money(s.amount, currency),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ])),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (total > 0)
        LayoutBuilder(builder: (context, box) {
          final side = box.maxWidth >= 320 &&
              MediaQuery.textScalerOf(context).scale(12) <= 15;
          final diameter = side ? 140.0 : 176.0;
          final chart = Semantics(
              label: '$label: ${_money(total, currency)}',
              child: SizedBox(
                  width: diameter,
                  height: diameter,
                  child: CustomPaint(
                      painter: _CategoryRing(slices, total),
                      child: Center(
                          child: SizedBox(
                              width: diameter * .62,
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(label,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: SomiaColors.muted)),
                                    const SizedBox(height: 4),
                                    FittedBox(
                                        child: Text(_money(total, currency),
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600))),
                                  ]))))));
          return side
              ? Row(children: [
                  chart,
                  const SizedBox(width: 14),
                  Expanded(child: legend)
                ])
              : Column(children: [chart, const SizedBox(height: 12), legend]);
        }),
      if (credits.isNotEmpty) ...[
        const SizedBox(height: 8),
        for (final item in credits)
          ModuleValueRow(
              label: item.name, value: _money(item.amount, currency)),
        ModuleValueRow(
            label: 'Total líquido',
            value:
                _money(all.fold<int>(0, (sum, s) => sum + s.amount), currency)),
      ],
      Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed: details, child: const Text('Ver categorias'))),
    ]);
  }
}

class _CategorySlice {
  const _CategorySlice(this.name, this.amount, this.color);
  final String name;
  final int amount;
  final Color color;
}

class _CategoryRing extends CustomPainter {
  const _CategoryRing(this.slices, this.total);
  final List<_CategorySlice> slices;
  final int total;
  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final stroke = size.width * .16;
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    var start = -math.pi / 2;
    for (final s in slices) {
      final angle = s.amount * math.pi * 2 / total;
      canvas.drawArc(
          rect,
          start,
          angle,
          false,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke);
      start += angle;
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryRing oldDelegate) =>
      slices != oldDelegate.slices || total != oldDelegate.total;
}
