import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/database/app_database.dart';
import '../../../core/di/injection.dart';
import '../../../core/filters/reference_month.dart';
import '../../../core/routing/somia_shell.dart';
import '../../../core/widgets/month_selector.dart';
import '../../../core/widgets/monetary_calculator.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../accounts/domain/money_minor.dart';
import '../../categories/domain/category.dart';
import '../../categories/domain/categories_repository.dart';
import '../data/planning_repository.dart';
import '../domain/planning.dart';

class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key});
  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage> {
  final repo = getIt<PlanningRepository>();
  List<BudgetLimit> budgets = [];
  List<PlanningGoal> goals = [];
  List<MonthlySpend> spending = [];
  bool loading = true, busy = false;
  Object? error;
  int generation = 0;
  StreamSubscription<void>? subscription;
  @override
  void initState() {
    super.initState();
    referenceMonth.addListener(load);
    if (getIt.isRegistered<AppDatabase>()) {
      subscription =
          getIt<AppDatabase>().financialChanges.listen((_) => load());
    }
    load();
  }

  @override
  void dispose() {
    referenceMonth.removeListener(load);
    subscription?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    final request = ++generation, period = referenceMonth.value;
    try {
      final b = await repo.budgets(period),
          g = await repo.goals(),
          s = await repo.spending(period);
      if (mounted && request == generation) {
        setState(() {
          budgets = b;
          goals = g;
          spending = s;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && request == generation) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  Future<void> act(Future<void> Function() action) async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    try {
      await action();
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e is FormatException ? e.message : '$e')));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<bool> confirm(String text) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Confirmar exclusão'),
                  content: Text(text),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Excluir'))
                  ])) ??
      false;
  Future<void> budgetForm([BudgetLimit? current]) async {
    final period = referenceMonth.value;
    final categories = await getIt<CategoriesRepository>().list();
    final accounts = await getIt<AccountsRepository>().list();
    if (!mounted) {
      return;
    }
    final draft = await showMovementForm<(String, String, int)>(
        context,
        (_) => BudgetForm(
            categories: categories,
            currencies: {'BRL', ...accounts.map((a) => a.currencyCode)},
            current: current,
            period: period));
    if (draft != null) {
      await act(() => repo.saveBudget(period, draft.$1, draft.$2, draft.$3,
          id: current?.id));
    }
  }

  Future<void> goalForm(String kind, [PlanningGoal? current]) async {
    final accounts = await getIt<AccountsRepository>().list();
    final categories = await getIt<CategoriesRepository>().list();
    if (!mounted) {
      return;
    }
    final draft = await showMovementForm<GoalDraft>(
        context,
        (_) => GoalForm(
            kind: kind,
            accounts: accounts,
            categories: categories,
            current: current));
    if (draft != null) {
      await act(() async {
        await repo.saveGoal(draft, id: current?.id);
      });
    }
  }

  String money(int n, String code) => MoneyMinor.display(n, code);
  Widget progress(int amount, int target) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LinearProgressIndicator(
          value: target <= 0 ? 0 : (amount / target).clamp(0.0, 1.0)));
  Widget budgetCard(BudgetLimit b) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(b.name,
                      style: Theme.of(context).textTheme.titleMedium)),
              PopupMenuButton<String>(
                  enabled: !busy,
                  onSelected: (v) => v == 'edit'
                      ? budgetForm(b)
                      : act(() async {
                          if (await confirm(
                              'Excluir o limite deste mês? Os lançamentos serão mantidos.')) {
                            await repo.deleteBudget(b.id);
                          }
                        }),
                  itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Editar')),
                        PopupMenuItem(value: 'delete', child: Text('Excluir'))
                      ])
            ]),
            Text('Limite: ${money(b.amount, b.currency)}'),
            progress(b.realized, b.amount),
            Text('Realizado: ${money(b.realized, b.currency)}'),
            Text('Previsto total: ${money(b.projected, b.currency)}'),
            Text(
                'Disponível no previsto: ${money(b.amount - b.projected, b.currency)}'),
            if (b.projected > b.amount)
              Text('O previsto ultrapassa o limite.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error))
            else if (b.projected * 100 >= b.amount * 80)
              const Text('Atenção: previsto a partir de 80% do limite.'),
          ])));
  Widget goalCard(PlanningGoal g) {
    final left = math.max(0, g.target - g.saved), today = DateTime.now();
    final months = g.deadline == null
        ? 0
        : math.max(
            1,
            (g.deadline!.year - today.year) * 12 +
                g.deadline!.month -
                today.month +
                1);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text('${g.name}${g.archived ? ' · arquivada' : ''}',
                        style: Theme.of(context).textTheme.titleMedium)),
                PopupMenuButton<String>(
                    enabled: !busy,
                    onSelected: (v) => v == 'edit'
                        ? goalForm(g.kind, g)
                        : act(() async {
                            if (v == 'archive') {
                              await repo.archiveGoal(g);
                            } else if (await confirm(
                                'Excluir esta meta? O dinheiro permanece nas contas.')) {
                              await repo.deleteGoal(g.id);
                            }
                          }),
                    itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit', child: Text('Editar')),
                          PopupMenuItem(
                              value: 'archive',
                              child:
                                  Text(g.archived ? 'Reativar' : 'Arquivar')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Excluir'))
                        ])
              ]),
              Text('Saldo atual vinculado: ${money(g.saved, g.currency)}'),
              Text('Objetivo: ${money(g.target, g.currency)}'),
              progress(g.saved, g.target),
              if (g.kind == 'reserve')
                Text(
                    '${g.months} meses × ${money(g.monthlyEssential, g.currency)} de gastos essenciais médios.'),
              if (g.kind == 'reserve' && g.target == 0)
                const Text(
                    'Sem base de gastos essenciais nos três meses completos anteriores. Revise as categorias e o histórico.'),
              if (g.target > 0)
                Text(left == 0
                    ? 'Objetivo alcançado'
                    : 'Faltam ${money(left, g.currency)}'),
              if (g.deadline != null)
                Text(
                    'Prazo: ${g.deadline!.day}/${g.deadline!.month}/${g.deadline!.year}'),
              if (!g.archived && g.deadline != null && left > 0)
                Text(g.deadline!
                        .isBefore(DateTime(today.year, today.month, today.day))
                    ? 'Prazo vencido. Revise a meta.'
                    : 'Referência mensal até o prazo: ${money((left + months - 1) ~/ months, g.currency)}'),
            ])));
  }

  Widget indicators() {
    final codes = spending.map((s) => s.currency).toSet().toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Renda e saúde financeira', style: TextStyle(fontSize: 20)),
      const SizedBox(height: 8),
      const Text(
          'Indicadores do mês selecionado. Poupança = receita menos despesa; não representa aportes em investimentos.'),
      if (codes.isEmpty)
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sem movimentos neste mês.')),
      for (final code in codes)
        Builder(builder: (context) {
          final rows = spending.where((s) => s.currency == code);
          final income = rows
                  .where((s) => s.type == 'income')
                  .fold<int>(0, (v, s) => v + s.realized),
              expense = rows
                  .where((s) => s.type == 'expense')
                  .fold<int>(0, (v, s) => v + s.realized);
          final pi = rows
                  .where((s) => s.type == 'income')
                  .fold<int>(0, (v, s) => v + s.projected),
              pe = rows
                  .where((s) => s.type == 'expense')
                  .fold<int>(0, (v, s) => v + s.projected);
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Receita realizada: ${money(income, code)}'),
                        Text('Despesa realizada: ${money(expense, code)}'),
                        Text(
                            'Resultado realizado: ${money(income - expense, code)}'),
                        Text(
                            'Taxa de poupança: ${income <= 0 ? 'indisponível sem renda positiva' : '${((income - expense) * 100 / income).toStringAsFixed(1)}%'}'),
                        Text('Resultado previsto: ${money(pi - pe, code)}'),
                        Text(pi - pe < 0
                            ? 'Alerta: despesas previstas superam as receitas. Revise os limites ou os gastos.'
                            : income <= 0
                                ? 'Registre renda para acompanhar a taxa de poupança.'
                                : 'Compare a sobra com suas metas e mantenha uma reserva para imprevistos.'),
                      ])));
        }),
      const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
              'Transferir dinheiro entre contas não aumenta renda nem poupança. Compras do cartão entram no mês da fatura; pagar a fatura não repete a despesa. Reembolsos permanecem receitas separadas.')),
    ]);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 3,
      child: Scaffold(
          appBar: AppBar(
              leading: somiaMenuLeading(context),
              title: const Text('Planejamento'),
              bottom: const TabBar(tabs: [
                Tab(text: 'Orçamentos'),
                Tab(text: 'Metas'),
                Tab(text: 'Indicadores')
              ])),
          body: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? Center(
                      child: TextButton(
                          onPressed: load,
                          child: const Text('Tentar carregar novamente')))
                  : Column(children: [
                      Padding(
                          padding: const EdgeInsets.all(12),
                          child: MonthSelector(
                              month: referenceMonth.value,
                              onChanged: referenceMonth.select)),
                      Expanded(
                          child: TabBarView(children: [
                        RefreshIndicator(
                            onRefresh: load,
                            child: ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                children: [
                                  Wrap(spacing: 8, children: [
                                    FilledButton.icon(
                                        onPressed:
                                            busy ? null : () => budgetForm(),
                                        icon: const Icon(Icons.add),
                                        label: const Text('Novo limite')),
                                    TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => act(() => repo.copyPrevious(
                                                referenceMonth.value)),
                                        child:
                                            const Text('Copiar mês anterior'))
                                  ]),
                                  const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 12),
                                      child: Text(
                                          'Limites independentes por mês. Previsto total inclui o realizado e os lançamentos pendentes. Categoria principal já inclui suas subcategorias.')),
                                  if (budgets.isEmpty)
                                    const Padding(
                                        padding: EdgeInsets.all(20),
                                        child: Text(
                                            'Nenhum limite neste mês. Adicione uma categoria para começar.')),
                                  ...budgets.map(budgetCard),
                                ])),
                        RefreshIndicator(
                            onRefresh: load,
                            child: ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                children: [
                                  Wrap(spacing: 8, children: [
                                    FilledButton.icon(
                                        onPressed: busy
                                            ? null
                                            : () => goalForm('goal'),
                                        icon: const Icon(Icons.add),
                                        label: const Text('Nova meta')),
                                    TextButton.icon(
                                        onPressed: busy
                                            ? null
                                            : () => goalForm('reserve'),
                                        icon:
                                            const Icon(Icons.savings_outlined),
                                        label:
                                            const Text('Reserva de emergência'))
                                  ]),
                                  const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 12),
                                      child: Text(
                                          'Progresso pelo saldo atual das contas vinculadas, independente do mês selecionado. Vincular não transfere ou bloqueia dinheiro. Use contas separadas para cada meta.')),
                                  if (goals.isEmpty)
                                    const Padding(
                                        padding: EdgeInsets.all(20),
                                        child: Text(
                                            'Crie sua primeira meta ou reserva.')),
                                  ...goals.map(goalCard),
                                ])),
                        RefreshIndicator(
                            onRefresh: load,
                            child: ListView(
                                padding: const EdgeInsets.all(16),
                                children: [indicators()])),
                      ])),
                    ])));
}

