import 'package:flutter/material.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../../core/widgets/monetary_calculator.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/money_minor.dart';
import '../../accounts/domain/bank_institution.dart';
import '../../accounts/presentation/account_identity.dart';
import '../../accounts/presentation/bank_selector.dart';
import '../domain/credit_card.dart';

String cardDateLabel(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String cardMonthLabel(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.year}';
String cardMoney(int n) => MoneyMinor.display(n, 'BRL');
void cardError(BuildContext context, Object e) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is FormatException
            ? e.message
            : e is StateError
                ? e.message
                : 'Não foi possível salvar. Tente novamente.')));
Future<DateTime?> pickCardDate(BuildContext context, DateTime date,
        {String? help}) =>
    showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100, 12, 31),
        helpText: help);

class CardForm extends StatefulWidget {
  const CardForm(
      {super.key,
      required this.accounts,
      required this.month,
      required this.onSubmit,
      this.card});
  final List<Account> accounts;
  final DateTime month;
  final CreditCard? card;
  final Future<void> Function(CardDraft, int, DateTime) onSubmit;
  @override
  State<CardForm> createState() => _CardFormState();
}

class _CardFormState extends State<CardForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _name, _limit, _closing, _due;
  final _opening = TextEditingController(text: '0,00');
  late DateTime _month;
  String? _account, _bank;
  int? _colorArgb;
  late bool _controlLimit;
  bool _saving = false;
  List<Account> get _accounts => widget.accounts
      .where((a) =>
          a.currencyCode == 'BRL' &&
          (!a.isArchived || a.id == widget.card?.paymentAccountId))
      .toList();
  @override
  void initState() {
    super.initState();
    final c = widget.card;
    _name = TextEditingController(text: c?.name ?? '');
    _limit = TextEditingController(text: MoneyMinor.plain(c?.limitMinor ?? 0));
    _closing = TextEditingController(text: '${c?.closingDay ?? 25}');
    _due = TextEditingController(text: '${c?.dueDay ?? 5}');
    _account = c?.paymentAccountId ?? _accounts.firstOrNull?.id;
    _bank = c?.institutionId;
    _colorArgb = c?.colorArgb;
    _controlLimit = c == null || c.limitMinor != null;
    _month = widget.month;
  }

  @override
  void dispose() {
    for (final c in [_name, _limit, _closing, _due, _opening]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _day(String? v) {
    final n = int.tryParse(v ?? '');
    return n == null || n < 1 || n > 31 ? 'Informe de 1 a 31.' : null;
  }

  Future<void> _save() async {
    if (_saving || !_key.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSubmit(
          CardDraft(
              name: _name.text,
              paymentAccountId: _account!,
              closingDay: int.parse(_closing.text),
              dueDay: int.parse(_due.text),
              limitMinor: _controlLimit ? MoneyMinor.parse(_limit.text) : null,
              institutionId: _bank,
              colorArgb: _colorArgb),
          widget.card == null ? MoneyMinor.parse(_opening.text) : 0,
          _month);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) cardError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      value: () => (
            _name.text,
            _limit.text,
            _closing.text,
            _due.text,
            _opening.text,
            _account,
            _bank,
            _colorArgb,
            _controlLimit,
            _month
          ),
      builder: (context, cancel) => MovementFormFrame(
          title: widget.card == null ? 'Novo cartão' : 'Editar cartão',
          saveLabel: _saving ? 'Salvando…' : 'Salvar cartão',
          onSave: _save,
          onCancel: _saving ? () {} : cancel,
          child: Form(
              key: _key,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 16,
                  children: [
                    TextFormField(
                        controller: _name,
                        autofocus: usesFullScreenMovementForm(context),
                        textInputAction: TextInputAction.next,
                        decoration:
                            const InputDecoration(labelText: 'Nome do cartão'),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Informe o nome.'
                            : null),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: AccountAvatar(institutionId: _bank),
                        title: const Text('Instituição'),
                        subtitle: Text(BankInstitution.find(_bank)?.name ??
                            'Sem instituição'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final selected =
                              await showBankSelector(context, _bank);
                          if (selected != null && mounted) {
                            setState(() =>
                                _bank = selected.isEmpty ? null : selected);
                          }
                        }),
                    DropdownButtonFormField<int>(
                        initialValue: _colorArgb ?? -1,
                        menuMaxHeight: 280,
                        borderRadius: BorderRadius.circular(16),
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Cor do cartão'),
                        items: [
                          const DropdownMenuItem<int>(
                              value: -1, child: Text('Padrão Somia')),
                          for (final entry in const <int, String>{
                            0xff6f9dd5: 'Azul',
                            0xff69b89a: 'Verde',
                            0xffb59add: 'Roxo',
                            0xffd59c76: 'Laranja',
                            0xffcf8390: 'Rosa',
                            0xff8c9baa: 'Cinza',
                          }.entries)
                            DropdownMenuItem(
                                value: entry.key,
                                child: Row(children: [
                                  Icon(Icons.circle,
                                      color: Color(entry.key), size: 20),
                                  const SizedBox(width: 10),
                                  Text(entry.value),
                                ])),
                        ],
                        onChanged: (value) => setState(
                            () => _colorArgb = value == -1 ? null : value)),
                    DropdownButtonFormField<String>(
                        menuMaxHeight: 280,
                        borderRadius: BorderRadius.circular(16),
                        itemHeight: 48,
                        initialValue: _account,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Conta padrão para pagamento'),
                        items: [
                          for (final a in _accounts)
                            DropdownMenuItem(
                                value: a.id, child: AccountOption(account: a))
                        ],
                        validator: (v) =>
                            v == null ? 'Cadastre uma conta em BRL.' : null,
                        onChanged: (v) => setState(() => _account = v)),
                    const Text(
                        'A conta padrão recebe a projeção das faturas. Cada pagamento pode usar outra conta.'),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Controlar limite'),
                        value: _controlLimit,
                        onChanged: (v) => setState(() => _controlLimit = v)),
                    if (_controlLimit)
                      MonetaryCalculatorField(
                          controller: _limit,
                          labelText: 'Limite',
                          currencyCode: 'BRL',
                          minimumMinor: 0),
                    TextFormField(
                        controller: _closing,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Dia de fechamento'),
                        validator: _day),
                    TextFormField(
                        controller: _due,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Dia de vencimento'),
                        validator: _day),
                    const Text(
                        'Compra no dia do fechamento entra na próxima fatura. Dias inexistentes usam o último dia do mês.'),
                    if (widget.card != null)
                      const Text(
                          'Alterar estes dias vale para novas faturas. Ajuste as datas reais das faturas existentes nos detalhes.'),
                    if (widget.card == null) ...[
                      const Divider(),
                      const Text('Começar com um cartão já em uso'),
                      MonetaryCalculatorField(
                          controller: _opening,
                          labelText: 'Saldo da fatura atual (opcional)',
                          currencyCode: 'BRL',
                          minimumMinor: -9000000000000000),
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Mês da fatura inicial'),
                          subtitle: Text(cardMonthLabel(_month)),
                          trailing: const Icon(Icons.calendar_today),
                          onTap: () async {
                            final d = await pickCardDate(context, _month,
                                help: 'Mês do vencimento');
                            if (d != null && mounted) {
                              setState(
                                  () => _month = DateTime(d.year, d.month));
                            }
                          }),
                      const Text(
                          'Use o saldo que falta pagar. Crédito pode ser negativo. Este saldo não repete gastos antigos nos relatórios. Cadastre parcelas restantes pelo botão de compra; evite incluir o mesmo valor nos dois lugares.'),
                    ],
                  ]))));
}

