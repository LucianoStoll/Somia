import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/routing/somia_shell.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../../core/widgets/monetary_calculator.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../accounts/domain/money_minor.dart';
import '../../accounts/presentation/account_identity.dart';
import '../../categories/domain/category.dart';
import '../../categories/domain/categories_repository.dart';
import '../data/cards_repository.dart';
import '../data/debit_cards_repository.dart';
import '../data/cashback_repository.dart';
import '../domain/cashback_calculator.dart';
import 'card_forms.dart';

class CashbackPage extends StatefulWidget {
  const CashbackPage({super.key, this.kind, this.cardId, this.receiptId});
  final String? kind, cardId, receiptId;
  @override
  State<CashbackPage> createState() => _CashbackPageState();
}

class _CashbackPageState extends State<CashbackPage> {
  CashbackRepository get repo => getIt<CashbackRepository>();
  List<CashbackReceipt> receipts = [];
  List<Account> accounts = [];
  List<FinanceCategory> categories = [];
  List<CardCashbackOption> cards = [];
  String? target, error;
  bool loading = true, acting = false, batch = false;
  final selected = <String>{};
  @override
  void initState() {
    super.initState();
    target = widget.cardId == null ? null : '${widget.kind}:${widget.cardId}';
    load();
  }

  Future<void> load() async {
    try {
      final credit = await getIt<CardsRepository>().list(),
          debit = await getIt<DebitCardsRepository>().list();
      final options = [
        for (final c in credit)
          CardCashbackOption('credit', c.id, c.name, c.paymentAccountId),
        for (final c in debit)
          CardCashbackOption('debit', c.id, c.name, c.accountId)
      ];
      final acc = await getIt<AccountsRepository>().list(),
          cat = await getIt<CategoriesRepository>().list();
      final active = options.where((c) => c.key == target).firstOrNull;
      final items = await repo.list(kind: active?.kind, cardId: active?.id);
      if (mounted)
        setState(() {
          cards = options;
          accounts = acc;
          categories = cat;
          receipts = items;
          loading = false;
          error = null;
          selected.clear();
          if (active == null) target = null;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          loading = false;
          error = e is StateError
              ? e.message
              : 'Não foi possível carregar o cashback.';
        });
    }
  }

  Future<void> settings() async {
    final card = cards.where((c) => c.key == target).firstOrNull;
    if (card == null) return;
    try {
      final current = await repo.settings(card.kind, card.id);
      if (!mounted) return;
      await showMovementForm<bool>(
          context,
          (_) => CashbackSettingsForm(
              card: card,
              accounts: accounts,
              categories: categories,
              current: current,
              repo: repo));
      if (mounted) await load();
    } catch (e) {
      if (mounted) cardError(context, e);
    }
  }

  Future<void> confirm(List<CashbackReceipt> chosen) async {
    if (chosen.isEmpty) return;
    if (chosen
        .any((r) => (r.kind == 'return') != (chosen.first.kind == 'return'))) {
      cardError(
          context,
          StateError(
              'Selecione recebimentos ou devoluções, em lotes separados.'));
      return;
    }
    await showMovementForm<bool>(
        context,
        (_) => CashbackConfirmationForm(
            receipts: chosen,
            accounts: accounts,
            categories: categories,
            repo: repo));
    if (mounted) await load();
  }