class BudgetForm extends StatefulWidget {
  const BudgetForm(
      {super.key,
      required this.categories,
      required this.currencies,
      required this.period,
      this.current});
  final List<FinanceCategory> categories;
  final Set<String> currencies;
  final DateTime period;
  final BudgetLimit? current;
  @override
  State<BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends State<BudgetForm> {
  final key = GlobalKey<FormState>();
  late String? category = widget.current?.categoryId;
  late String currency = widget.current?.currency ?? 'BRL';
  late final amount = TextEditingController(
      text: MoneyMinor.plain(widget.current?.amount ?? 0));
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      value: () => (category, currency, amount.text),
      builder: (context, cancel) => MovementFormFrame(
          title: 'Limite mensal',
          saveLabel: 'Salvar limite',
          compact: true,
          onCancel: cancel,
          onSave: () {
            if (key.currentState!.validate()) {
              Navigator.pop(context,
                  (category!, currency, MoneyMinor.parse(amount.text)));
            }
          },
          child: Form(
              key: key,
              child: Column(children: [
                Text(
                    '${monthNames[widget.period.month - 1]} ${widget.period.year}'),
                DropdownButtonFormField<String>(
                    initialValue: category,
                    isExpanded: true,
                    menuMaxHeight: 280,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: widget.categories
                        .where((c) =>
                            c.type == CategoryType.expense &&
                            (!c.isArchived || c.id == category))
                        .map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(
                                '${c.parentId == null ? '' : '↳ '}${c.name}',
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    validator: (v) => v == null ? 'Escolha a categoria.' : null,
                    onChanged: (v) => setState(() => category = v)),
                DropdownButtonFormField<String>(
                    initialValue: currency,
                    menuMaxHeight: 280,
                    decoration: const InputDecoration(labelText: 'Moeda'),
                    items: {currency, ...widget.currencies}
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => currency = v!)),
                MonetaryCalculatorField(
                    controller: amount,
                    currencyCode: currency,
                    labelText: 'Limite'),
              ]))));
}

