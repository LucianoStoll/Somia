import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../accounts/domain/money_minor.dart';
import '../../../core/routing/somia_shell.dart';
import '../../../core/widgets/monetary_calculator.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../categories/domain/category.dart';
import '../../categories/domain/categories_repository.dart';
import '../data/reimbursements_repository.dart';
import '../domain/reimbursement.dart';
import 'reimbursement_editor.dart';

class ReimbursementsPage extends StatefulWidget {
  const ReimbursementsPage({super.key});
  @override
  State<ReimbursementsPage> createState() => _ReimbursementsPageState();
}

class _ReimbursementsPageState extends State<ReimbursementsPage> {
  final repo = getIt<ReimbursementsRepository>();
  List<Person> people = [];
  List<Reimbursement> claims = [];
  String? personId;
  String search = '';
  bool loading = true, busy = false;
  Object? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final p = await repo.people(), c = await repo.load();
      if (mounted) {
        setState(() {
          people = p;
          claims = c;
          loading = false;
          error = null;
          if (!p.any((p) => p.id == personId)) personId = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  Future<void> act(Future<void> Function() fn) async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    try {
      await fn();
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

  String money(int amount, String currency) =>
      MoneyMinor.display(amount, currency);
  Future<void> receive(Reimbursement r) async {
    final accounts = (await getIt<AccountsRepository>().list())
        .where((a) => !a.isArchived && a.currencyCode == r.currency)
        .toList();
    final categories = (await getIt<CategoriesRepository>().list())
        .where((c) => !c.isArchived && c.type == CategoryType.income)
        .toList();
    if (!mounted) {
      return;
    }
    final draft = await showMovementForm<_ReceiptDraft>(
        context,
        (_) =>
            _ReceiptForm(claim: r, accounts: accounts, categories: categories));
    if (draft == null) {
      return;
    }
    await act(() => repo.receive(r,
        amount: draft.amount,
        accountId: draft.account,
        date: draft.date,
        categoryId: draft.category,
        effective: draft.effective));
  }

  Future<void> link(Reimbursement r) async {
    final rows = await repo.eligibleIncome(r);
    if (!mounted) {
      return;
    }
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Nenhuma receita disponível nesta moeda e dentro do valor restante.')));
      return;
    }
    final id = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Vincular receita existente'),
                content: SizedBox(
                    width: 480,
                    height: 280,
                    child: ListView(
                        children: rows
                            .map((row) => ListTile(
                                title: Text(row.read<String>('description')),
                                subtitle: Text(money(
                                    row.read<int>('planned_amount_minor'),
                                    r.currency)),
                                onTap: () => Navigator.pop(
                                    context, row.read<String>('id'))))
                            .toList())),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'))
                ]));
    if (id != null) {
      await act(() => repo.link(r.id, id));
    }
  }

  Future<void> merge(Person source) async {
    final target = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Mesclar pessoa'),
                content: SizedBox(
                    width: 480,
                    height: 280,
                    child: ListView(
                        children: people
                            .where((p) => p.id != source.id && !p.archived)
                            .map((p) => ListTile(
                                title: Text(p.name),
                                onTap: () => Navigator.pop(context, p.id)))
                            .toList())),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'))
                ]));
    if (target == null || !mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Unir os históricos?'),
                content: Text(
                    'Os vínculos de ${source.name} passarão para a pessoa escolhida. O nome anterior será mantido como outro nome.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Mesclar'))
                ]));
    if (confirmed == true) {
      await act(() => repo.mergePeople(source.id, target));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = claims
        .where((r) => personId == null || r.personId == personId)
        .toList();
    return Scaffold(
        appBar: AppBar(
            leading: somiaMenuLeading(context),
            title: const Text('Pessoas e reembolsos')),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: busy
                ? null
                : () => act(() async {
                      await editPerson(context, repo);
                    }),
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Nova pessoa')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(
                    child: TextButton(
                        onPressed: load,
                        child: const Text('Tentar carregar novamente')))
                : RefreshIndicator(
                    onRefresh: load,
                    child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        children: [
                          TextField(
                              decoration: const InputDecoration(
                                  labelText: 'Buscar pessoa'),
                              onChanged: (s) =>
                                  setState(() => search = s.toLowerCase())),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                              key: ValueKey(personId),
                              initialValue: personId ?? '',
                              isExpanded: true,
                              menuMaxHeight: 280,
                              itemHeight: 48,
                              decoration: const InputDecoration(
                                  labelText: 'Histórico de'),
                              items: [
                                const DropdownMenuItem(
                                    value: '', child: Text('Todas as pessoas')),
                                for (final p in people)
                                  DropdownMenuItem(
                                      value: p.id,
                                      child: Text(
                                          '${p.name}${p.archived ? ' (arquivada)' : ''}',
                                          overflow: TextOverflow.ellipsis))
                              ],
                              onChanged: (v) => setState(() => personId =
                                  v == null || v.isEmpty ? null : v)),
                          for (final p in people.where((p) =>
                              '${p.name} ${p.aliases}'
                                  .toLowerCase()
                                  .contains(search) &&
                              (personId == null || p.id == personId)))
                            ListTile(
                                leading: const Icon(Icons.person_outline),
                                title: Text(p.name),
                                subtitle: p.archived
                                    ? const Text(
                                        'Arquivada · histórico preservado')
                                    : null,
                                onTap: () => setState(() => personId = p.id),
                                trailing: PopupMenuButton<String>(
                                    enabled: !busy,
                                    onSelected: (s) => s == 'merge'
                                        ? merge(p)
                                        : act(() async {
                                            if (s == 'edit') {
                                              await editPerson(context, repo,
                                                  person: p);
                                            } else {
                                              await repo.archivePerson(p);
                                            }
                                          }),
                                    itemBuilder: (_) => [
                                          const PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Editar')),
                                          PopupMenuItem(
                                              value: 'archive',
                                              child: Text(p.archived
                                                  ? 'Reativar'
                                                  : 'Arquivar')),
                                          const PopupMenuItem(
                                              value: 'merge',
                                              child: Text('Mesclar'))
                                        ])),
                          const Divider(),
                          if (filtered.isEmpty)
                            const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                    'Adicione um reembolso em Mais opções da despesa.')),
                          for (final r in filtered)
                            Card(
                                child: ExpansionTile(
                                    title: Text(
                                        '${r.personName} · ${r.description}'),
                                    subtitle: Text(
                                        'A receber: ${money(r.pending, r.currency)}'),
                                    childrenPadding: const EdgeInsets.all(12),
                                    children: [
                                  Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                          'Combinado: ${money(r.amountMinor, r.currency)}\nRecebido: ${money(r.received, r.currency)}\nPendente/agendado: ${money(r.scheduled, r.currency)}')),
                                  if (r.available > 0)
                                    Wrap(spacing: 8, children: [
                                      TextButton.icon(
                                          onPressed:
                                              busy ? null : () => receive(r),
                                          icon: const Icon(
                                              Icons.add_circle_outline),
                                          label: const Text(
                                              'Registrar recebimento')),
                                      TextButton(
                                          onPressed:
                                              busy ? null : () => link(r),
                                          child: const Text(
                                              'Vincular receita existente'))
                                    ]),
                                  for (final receipt in r.receipts)
                                    ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(money(
                                            receipt.amountMinor, r.currency)),
                                        subtitle: Text(
                                            '${receipt.date.day}/${receipt.date.month}/${receipt.date.year} · ${receipt.deleted ? 'Excluída' : receipt.effective ? 'Recebida' : 'Pendente/agendada'}'),
                                        trailing: IconButton(
                                            tooltip:
                                                'Desvincular, mantendo a receita',
                                            icon: const Icon(Icons.link_off),
                                            onPressed: busy
                                                ? null
                                                : () => act(() =>
                                                    repo.unlink(receipt.id)))),
                                ])),
                        ])));
  }
}