  Future<void> undo(CashbackReceipt receipt) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Desfazer confirmação?'),
                content: const Text(
                    'O lançamento voltará a previsto e os ajustes serão recalculados. Desfaça primeiro os ajustes mais recentes da compra.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Desfazer'))
                ]));
    if (ok != true) return;
    if (mounted) setState(() => acting = true);
    try {
      await repo.undo(receipt.id);
      await load();
    } catch (e) {
      if (mounted) cardError(context, e);
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = receipts
        .where((r) => r.confirmed == 0 && r.kind != 'return')
        .fold(0, (v, r) => v + r.amountMinor);
    final received = receipts.where((r) => r.confirmed != 0).fold(
        0, (v, r) => v + (r.kind == 'return' ? -r.amountMinor : r.amountMinor));
    return Scaffold(
        appBar: AppBar(
            title: const Text('Cashback'),
            leading: somiaMenuLeading(context),
            actions: [
              IconButton(
                  tooltip: 'Configurar cashback do cartão',
                  onPressed: target == null || loading ? null : settings,
                  icon: const Icon(Icons.tune)),
              IconButton(
                  tooltip: batch ? 'Cancelar seleção' : 'Confirmar em lote',
                  onPressed: () => setState(() {
                        batch = !batch;
                        selected.clear();
                      }),
                  icon: Icon(batch ? Icons.close : Icons.checklist))
            ]),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(
                    child: TextButton(
                        onPressed: load,
                        child: Text('$error Tentar novamente')))
                : RefreshIndicator(
                    onRefresh: load,
                    child:
                        ListView(padding: const EdgeInsets.all(16), children: [
                      DropdownButtonFormField<String>(
                          key: ValueKey(target),
                          initialValue: target,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Cartão'),
                          items: [
                            const DropdownMenuItem<String>(
                                value: null, child: Text('Todos os cartões')),
                            for (final card in cards)
                              DropdownMenuItem(
                                  value: card.key,
                                  child: Text(
                                      '${card.name} · ${card.kind == 'credit' ? 'Crédito' : 'Débito'}'))
                          ],
                          onChanged: (v) {
                            setState(() => target = v);
                            load();
                          }),
                      if (target != null)
                        TextButton.icon(
                            onPressed: settings,
                            icon: const Icon(Icons.settings_outlined),
                            label: const Text(
                                'Configurar regra, conta e categorias')),
                      Wrap(spacing: 16, runSpacing: 8, children: [
                        Text('Previsto: ${cardMoney(pending)}'),
                        Text('Recebido líquido: ${cardMoney(received)}')
                      ]),
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                              'Previsões não movimentam o saldo atual. Confirme o depósito ou a devolução pelo valor realmente ocorrido.')),
                      if (batch)
                        FilledButton(
                            onPressed: selected.isEmpty || acting
                                ? null
                                : () => confirm(receipts
                                    .where((r) => selected.contains(r.id))
                                    .toList()),
                            child: Text(
                                'Confirmar ${selected.length} selecionado(s)')),
                      if (receipts.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                                'Nenhum cashback. Selecione um cartão e configure sua regra. Compras geram previsão quando o primeiro pagamento for efetivado.')),
                      for (final r in receipts)
                        Card(
                            color: r.id == widget.receiptId
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            child: ListTile(
                                leading: batch && r.confirmed == 0
                                    ? Checkbox(
                                        value: selected.contains(r.id),
                                        onChanged: (v) => setState(() {
                                              if (v == true) {
                                                selected.add(r.id);
                                              } else {
                                                selected.remove(r.id);
                                              }
                                            }))
                                    : Icon(r.kind == 'return'
                                        ? Icons.undo
                                        : r.confirmed == 0
                                            ? Icons.schedule
                                            : Icons.check_circle_outline),
                                title: Text(r.description),
                                subtitle: Text(
                                    '${r.cardName}\n${r.confirmed == 0 ? (r.kind == 'return' ? 'Devolução prevista' : 'Previsto') : (r.kind == 'return' ? 'Devolvido' : 'Recebido')} · ${cardDateLabel(r.date)} · ${const {
                                          'forecast': 'Compra',
                                          'tier': 'Faixa maior',
                                          'cap': 'Redistribuição / teto',
                                          'refund': 'Estorno'
                                        }[r.reason] ?? 'Ajuste'}'),
                                isThreeLine: true,
                                trailing: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(cardMoney(r.amountMinor)),
                                      if (r.confirmed == 0)
                                        TextButton(
                                            onPressed: acting
                                                ? null
                                                : () => confirm([r]),
                                            child: const Text('Confirmar'))
                                      else
                                        TextButton(
                                            onPressed:
                                                acting ? null : () => undo(r),
                                            child: const Text('Desfazer'))
                                    ]))),
                    ])));
  }
}