class CardPaymentForm extends StatefulWidget {
  const CardPaymentForm(
      {super.key,
      required this.invoice,
      required this.card,
      required this.accounts,
      required this.onSubmit});
  final CardInvoice invoice;
  final CreditCard card;
  final List<Account> accounts;
  final Future<void> Function(String, int, DateTime, int, int) onSubmit;
  @override
  State<CardPaymentForm> createState() => _CardPaymentFormState();
}

class _CardPaymentFormState extends State<CardPaymentForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _amount;
  final _fee = TextEditingController(text: '0,00'),
      _discount = TextEditingController(text: '0,00');
  String? _account;
  DateTime _date = DateTime.now();
  bool _saving = false;
  List<Account> get _accounts => widget.accounts
      .where((a) => !a.isArchived && a.currencyCode == 'BRL')
      .toList();
  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
        text: MoneyMinor.plain(widget.invoice.projectedMinor > 0
            ? widget.invoice.projectedMinor
            : 0));
    _account = _accounts.any((a) => a.id == widget.card.paymentAccountId)
        ? widget.card.paymentAccountId
        : _accounts.firstOrNull?.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _fee.dispose();
    _discount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_key.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSubmit(_account!, MoneyMinor.parse(_amount.text), _date,
          MoneyMinor.parse(_fee.text), MoneyMinor.parse(_discount.text));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) cardError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      value: () => (_amount.text, _fee.text, _discount.text, _account, _date),
      builder: (context, cancel) => MovementFormFrame(
          title: 'Pagar fatura ${cardMonthLabel(widget.invoice.month)}',
          saveLabel: _saving ? 'Salvando…' : 'Registrar pagamento',
          onSave: _save,
          onCancel: _saving ? () {} : cancel,
          child: Form(
              key: _key,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 16,
                  children: [
                    Text(
                        'Saldo da fatura: ${cardMoney(widget.invoice.balanceMinor)}'),
                    DropdownButtonFormField<String>(
                        menuMaxHeight: 280,
                        borderRadius: BorderRadius.circular(16),
                        itemHeight: 48,
                        initialValue: _account,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Conta do pagamento'),
                        items: [
                          for (final a in _accounts)
                            DropdownMenuItem(
                                value: a.id, child: AccountOption(account: a))
                        ],
                        validator: (v) => v == null
                            ? 'Selecione uma conta ativa em BRL.'
                            : null,
                        onChanged: (v) => setState(() => _account = v)),
                    MonetaryCalculatorField(
                        controller: _amount,
                        labelText: 'Valor pago',
                        currencyCode: 'BRL'),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Data do pagamento'),
                        subtitle: Text(cardDateLabel(_date)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final d = await pickCardDate(context, _date);
                          if (d != null && mounted) setState(() => _date = d);
                        }),
                    MonetaryCalculatorField(
                        controller: _fee,
                        labelText: 'Juros, multa e acréscimos',
                        currencyCode: 'BRL',
                        minimumMinor: 0),
                    MonetaryCalculatorField(
                        controller: _discount,
                        labelText: 'Desconto',
                        currencyCode: 'BRL',
                        minimumMinor: 0),
                    const Text(
                        'O valor pago é o débito real da conta. Encargos e desconto ajustam a dívida. Pagamento parcial carrega o restante; pagamento a maior gera crédito. Data futura agenda o débito.'),
                  ]))));
}