class GoalForm extends StatefulWidget {
  const GoalForm(
      {super.key,
      required this.kind,
      required this.accounts,
      required this.categories,
      this.current});
  final String kind;
  final List<Account> accounts;
  final List<FinanceCategory> categories;
  final PlanningGoal? current;
  @override
  State<GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<GoalForm> {
  final key = GlobalKey<FormState>();
  late final name = TextEditingController(
      text: widget.current?.name ??
          (widget.kind == 'reserve' ? 'Reserva de emergência' : ''));
  late final amount = TextEditingController(
      text: MoneyMinor.plain(widget.current?.target ?? 0));
  late String currency = widget.current?.currency ?? 'BRL';
  late int months = widget.current?.months ?? 6;
  late DateTime? deadline = widget.current?.deadline;
  late final selected = widget.current?.accounts.toSet() ?? <String>{};
  late final essential = widget.current?.essential.toSet() ?? <String>{};
  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      value: () => (
            name.text,
            amount.text,
            currency,
            months,
            deadline,
            selected.join(','),
            essential.join(',')
          ),
      builder: (context, cancel) => MovementFormFrame(
          title: widget.kind == 'reserve' ? 'Reserva de emergência' : 'Meta',
          saveLabel: 'Salvar meta',
          compact: true,
          onCancel: cancel,
          onSave: () {
            if (!key.currentState!.validate()) {
              return;
            }
            if (selected.isEmpty ||
                (widget.kind == 'reserve' && essential.isEmpty)) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Selecione contas e, na reserva, categorias essenciais.')));
              return;
            }
            Navigator.pop(
                context,
                GoalDraft(
                    name: name.text,
                    kind: widget.kind,
                    currency: currency,
                    target: widget.kind == 'reserve'
                        ? 0
                        : MoneyMinor.parse(amount.text),
                    accounts: selected.toList(),
                    essential: essential.toList(),
                    months: months,
                    deadline: deadline));
          },
          child: Form(
              key: key,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                        controller: name,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Nome'),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Informe o nome.'
                            : null),
                    DropdownButtonFormField<String>(
                        initialValue: currency,
                        menuMaxHeight: 280,
                        decoration: const InputDecoration(labelText: 'Moeda'),
                        items: {
                          currency,
                          'BRL',
                          ...widget.accounts.map((a) => a.currencyCode)
                        }
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) => setState(() {
                              currency = v!;
                              selected.clear();
                            })),
                    if (widget.kind == 'goal')
                      MonetaryCalculatorField(
                          controller: amount,
                          currencyCode: currency,
                          labelText: 'Valor objetivo'),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Prazo (opcional)'),
                        subtitle: Text(deadline == null
                            ? 'Sem prazo'
                            : '${deadline!.day}/${deadline!.month}/${deadline!.year}'),
                        trailing: deadline == null
                            ? const Icon(Icons.calendar_today)
                            : IconButton(
                                tooltip: 'Remover prazo',
                                onPressed: () =>
                                    setState(() => deadline = null),
                                icon: const Icon(Icons.close)),
                        onTap: () async {
                          final date = await showDatePicker(
                              context: context,
                              initialDate: deadline ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100, 12, 31));
                          if (date != null && mounted) {
                            setState(() => deadline = date);
                          }
                        }),
                    if (widget.kind == 'reserve') ...[
                      DropdownButtonFormField<int>(
                          initialValue: months,
                          menuMaxHeight: 280,
                          decoration: const InputDecoration(
                              labelText: 'Meses de cobertura'),
                          items: List.generate(
                              36,
                              (i) => DropdownMenuItem(
                                  value: i + 1, child: Text('${i + 1} meses'))),
                          onChanged: (v) => setState(() => months = v!)),
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                              'Base: média dos gastos essenciais realizados nos três meses completos anteriores, incluindo meses sem gastos.')),
                      ExpansionTile(
                          title: Text(
                              'Categorias essenciais (${essential.length})'),
                          children: widget.categories
                              .where((c) =>
                                  c.type == CategoryType.expense &&
                                  (!c.isArchived || essential.contains(c.id)))
                              .map((c) => CheckboxListTile(
                                  title: Text(
                                      '${c.parentId == null ? '' : '↳ '}${c.name}'),
                                  value: essential.contains(c.id),
                                  onChanged: (v) => setState(() {
                                        if (v == true) {
                                          essential.removeWhere((id) =>
                                              id == c.parentId ||
                                              widget.categories.any((x) =>
                                                  x.id == id &&
                                                  x.parentId == c.id));
                                          essential.add(c.id);
                                        } else {
                                          essential.remove(c.id);
                                        }
                                      })))
                              .toList()),
                    ],
                    ExpansionTile(
                        title: Text('Contas vinculadas (${selected.length})'),
                        initiallyExpanded: true,
                        children: widget.accounts
                            .where((a) =>
                                a.currencyCode == currency &&
                                (!a.isArchived || selected.contains(a.id)))
                            .map((a) => CheckboxListTile(
                                title: Text(a.name),
                                subtitle: Text(MoneyMinor.display(
                                    a.currentBalanceMinor, currency)),
                                value: selected.contains(a.id),
                                onChanged: (v) => setState(() => v == true
                                    ? selected.add(a.id)
                                    : selected.remove(a.id))))
                            .toList()),
                    const Text(
                        'Uma conta por meta ativa. Seu saldo continua pertencendo à conta e ao patrimônio.'),
                  ]))));
}