class CardCashbackOption {
  const CardCashbackOption(this.kind, this.id, this.name, this.account);
  final String kind, id, name, account;
  String get key => '$kind:$id';
}

Widget cashbackCategoryPicker(List<FinanceCategory> categories, String type,
    String? value, ValueChanged<String?> changed, String label) {
  final available =
      categories.where((c) => c.type.name == type && !c.isArchived).toList();
  final selected = available.where((c) => c.id == value).firstOrNull;
  final root = selected?.parentId ?? selected?.id;
  final children = available.where((c) => c.parentId == root).toList();
  return Column(spacing: 12, children: [
    DropdownButtonFormField<String>(
        key: ValueKey('$label-$root'),
        initialValue: root,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem<String>(
              value: null, child: Text('Sem categoria')),
          for (final c in available.where((c) => c.parentId == null))
            DropdownMenuItem(value: c.id, child: Text(c.name))
        ],
        onChanged: changed),
    if (children.isNotEmpty)
      DropdownButtonFormField<String>(
          key: ValueKey('$label-sub-$value'),
          initialValue: selected?.parentId == null ? null : value,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Subcategoria'),
          items: [
            const DropdownMenuItem<String>(
                value: null, child: Text('Sem subcategoria')),
            for (final c in children)
              DropdownMenuItem(value: c.id, child: Text(c.name))
          ],
          onChanged: (v) => changed(v ?? root)),
  ]);
}

class CashbackSettingsForm extends StatefulWidget {
  const CashbackSettingsForm(
      {super.key,
      required this.card,
      required this.accounts,
      required this.categories,
      required this.repo,
      this.current});
  final CardCashbackOption card;
  final List<Account> accounts;
  final List<FinanceCategory> categories;
  final CashbackRepository repo;
  final CashbackSettings? current;
  @override
  State<CashbackSettingsForm> createState() => _CashbackSettingsFormState();
}

class _CashbackSettingsFormState extends State<CashbackSettingsForm> {
  final form = GlobalKey<FormState>();
  late TextEditingController rate, cap, day;
  final tiers = <(TextEditingController, TextEditingController)>[];
  String? account, category, returnCategory;
  bool enabled = true, saving = false;
  CashbackSchedule schedule = CashbackSchedule.firstPayment;
  List<Account> get accounts => widget.accounts
      .where((a) => !a.isArchived && a.currencyCode == 'BRL')
      .toList();
  @override
  void initState() {
    super.initState();
    final current = widget.current;
    rate = TextEditingController(
        text: MoneyMinor.plain(current?.rule.rateBasisPoints ?? 100));
    cap = TextEditingController(
        text: current?.rule.monthlyCapMinor == null
            ? ''
            : MoneyMinor.plain(current!.rule.monthlyCapMinor!));
    day = TextEditingController(text: '${current?.rule.receiptDay ?? 1}');
    account = accounts
            .where((a) => a.id == (current?.accountId ?? widget.card.account))
            .firstOrNull
            ?.id ??
        accounts.firstOrNull?.id;
    category = current?.categoryId;
    returnCategory = current?.returnCategoryId;
    enabled = current?.enabled ?? true;
    schedule = current?.rule.schedule ?? CashbackSchedule.firstPayment;
    for (final t in current?.rule.tiers ?? <CashbackTier>[])
      tiers.add((
        TextEditingController(text: MoneyMinor.plain(t.minimumPaidMinor)),
        TextEditingController(text: MoneyMinor.plain(t.rateBasisPoints))
      ));
  }

