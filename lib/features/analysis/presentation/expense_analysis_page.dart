import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/filters/reference_month.dart';
import '../../../core/routing/somia_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/month_selector.dart';
import '../../accounts/domain/money_minor.dart';
import '../data/expense_analysis_repository.dart';
import '../domain/expense_analysis.dart';

class ExpenseAnalysisPage extends StatefulWidget {
  const ExpenseAnalysisPage({super.key});
  @override
  State<ExpenseAnalysisPage> createState() => _ExpenseAnalysisPageState();
}

class _ExpenseAnalysisPageState extends State<ExpenseAnalysisPage>
    with WidgetsBindingObserver {
  ExpenseAnalysis? data;
  String? error, currency;
  bool loading = true;
  int view = 0, request = 0;
  @override
  void initState() {
    super.initState();
    referenceMonth.addListener(load);
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    referenceMonth.removeListener(load);
    WidgetsBinding.instance.removeObserver(this);
    request++;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    final id = ++request;
    setState(() {
      loading = true;
      error = null;
      data = null;
    });
    try {
      final result =
          await getIt<ExpenseAnalysisRepository>().load(referenceMonth.value);
      if (!mounted || id != request) return;
      setState(() {
        data = result;
        loading = false;
        if (!result.currencies.contains(currency)) {
          currency = result.currencies.firstOrNull;
        }
      });
    } catch (_) {
      if (mounted && id == request) {
        setState(() {
          loading = false;
          error = 'Não foi possível carregar as análises.';
        });
      }
    }
  }

  String money(int value) => MoneyMinor.display(value, currency ?? 'BRL');
  String monthLabel(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Análises'),
          leading: somiaMenuLeading(context),
          actions: [
            IconButton(
                tooltip: 'Atualizar análises',
                onPressed: loading ? null : load,
                icon: const Icon(Icons.refresh))
          ]),
      body: RefreshIndicator(
          onRefresh: load,
          child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
              children: [
                Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              MonthSelector(
                                  month: referenceMonth.value,
                                  onChanged: referenceMonth.select),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<int>(
                                  initialValue: view,
                                  decoration: const InputDecoration(
                                      labelText: 'O que analisar'),
                                  isExpanded: true,
                                  items: const [
                                    DropdownMenuItem(
                                        value: 0,
                                        child: Text('Despesas por categoria')),
                                    DropdownMenuItem(
                                        value: 1,
                                        child: Text('Comparação mensal')),
                                    DropdownMenuItem(
                                        value: 2,
                                        child: Text('Compromissos futuros')),
                                    DropdownMenuItem(
                                        value: 3,
                                        child: Text('Saldo por tipo de conta'))
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => view = value);
                                    }
                                  }),
                              const SizedBox(height: 12),
                              if (loading)
                                const Center(
                                    child: Padding(
                                        padding: EdgeInsets.all(40),
                                        child: CircularProgressIndicator()))
                              else if (error != null)
                                Column(children: [
                                  Text(error!),
                                  TextButton(
                                      onPressed: load,
                                      child: const Text('Tentar novamente'))
                                ])
                              else if (data!.currencies.isEmpty)
                                const Text(
                                    'Cadastre contas e lançamentos para começar.')
                              else ...[
                                if (data!.currencies.length > 1)
                                  Wrap(spacing: 8, children: [
                                    for (final c in data!.currencies)
                                      ChoiceChip(
                                          label: Text(c),
                                          selected: currency == c,
                                          onSelected: (_) =>
                                              setState(() => currency = c))
                                  ]),
                                const SizedBox(height: 12),
                                switch (view) {
                                  0 => categories(),
                                  1 => comparison(),
                                  2 => future(),
                                  _ => balances()
                                },
                              ],
                            ])))
              ])));
  Widget panel(String title, String explanation, List<Widget> children) => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(explanation, style: const TextStyle(color: SomiaColors.muted)),
            const SizedBox(height: 18),
            ...children
          ])));
  Widget categories() {
    final rows =
        data!.comparisons(currency!).where((r) => r.current != 0).toList();
    final max = rows.fold<int>(1, (v, r) => math.max(v, r.current.abs()));
    final total = rows.fold<int>(0, (v, r) => v + r.current);
    return panel(
        'Despesas por categoria',
        'Efetivação ou vencimento; cartões pelo vencimento da fatura. Inclui previstos, rateios e estornos. Toque para ver subcategorias e lançamentos.',
        [
          Text('Total: ${money(total)}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (rows.isEmpty) const Text('Nenhuma despesa neste mês.'),
          for (final r in rows)
            AnalysisBar(
                label: r.category,
                value: r.current,
                maximum: max,
                formatted: money(r.current),
                detail: total > 0 && r.current >= 0
                    ? '${(r.current * 100 / total).toStringAsFixed(1)}% do total líquido'
                    : null,
                onTap: () => details(
                    r.category,
                    data!
                        .inMonth(currency!, data!.month)
                        .where((e) => e.category == r.category)
                        .toList(),
                    subcategories: true))
        ]);
  }

  Widget comparison() {
    final rows = data!.comparisons(currency!);
    final totals = (
      rows.fold<int>(0, (s, r) => s + r.current),
      rows.fold<int>(0, (s, r) => s + r.previous),
      data!.expenses
              .where((e) =>
                  e.currency == currency &&
                  (e.date.year != data!.month.year ||
                      e.date.month != data!.month.month))
              .fold<int>(0, (s, e) => s + e.amount) ~/
          3
    );
    final max = math.max(1,
        math.max(totals.$1.abs(), math.max(totals.$2.abs(), totals.$3.abs())));
    return panel(
        'Comparação mensal',
        'Mesma base das despesas por categoria. A média usa os três meses anteriores completos, incluindo meses sem lançamentos. Mês atual pode estar incompleto.',
        [
          AnalysisBar(
              label: 'Mês selecionado',
              value: totals.$1,
              maximum: max,
              formatted: money(totals.$1),
              onTap: () => details(
                  'Mês selecionado', data!.inMonth(currency!, data!.month))),
          AnalysisBar(
              label: 'Mês anterior',
              value: totals.$2,
              maximum: max,
              formatted: money(totals.$2),
              color: SomiaColors.purple,
              onTap: () => details(
                  'Mês anterior',
                  data!.inMonth(currency!,
                      DateTime(data!.month.year, data!.month.month - 1)))),
          AnalysisBar(
              label: 'Média dos 3 meses',
              value: totals.$3,
              maximum: max,
              formatted: money(totals.$3),
              color: SomiaColors.muted),
          const Divider(),
          if (rows.isEmpty)
            const Text('Nenhuma despesa nos quatro meses comparados.'),
          for (final r in rows)
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.category),
                subtitle: Text(
                    'Atual: ${money(r.current)} · Anterior: ${money(r.previous)}\nMédia: ${money(r.average)}\nVariação: ${r.difference > 0 ? '+' : ''}${money(r.difference)} · ${r.changePercent == null ? 'Sem base percentual' : '${r.changePercent! > 0 ? '+' : ''}${r.changePercent!.toStringAsFixed(1)}%'}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => details(
                    r.category,
                    data!.expenses
                        .where((e) =>
                            e.currency == currency && e.category == r.category)
                        .toList(),
                    subcategories: true)),
        ]);
  }

  Widget future() {
    final rows = data!.commitments[currency] ?? [];
    final max = rows.fold<int>(1, (v, r) => math.max(v, r.total));
    return panel(
        'Compromissos futuros',
        'Próximos 6 meses após o selecionado. Pendências existentes hoje: despesas ainda não pagas e encargos de cartão não liquidados, sem repetir pagamentos ou saldos antigos. Recorrências ainda não geradas não são estimadas.',
        [
          const Wrap(spacing: 16, children: [
            Text('● Despesas', style: TextStyle(color: SomiaColors.red)),
            Text('● Cartões', style: TextStyle(color: SomiaColors.blue))
          ]),
          const SizedBox(height: 12),
          if (rows.every((r) => r.total == 0))
            const Text('Nenhum compromisso cadastrado neste horizonte.'),
          for (final r in rows)
            Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                    onTap: () => details('Compromissos ${monthLabel(r.month)}',
                        [...r.expenses, ...r.cards]),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${monthLabel(r.month)} · ${money(r.total)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          LayoutBuilder(
                              builder: (context, box) => Row(children: [
                                    Container(
                                        height: 12,
                                        width:
                                            box.maxWidth * r.expenseTotal / max,
                                        color: SomiaColors.red),
                                    Container(
                                        height: 12,
                                        width: box.maxWidth * r.cardTotal / max,
                                        color: SomiaColors.blue)
                                  ])),
                          const SizedBox(height: 6),
                          Text(
                              'Despesas: ${money(r.expenseTotal)} · Cartões: ${money(r.cardTotal)}',
                              style: const TextStyle(color: SomiaColors.muted)),
                        ]))),
        ]);
  }

  Widget balances() {
    final values = data!.balances(currency!);
    final max = values.values.fold<int>(1, (v, a) => math.max(v, a.abs()));
    return panel(
        'Saldo por tipo de conta',
        'Saldo efetivado até o fim de ${monthLabel(data!.month)}. Todas as contas ativas, inclusive as excluídas do saldo do mês. Contas arquivadas ficam de fora. Aplicações entram somente pelo saldo da conta.',
        [
          Text(
              'Total das contas ativas: ${money(values.values.fold<int>(0, (s, v) => s + v))}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (values.isEmpty) const Text('Nenhuma conta ativa nesta moeda.'),
          for (final entry in values.entries)
            AnalysisBar(
                label: entry.key.label,
                value: entry.value,
                maximum: max,
                formatted: money(entry.value),
                signed: true,
                color: SomiaColors.green,
                onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => SafeArea(
                        child: SizedBox(
                            height: MediaQuery.sizeOf(context).height * .7,
                            child: ListView(
                                padding: const EdgeInsets.all(20),
                                children: [
                                  Text(entry.key.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  for (final a in data!.accounts.where((a) =>
                                      !a.isArchived &&
                                      a.currencyCode == currency &&
                                      a.type == entry.key))
                                    ListTile(
                                        title: Text(a.name),
                                        subtitle:
                                            Text(money(a.currentBalanceMinor))),
                                  TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Fechar')),
                                ]))))),
        ]);
  }

  void details(String title, List<AnalysisExpense> rows,
      {bool subcategories = false}) {
    final groups = <String, int>{};
    for (final e in rows) {
      groups.update(e.subcategory, (v) => v + e.amount,
          ifAbsent: () => e.amount);
    }
    final max = groups.values.fold<int>(1, (v, a) => math.max(v, a.abs()));
    rows.sort((a, b) => b.date.compareTo(a.date));
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .8,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Row(children: [
                    Expanded(
                        child: Text(title,
                            style: Theme.of(context).textTheme.titleLarge)),
                    IconButton(
                        tooltip: 'Fechar detalhes',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close))
                  ]),
                  Text(
                      'Total: ${money(rows.fold<int>(0, (s, e) => s + e.amount))}'),
                  const SizedBox(height: 12),
                  if (subcategories) ...[
                    for (final e in groups.entries)
                      AnalysisBar(
                          label: e.key,
                          value: e.value,
                          maximum: max,
                          formatted: money(e.value)),
                    const Divider()
                  ],
                  if (rows.isEmpty)
                    const Text('Nenhum lançamento neste período.'),
                  for (final e in rows)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.description),
                        subtitle: Text(
                            '${e.date.day.toString().padLeft(2, '0')}/${monthLabel(e.date)} · ${e.source}\n${e.category} · ${e.subcategory}'),
                        trailing: Text(money(e.amount)),
                        isThreeLine: true),
                ]))));
  }
}

