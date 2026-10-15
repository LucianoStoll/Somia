import 'package:flutter/material.dart';
import '../../../core/widgets/monetary_calculator.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../accounts/domain/money_minor.dart';
import '../../assets/domain/asset.dart';
import '../../assets/presentation/asset_form.dart' show assetDate;
import '../../investments/presentation/investment_forms.dart'
    show investmentError;
import '../domain/debt.dart';

class DebtForm extends StatefulWidget {
  const DebtForm(
      {super.key, required this.repository, required this.assets, this.debt});
  final DebtsRepository repository;
  final List<Asset> assets;
  final Debt? debt;
  @override
  State<DebtForm> createState() => _DebtFormState();
}

class _DebtFormState extends State<DebtForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.debt?.name ?? '');
  late final _creditor =
      TextEditingController(text: widget.debt?.creditor ?? '');
  late final _balance = TextEditingController(
      text: MoneyMinor.plain(widget.debt?.initialMinor ?? 0));
  late final _notes = TextEditingController(text: widget.debt?.notes ?? '');
  late DebtKind _kind = widget.debt?.kind ?? DebtKind.loan;
  late DateTime _date =
      widget.debt?.referenceAt ?? DateUtils.dateOnly(DateTime.now());
  late String? _assetId = widget.debt?.assetId;
  bool _busy = false;
  String? _error;
  bool get _fixed => widget.debt?.payments.isNotEmpty ?? false;
  String get _snapshot => [
        _name.text,
        _creditor.text,
        _balance.text,
        _notes.text,
        _kind.name,
        _date.toString(),
        _assetId
      ].join('|');
  Future<void> _pick() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime(1900),
        lastDate: DateTime.now());
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.save(
          DebtDraft(
              name: _name.text,
              creditor: _creditor.text,
              kind: _kind,
              balanceMinor: MoneyMinor.parse(_balance.text),
              referenceAt: _date,
              assetId: _assetId,
              notes: _notes.text),
          id: widget.debt?.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = investmentError(e);
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _creditor, _balance, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      allowCancel: !_busy,
      value: () => _snapshot,
      builder: (context, cancel) => MovementFormFrame(
          title: widget.debt == null ? 'Nova dívida' : 'Editar dívida',
          saveLabel: _busy ? 'Salvando…' : 'Salvar',
          onSave: _save,
          onCancel: () {
            if (!_busy) cancel();
          },
          child: AbsorbPointer(
              absorbing: _busy,
              child: Form(
                  key: _form,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                        controller: _name,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        decoration:
                            const InputDecoration(labelText: 'Nome da dívida'),
                        validator: (v) => v?.trim().isEmpty ?? true
                            ? 'Informe o nome.'
                            : null),
                    const SizedBox(height: 20),
                    TextFormField(
                        controller: _creditor,
                        decoration:
                            const InputDecoration(labelText: 'Credor / banco'),
                        validator: (v) => v?.trim().isEmpty ?? true
                            ? 'Informe o credor.'
                            : null),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<DebtKind>(
                        initialValue: _kind,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Tipo'),
                        items: DebtKind.values
                            .map((k) => DropdownMenuItem(
                                value: k, child: Text(k.label)))
                            .toList(),
                        onChanged: (v) => setState(() => _kind = v!)),
                    const SizedBox(height: 20),
                    if (widget.debt == null) ...[
                      DropdownButtonFormField<String>(
                          initialValue: _assetId ?? '',
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Bem vinculado (opcional)'),
                          items: [
                            const DropdownMenuItem<String>(
                                value: '', child: Text('Sem vínculo com bem')),
                            for (final a in widget.assets)
                              DropdownMenuItem(
                                  value: a.id,
                                  child: Text(a.name,
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: (v) => setState(() {
                                _assetId = v == '' ? null : v;
                                if (_assetId != null) {
                                  final a = widget.assets
                                      .firstWhere((a) => a.id == _assetId);
                                  _balance.text = MoneyMinor.plain(a.debtMinor);
                                  _creditor.text = a.managedCreditor ??
                                      a.current?.creditor ??
                                      '';
                                  _kind = DebtKind.financing;
                                }
                              })),
                      const SizedBox(height: 12),
                      const Text(
                          'Ao vincular um bem, este saldo substitui seu financiamento manual no patrimônio. Confira o valor devido na data de referência.'),
                      const SizedBox(height: 20)
                    ],
                    if (_fixed) ...[
                      Text(
                          'Saldo inicial: ${MoneyMinor.display(widget.debt!.initialMinor, 'BRL')}'),
                      Text('Referência: ${assetDate(_date)}'),
                      const Text(
                          'O saldo inicial e a referência ficam preservados após vincular parcelas.')
                    ] else ...[
                      MonetaryCalculatorField(
                          controller: _balance,
                          labelText: 'Saldo devedor inicial',
                          minimumMinor: 0),
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Data de referência do saldo'),
                          subtitle: Text(assetDate(_date)),
                          trailing: const Icon(Icons.calendar_month),
                          onTap: _pick)
                    ],
                    const SizedBox(height: 16),
                    const Text(
                        'Informe o principal restante, sem somar juros futuros. Vincule somente parcelas ainda não abatidas neste saldo. Cadastro não movimenta contas.'),
                    const SizedBox(height: 20),
                    TextFormField(
                        controller: _notes,
                        maxLines: 3,
                        decoration: const InputDecoration(
                            labelText: 'Observações (opcional)')),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)))
                  ])))));
}

