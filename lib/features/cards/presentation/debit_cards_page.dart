import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../core/routing/somia_shell.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_repository.dart';
import '../../accounts/domain/bank_institution.dart';
import '../../accounts/presentation/account_identity.dart';
import '../../accounts/presentation/bank_selector.dart';
import '../data/debit_cards_repository.dart';
import 'card_forms.dart';

class DebitCardsPage extends StatefulWidget {
  const DebitCardsPage({super.key});
  @override
  State<DebitCardsPage> createState() => _DebitCardsPageState();
}

class _DebitCardsPageState extends State<DebitCardsPage> {
  DebitCardsRepository get repo => getIt<DebitCardsRepository>();
  List<DebitCard> cards = [];
  List<Account> accounts = [];
  String? error;
  bool loading = true, acting = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final next = await repo.list();
      final acc = await getIt<AccountsRepository>().list();
      if (mounted) {
        setState(() {
          cards = next;
          accounts = acc;
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Não foi possível carregar. Tentar novamente';
        });
      }
    }
  }

  Future<void> edit([DebitCard? card]) async {
    await showMovementForm<bool>(context,
        (_) => DebitCardForm(card: card, accounts: accounts, repo: repo));
    if (mounted) await load();
  }

  Future<void> action(DebitCard card, String value) async {
    if (value == 'edit') {
      await edit(card);
      return;
    }
    if (value == 'cashback') {
      context.go('/cashback?kind=debit&card=${card.id}');
      return;
    }
    if (value == 'delete') {
      final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('Excluir cartão de débito?'),
                  content: const Text(
                      'O cartão sairá do cadastro. Despesas, saldo, recebimentos e histórico serão preservados.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Excluir'))
                  ]));
      if (ok != true) return;
    }
    if (mounted) setState(() => acting = true);
    try {
      if (value == 'delete') {
        await repo.delete(card.id);
      } else {
        await repo.archive(card.id, !card.archived);
      }
      await load();
    } catch (e) {
      if (mounted) cardError(context, e);
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(Theme.of(context).platform == TargetPlatform.android
              ? 'Débito'
              : 'Cartões de débito'),
          leading: somiaMenuLeading(context),
          actions: [
            IconButton(
                tooltip: 'Cartões de crédito',
                onPressed: () => context.go('/cards'),
                icon: const Icon(Icons.credit_card)),
            IconButton(
                tooltip: 'Novo cartão de débito',
                onPressed: loading || acting ? null : () => edit(),
                icon: const Icon(Icons.add))
          ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: TextButton(onPressed: load, child: Text(error!)))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    const Text(
                        'Compras no débito saem da conta vinculada quando efetivadas. Não geram fatura ou dívida de crédito.'),
                    if (cards.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                              'Cadastre um cartão para selecioná-lo ao lançar uma despesa.')),
                    for (final card in cards)
                      Card(
                          child: ListTile(
                              leading: Icon(Icons.payment,
                                  color: card.colorArgb == null
                                      ? null
                                      : Color(card.colorArgb!)),
                              title: Text(card.name),
                              subtitle: Text(
                                  '${accounts.where((a) => a.id == card.accountId).firstOrNull?.name ?? 'Conta removida'}${card.archived ? ' · Arquivado' : ''}'),
                              onTap: () => edit(card),
                              trailing: PopupMenuButton<String>(
                                  enabled: !acting,
                                  onSelected: (v) => action(card, v),
                                  itemBuilder: (_) => [
                                        const PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Editar')),
                                        const PopupMenuItem(
                                            value: 'cashback',
                                            child: Text('Cashback')),
                                        PopupMenuItem(
                                            value: 'archive',
                                            child: Text(card.archived
                                                ? 'Reativar'
                                                : 'Arquivar')),
                                        const PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Excluir'))
                                      ]))),
                  ])));
}

class DebitCardForm extends StatefulWidget {
  const DebitCardForm(
      {super.key, this.card, required this.accounts, required this.repo});
  final DebitCard? card;
  final List<Account> accounts;
  final DebitCardsRepository repo;
  @override
  State<DebitCardForm> createState() => _DebitCardFormState();
}

class _DebitCardFormState extends State<DebitCardForm> {
  final form = GlobalKey<FormState>();
  late TextEditingController name;
  String? account, bank;
  int? color;
  bool saving = false;
  List<Account> get accounts => widget.accounts
      .where((a) =>
          a.currencyCode == 'BRL' &&
          (!a.isArchived || a.id == widget.card?.accountId))
      .toList();
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.card?.name ?? '');
    account = widget.card?.accountId ?? accounts.firstOrNull?.id;
    bank = widget.card?.institutionId;
    color = widget.card?.colorArgb;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.repo.save(
          id: widget.card?.id,
          name: name.text,
          accountId: account!,
          institutionId: bank,
          colorArgb: color);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) cardError(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      value: () => (name.text, account, bank, color),
      builder: (context, cancel) => MovementFormFrame(
          title: widget.card == null
              ? 'Novo cartão de débito'
              : 'Editar cartão de débito',
          onSave: save,
          onCancel: saving ? () {} : cancel,
          saveLabel: saving ? 'Salvando…' : 'Salvar cartão',
          child: Form(
              key: form,
              child: Column(spacing: 16, children: [
                TextFormField(
                    controller: name,
                    autofocus: usesFullScreenMovementForm(context),
                    decoration: const InputDecoration(labelText: 'Nome'),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Informe o nome.'
                        : null),
                DropdownButtonFormField<String>(
                    initialValue: account,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Conta vinculada'),
                    items: [
                      for (final a in accounts)
                        DropdownMenuItem(
                            value: a.id, child: AccountOption(account: a))
                    ],
                    validator: (v) =>
                        v == null ? 'Cadastre uma conta em BRL.' : null,
                    onChanged: (v) => setState(() => account = v)),
                ListTile(
                    title: const Text('Instituição'),
                    subtitle: Text(
                        BankInstitution.find(bank)?.name ?? 'Sem instituição'),
                    onTap: () async {
                      final value = await showBankSelector(context, bank);
                      if (value != null && mounted) {
                        setState(() => bank = value.isEmpty ? null : value);
                      }
                    }),
                DropdownButtonFormField<int>(
                    initialValue: color ?? -1,
                    decoration: const InputDecoration(labelText: 'Cor'),
                    items: [
                      const DropdownMenuItem(
                          value: -1, child: Text('Padrão Somia')),
                      for (final item in const {
                        0xff6f9dd5: 'Azul',
                        0xff69b89a: 'Verde',
                        0xffb59add: 'Roxo',
                        0xffcf8390: 'Rosa'
                      }.entries)
                        DropdownMenuItem(
                            value: item.key, child: Text(item.value)),
                      if (color != null &&
                          !const {
                            0xff6f9dd5,
                            0xff69b89a,
                            0xffb59add,
                            0xffcf8390
                          }.contains(color))
                        DropdownMenuItem(
                            value: color, child: const Text('Cor atual'))
                    ],
                    onChanged: (v) =>
                        setState(() => color = v == -1 ? null : v)),
                if (widget.card != null)
                  const Text(
                      'Mudar a conta afeta somente novas compras. Despesas anteriores mantêm sua conta e saldo.'),
              ]))));
}