class CardAdjustmentForm extends StatefulWidget {
  const CardAdjustmentForm(
      {super.key,
      required this.title,
      required this.month,
      required this.onSubmit,
      this.initialAmount = 0,
      this.signed = false});
  final String title;
  final DateTime month;
  final int initialAmount;
  final bool signed;
  final Future<void> Function(int, DateTime, DateTime) onSubmit;
  @override
  State<CardAdjustmentForm> createState() => _CardAdjustmentFormState();
}

class _CardAdjustmentFormState extends State<CardAdjustmentForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late DateTime _month;
  DateTime _date = DateTime.now();
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _amount =
        TextEditingController(text: MoneyMinor.plain(widget.initialAmount));
    _month = widget.month;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_key.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSubmit(MoneyMinor.parse(_amount.text), _month, _date);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) cardError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      value: () => (_amount.text, _month, _date),
      builder: (context, cancel) => MovementFormFrame(
          title: widget.title,
          onSave: _save,
          onCancel: _saving ? () {} : cancel,
          saveLabel: _saving ? 'Salvando…' : 'Salvar ajuste',
          child: Form(
              key: _key,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 16,
                  children: [
                    MonetaryCalculatorField(
                        controller: _amount,
                        labelText: 'Valor',
                        currencyCode: 'BRL',
                        minimumMinor: widget.signed ? -9000000000000000 : 1),
                    if (widget.signed)
                      const Text(
                          'Saldo inicial a pagar: positivo. Crédito inicial: negativo. Não será somado aos gastos por categoria.'),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Fatura de destino'),
                        subtitle: Text(cardMonthLabel(_month)),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final d = await pickCardDate(context, _month,
                              help: 'Mês do vencimento');
                          if (d != null && mounted) {
                            setState(() => _month = DateTime(d.year, d.month));
                          }
                        }),
                    if (!widget.signed)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Data do estorno'),
                          subtitle: Text(cardDateLabel(_date)),
                          trailing: const Icon(Icons.calendar_today),
                          onTap: () async {
                            final d = await pickCardDate(context, _date);
                            if (d != null && mounted) setState(() => _date = d);
                          }),
                  ]))));
}