class DebtPaymentForm extends StatefulWidget {
  const DebtPaymentForm(
      {super.key,
      required this.repository,
      required this.debt,
      required this.expenses});
  final DebtsRepository repository;
  final Debt debt;
  final List<DebtExpense> expenses;
  @override
  State<DebtPaymentForm> createState() => _DebtPaymentFormState();
}

class _DebtPaymentFormState extends State<DebtPaymentForm> {
  final _form = GlobalKey<FormState>();
  final _principal = TextEditingController(text: '0,00');
  final _search = TextEditingController();
  DebtExpense? _expense;
  bool _busy = false;
  String? _error;
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_expense == null) {
      setState(() => _error = 'Selecione uma despesa.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.link(
          widget.debt.id, _expense!.id, MoneyMinor.parse(_principal.text));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = investmentError(e);
        });
      }
    }
  }

  @override
  void dispose() {
    _principal.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      allowCancel: !_busy,
      value: () => '${_expense?.id}|${_principal.text}',
      builder: (context, cancel) => MovementFormFrame(
          title: 'Vincular parcela / despesa',
          saveLabel: _busy ? 'Salvando…' : 'Vincular',
          onSave: _save,
          onCancel: () {
            if (!_busy) cancel();
          },
          child: AbsorbPointer(
              absorbing: _busy,
              child: Form(
                  key: _form,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.debt.name,
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        Text(
                            'Amortização disponível: ${MoneyMinor.display(widget.debt.projectedMinor, 'BRL')}'),
                        const Text(
                            'Selecione uma despesa já cadastrada em BRL. Para uma nova parcela, cadastre primeiro em Despesas e volte para vinculá-la.'),
                        const SizedBox(height: 16),
                        TextField(
                            controller: _search,
                            decoration: const InputDecoration(
                                labelText: 'Buscar despesa',
                                prefixIcon: Icon(Icons.search)),
                            onChanged: (_) => setState(() {})),
                        SizedBox(
                            height: 220,
                            child: ListView(children: [
                              if (widget.expenses.isEmpty)
                                const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text(
                                        'Nenhuma despesa disponível a partir da referência do saldo.')),
                              for (final e in widget.expenses.where((e) => e
                                  .description
                                  .toLowerCase()
                                  .contains(_search.text.toLowerCase())))
                                ListTile(
                                    selected: _expense?.id == e.id,
                                    leading: Icon(_expense?.id == e.id
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked),
                                    title: Text(e.description),
                                    subtitle: Text(
                                        '${assetDate(e.date)} · ${e.effective ? 'Paga' : 'Prevista'} · ${MoneyMinor.display(e.amountMinor, 'BRL')}'),
                                    onTap: () => setState(() => _expense = e))
                            ])),
                        const SizedBox(height: 16),
                        if (_expense != null)
                          Text(
                              'Selecionada: ${_expense!.description} · ${MoneyMinor.display(_expense!.amountMinor, 'BRL')}'),
                        MonetaryCalculatorField(
                            controller: _principal,
                            labelText: 'Amortização (principal)',
                            minimumMinor: 0),
                        const SizedBox(height: 12),
                        const Text(
                            'A diferença entre o valor da parcela e a amortização representa juros e encargos. Zero é permitido quando o pagamento contém somente encargos. Vincular não altera nem efetiva a despesa.'),
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(_error!,
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error)))
                      ])))));
}