class _ReceiptDraft {
  const _ReceiptDraft(
      this.amount, this.account, this.date, this.effective, this.category);
  final int amount;
  final String account;
  final DateTime date;
  final bool effective;
  final String? category;
}

class _ReceiptForm extends StatefulWidget {
  const _ReceiptForm(
      {required this.claim, required this.accounts, required this.categories});
  final Reimbursement claim;
  final List<Account> accounts;
  final List<FinanceCategory> categories;
  @override
  State<_ReceiptForm> createState() => _ReceiptFormState();
}

class _ReceiptFormState extends State<_ReceiptForm> {
  final key = GlobalKey<FormState>();
  late final amount =
      TextEditingController(text: MoneyMinor.plain(widget.claim.available));
  late String? account = widget.accounts.firstOrNull?.id;
  String? category;
  DateTime date = DateTime.now();
  bool effective = true;
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      value: () => (amount.text, account, category, date, effective),
      builder: (context, cancel) => MovementFormFrame(
          title: 'Receber reembolso',
          saveLabel: 'Salvar recebimento',
          compact: true,
          onCancel: cancel,
          onSave: () {
            if (!key.currentState!.validate()) {
              return;
            }
            if (MoneyMinor.parse(amount.text) > widget.claim.available) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('O valor supera o reembolso disponível.')));
              return;
            }
            Navigator.pop(
                context,
                _ReceiptDraft(MoneyMinor.parse(amount.text), account!, date,
                    effective, category));
          },
          child: Form(
              key: key,
              child: Column(children: [
                Text(
                    '${widget.claim.personName} · ${widget.claim.description}'),
                MonetaryCalculatorField(
                    controller: amount, currencyCode: widget.claim.currency),
                DropdownButtonFormField<String>(
                    initialValue: account,
                    isExpanded: true,
                    menuMaxHeight: 280,
                    decoration: const InputDecoration(
                        labelText: 'Conta de recebimento'),
                    items: widget.accounts
                        .map((a) => DropdownMenuItem(
                            value: a.id,
                            child:
                                Text(a.name, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    validator: (v) => v == null ? 'Selecione uma conta.' : null,
                    onChanged: (v) => setState(() => account = v)),
                DropdownButtonFormField<String>(
                    initialValue: '',
                    isExpanded: true,
                    menuMaxHeight: 280,
                    decoration: const InputDecoration(
                        labelText: 'Categoria de receita'),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('Sem categoria')),
                      for (final c in widget.categories)
                        DropdownMenuItem(
                            value: c.id,
                            child:
                                Text(c.name, overflow: TextOverflow.ellipsis))
                    ],
                    onChanged: (v) => setState(
                        () => category = v == null || v.isEmpty ? null : v)),
                ListTile(
                    title: const Text('Data do recebimento'),
                    subtitle: Text('${date.day}/${date.month}/${date.year}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100, 12, 31));
                      if (picked != null && mounted) {
                        setState(() => date = picked);
                      }
                    }),
                SwitchListTile(
                    title: const Text('Recebido'),
                    value: effective,
                    onChanged: (v) => setState(() => effective = v))
              ]))));
}