class CardDatesForm extends StatefulWidget {
  const CardDatesForm(
      {super.key, required this.invoice, required this.onSubmit});
  final CardInvoice invoice;
  final Future<void> Function(DateTime, DateTime) onSubmit;
  @override
  State<CardDatesForm> createState() => _CardDatesFormState();
}

class _CardDatesFormState extends State<CardDatesForm> {
  late DateTime _closing, _due;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _closing = widget.invoice.closingAt;
    _due = widget.invoice.dueAt;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSubmit(_closing, _due);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) cardError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      value: () => (_closing, _due),
      builder: (context, cancel) => MovementFormFrame(
          title: 'Datas reais da fatura',
          onSave: _save,
          onCancel: _saving ? () {} : cancel,
          saveLabel: _saving ? 'Salvando…' : 'Salvar datas',
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                title: const Text('Fechamento'),
                subtitle: Text(cardDateLabel(_closing)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final d = await pickCardDate(context, _closing);
                  if (d != null && mounted) setState(() => _closing = d);
                }),
            ListTile(
                title: const Text('Vencimento'),
                subtitle: Text(cardDateLabel(_due)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final d = await pickCardDate(context, _due);
                  if (d != null && mounted) setState(() => _due = d);
                }),
            const Text(
                'Compras já lançadas permanecem na fatura. Mude a fatura de uma compra pelo formulário de edição.'),
          ])));
}

class CardAnticipationForm extends StatefulWidget {
  const CardAnticipationForm(
      {super.key,
      required this.invoice,
      required this.entries,
      required this.onSubmit});
  final CardInvoice invoice;
  final List<CardEntry> entries;
  final Future<void> Function(List<String>, int) onSubmit;
  @override
  State<CardAnticipationForm> createState() => _CardAnticipationFormState();
}

class _CardAnticipationFormState extends State<CardAnticipationForm> {
  final _selected = <String>{};
  final _discount = TextEditingController(text: '0,00');
  final _key = GlobalKey<FormState>();
  bool _saving = false;
  @override
  void dispose() {
    _discount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_key.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSubmit(
          _selected.toList(), MoneyMinor.parse(_discount.text));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) cardError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      value: () =>
          "${(_selected.toList()..sort()).join('|')};${_discount.text}",
      builder: (context, cancel) => MovementFormFrame(
          title: 'Antecipar para ${cardMonthLabel(widget.invoice.month)}',
          saveLabel: _saving ? 'Salvando…' : 'Antecipar parcelas',
          onSave: _save,
          onCancel: _saving ? () {} : cancel,
          child: Form(
              key: _key,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 12,
                  children: [
                    if (widget.entries.isEmpty)
                      const Text('Nenhuma parcela futura disponível.'),
                    for (final e in widget.entries)
                      CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _selected.contains(e.id),
                          title: Text(e.description),
                          subtitle: Text(
                              '${e.label} · ${cardMonthLabel(e.invoiceMonth)} · ${cardMoney(e.amountMinor)}'),
                          onChanged: (v) => setState(() => v == true
                              ? _selected.add(e.id)
                              : _selected.remove(e.id))),
                    Text(
                        'Total selecionado: ${cardMoney(widget.entries.where((e) => _selected.contains(e.id)).fold(0, (a, e) => a + e.amountMinor))}'),
                    MonetaryCalculatorField(
                        controller: _discount,
                        labelText: 'Desconto pela antecipação',
                        currencyCode: 'BRL',
                        minimumMinor: 0),
                    const Text(
                        'As parcelas selecionadas mudam de fatura; o desconto é um crédito separado. O histórico da mudança permanece disponível.'),
                  ]))));
}