class AnalysisBar extends StatelessWidget {
  const AnalysisBar(
      {super.key,
      required this.label,
      required this.value,
      required this.maximum,
      required this.formatted,
      this.detail,
      this.onTap,
      this.color = SomiaColors.blue,
      this.signed = false});
  final String label, formatted;
  final String? detail;
  final int value, maximum;
  final VoidCallback? onTap;
  final Color color;
  final bool signed;
  @override
  Widget build(BuildContext context) => Semantics(
      label: '$label: $formatted',
      button: onTap != null,
      child: InkWell(
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(label,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          Text(formatted)
                        ]),
                    const SizedBox(height: 6),
                    LayoutBuilder(builder: (context, box) {
                      final width = box.maxWidth *
                          (value.abs() / math.max(1, maximum)).clamp(0.0, 1.0) *
                          (signed ? 0.5 : 1);
                      return Container(
                          height: 12,
                          decoration: BoxDecoration(
                              color: SomiaColors.surfaceHigh,
                              borderRadius: BorderRadius.circular(4)),
                          child: Stack(children: [
                            if (signed)
                              Positioned(
                                  left: box.maxWidth / 2,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                      width: 1, color: SomiaColors.muted)),
                            Positioned(
                                left: signed
                                    ? (value < 0
                                        ? box.maxWidth / 2 - width
                                        : box.maxWidth / 2)
                                    : 0,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                    width: width,
                                    color:
                                        value < 0 ? SomiaColors.red : color)),
                          ]));
                    }),
                    if (detail != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(detail!,
                              style:
                                  const TextStyle(color: SomiaColors.muted))),
                  ]))));
}