  @override
  void dispose() {
    rate.dispose();
    cap.dispose();
    day.dispose();
    for (final t in tiers) {
      t.$1.dispose();
      t.$2.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final rule = CashbackRule(
          rateBasisPoints: MoneyMinor.parse(rate.text),
          tiers: [
            for (final t in tiers)
              CashbackTier(
                  MoneyMinor.parse(t.$1.text), MoneyMinor.parse(t.$2.text))
          ],
          monthlyCapMinor:
              cap.text.trim().isEmpty ? null : MoneyMinor.parse(cap.text),
          schedule: schedule,
          receiptDay: int.parse(day.text));
      await widget.repo.saveSettings(
          kind: widget.card.kind,
          cardId: widget.card.id,
          enabled: enabled,
          accountId: account!,
          categoryId: category,
          returnCategoryId: returnCategory,
          rule: rule);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        cardError(
            context, e is ArgumentError ? StateError(e.message.toString()) : e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      value: () => (
            enabled,
            account,
            category,
            returnCategory,
            rate.text,
            cap.text,
            day.text,
            schedule,
            [for (final t in tiers) (t.$1.text, t.$2.text)]
          ),
      builder: (context, cancel) => MovementFormFrame(
          title: 'Cashback · ${widget.card.name}',
          onSave: save,
          onCancel: saving ? () {} : cancel,
          saveLabel: saving ? 'Salvando…' : 'Salvar regra',
          child: Form(
              key: form,
              child: Column(spacing: 16, children: [
                SwitchListTile(
                    title: const Text('Habilitar cashback'),
                    value: enabled,
                    onChanged: (v) => setState(() => enabled = v)),
                DropdownButtonFormField<String>(
                    initialValue: account,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Conta de recebimento'),
                    items: [
                      for (final a in accounts)
                        DropdownMenuItem(
                            value: a.id, child: AccountOption(account: a))
                    ],
                    validator: (v) =>
                        v == null ? 'Cadastre uma conta ativa em BRL.' : null,
                    onChanged: (v) => setState(() => account = v)),
                cashbackCategoryPicker(
                    widget.categories,
                    'income',
                    category,
                    (v) => setState(() => category = v),
                    'Categoria da receita'),
                DropdownButtonFormField<CashbackSchedule>(
                    initialValue: schedule,
                    decoration: const InputDecoration(
                        labelText: 'Previsão de recebimento'),
                    items: const [
                      DropdownMenuItem(
                          value: CashbackSchedule.firstPayment,
                          child: Text('No primeiro pagamento')),
                      DropdownMenuItem(
                          value: CashbackSchedule.nextMonth,
                          child: Text('Dia fixo do mês seguinte'))
                    ],
                    onChanged: (v) => setState(() => schedule = v!)),
                if (schedule == CashbackSchedule.nextMonth)
                  TextFormField(
                      controller: day,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Dia de recebimento (1–31)'),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return n == null || n < 1 || n > 31
                            ? 'Informe de 1 a 31.'
                            : null;
                      }),
                TextFormField(
                    controller: rate,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Percentual fixo / faixa inicial (%)')),
                ExpansionTile(
                    title: const Text('Faixas e opções avançadas'),
                    children: [
                      const Text(
                          'As faixas usam valores pagos no mês e aplicam o percentual a todas as compras. Informe limites crescentes.'),
                      for (final t in tiers)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(spacing: 8, children: [
                              MonetaryCalculatorField(
                                  controller: t.$1,
                                  labelText: 'A partir de (gasto pago)',
                                  currencyCode: 'BRL',
                                  minimumMinor: 0),
                              TextFormField(
                                  controller: t.$2,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Percentual da faixa (%)')),
                              TextButton(
                                  onPressed: () => setState(() {
                                        tiers.remove(t);
                                        t.$1.dispose();
                                        t.$2.dispose();
                                      }),
                                  child: const Text('Remover faixa'))
                            ])),
                      TextButton(
                          onPressed: () => setState(() => tiers.add((
                                TextEditingController(text: '0,00'),
                                TextEditingController(text: '1,00')
                              ))),
                          child: const Text('Adicionar faixa')),
                      TextFormField(
                          controller: cap,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText:
                                  r'Teto mensal em R$ (vazio = sem teto)')),
                      cashbackCategoryPicker(
                          widget.categories,
                          'expense',
                          returnCategory,
                          (v) => setState(() => returnCategory = v),
                          'Categoria da devolução'),
                    ]),
                const Text(
                    'Sempre gera previsão; o recebimento exige confirmação. O primeiro pagamento parcial ativa o valor total da compra uma vez. Alterar a regra recalcula compras ainda não recebidas do mês atual; confirmações anteriores são preservadas.'),
              ]))));
}

class CashbackConfirmationForm extends StatefulWidget {
  const CashbackConfirmationForm(
      {super.key,
      required this.receipts,
      required this.accounts,
      required this.categories,
      required this.repo});
  final List<CashbackReceipt> receipts;
  final List<Account> accounts;
  final List<FinanceCategory> categories;
  final CashbackRepository repo;
  @override
  State<CashbackConfirmationForm> createState() =>
      _CashbackConfirmationFormState();
}

class _CashbackConfirmationFormState extends State<CashbackConfirmationForm> {
  final form = GlobalKey<FormState>();
  late TextEditingController amount;
  String? account, category;
  DateTime date = DateTime.now();
  bool saving = false;
  bool get returns => widget.receipts.first.kind == 'return';
  List<Account> get accounts => widget.accounts
      .where((a) => !a.isArchived && a.currencyCode == 'BRL')
      .toList();
  @override
  void initState() {
    super.initState();
    amount = TextEditingController(
        text: MoneyMinor.plain(
            widget.receipts.fold(0, (v, r) => v + r.amountMinor)));
    account = accounts
            .where((a) => a.id == widget.receipts.first.accountId)
            .firstOrNull
            ?.id ??
        accounts.firstOrNull?.id;
    category = widget.receipts.first.categoryId;
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.repo.confirm(widget.receipts,
          totalMinor: MoneyMinor.parse(amount.text),
          accountId: account!,
          categoryId: category,
          date: date);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) cardError(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      value: () => (amount.text, account, category, date),
      builder: (context, cancel) => MovementFormFrame(
          title: returns ? 'Confirmar devolução' : 'Confirmar cashback',
          onSave: save,
          onCancel: saving ? () {} : cancel,
          saveLabel: saving ? 'Confirmando…' : 'Confirmar',
          child: Form(
              key: form,
              child: Column(spacing: 16, children: [
                Text(
                    '${widget.receipts.length} lançamento(s) · previsto ${cardMoney(widget.receipts.fold(0, (v, r) => v + r.amountMinor))}'),
                MonetaryCalculatorField(
                    controller: amount,
                    labelText: returns
                        ? 'Total realmente devolvido'
                        : 'Total realmente depositado',
                    currencyCode: 'BRL',
                    minimumMinor: 0),
                DropdownButtonFormField<String>(
                    initialValue: account,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: returns
                            ? 'Conta da devolução'
                            : 'Conta do recebimento'),
                    items: [
                      for (final a in accounts)
                        DropdownMenuItem(
                            value: a.id, child: AccountOption(account: a))
                    ],
                    validator: (v) =>
                        v == null ? 'Selecione uma conta ativa em BRL.' : null,
                    onChanged: (v) => setState(() => account = v)),
                cashbackCategoryPicker(
                    widget.categories,
                    returns ? 'expense' : 'income',
                    category,
                    (v) => setState(() => category = v),
                    'Categoria'),
                ListTile(
                    title: const Text('Data efetiva'),
                    subtitle: Text(cardDateLabel(date)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final chosen = await pickCardDate(context, date);
                      if (chosen != null && mounted)
                        setState(() => date = chosen);
                    }),
                const Text(
                    'O total será distribuído proporcionalmente, fechando os centavos. O valor confirmado é definitivo; uma diferença aceita não fica pendente. Informar zero registra a confirmação sem movimentar dinheiro.'),
              ]))));
}
