import 'package:flutter/material.dart';

import '../../../core/widgets/movement_form_frame.dart';
import '../../../core/widgets/monetary_calculator.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/money_minor.dart';
import '../domain/investment.dart';

String investmentError(Object error) => error is FormatException
    ? error.message
    : error is StateError
        ? error.message
        : 'Não foi possível salvar. Tente novamente.';

class InvestmentForm extends StatefulWidget {
  const InvestmentForm({
    super.key,
    required this.repository,
    required this.overview,
    this.investment,
  });
  final InvestmentsRepository repository;
  final InvestmentOverview overview;
  final Investment? investment;
  @override
  State<InvestmentForm> createState() => _InvestmentFormState();
}

class _InvestmentFormState extends State<InvestmentForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.investment?.name ?? '');
  late final _institution = TextEditingController(
    text: widget.investment?.institution ?? '',
  );
  late final _notes = TextEditingController(
    text: widget.investment?.notes ?? '',
  );
  final _initial = TextEditingController(text: '0,00');
  late InvestmentKind _kind = widget.investment?.kind ?? InvestmentKind.cdb;
  late String _account = widget.investment?.account.id ?? '';
  late DateTime? _maturity = widget.investment?.maturityDate;
  bool _busy = false;
  String? _error;
  String get _value => [
        _name.text,
        _institution.text,
        _notes.text,
        _initial.text,
        _kind.name,
        _maturity.toString(),
        _account,
      ].join('|');

  List<Account> get _accounts => widget.overview.accounts
      .where(
        (a) =>
            a.currencyCode == 'BRL' &&
            (!a.isArchived || a.id == widget.investment?.account.id) &&
            !widget.overview.investments.any(
              (i) => i.account.id == a.id && i.id != widget.investment?.id,
            ),
      )
      .toList();

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.save(
        InvestmentDraft(
          name: _name.text,
          kind: _kind,
          maturityDate: _maturity,
          institution: _institution.text,
          notes: _notes.text,
          accountId: _account.isEmpty ? null : _account,
          initialBalanceMinor: widget.investment != null || _account.isNotEmpty
              ? 0
              : MoneyMinor.parse(_initial.text),
        ),
        id: widget.investment?.id,
      );
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
    for (final c in [_name, _institution, _notes, _initial]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
        allowCancel: !_busy,
        value: () => _value,
        builder: (context, cancel) => MovementFormFrame(
          title:
              widget.investment == null ? 'Nova aplicação' : 'Editar aplicação',
          saveLabel: _busy ? 'Salvando…' : 'Salvar aplicação',
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
                children: [
                  TextFormField(
                    controller: _name,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nome da aplicação',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Informe o nome.'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<InvestmentKind>(
                    initialValue: _kind,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: InvestmentKind.values
                        .map(
                          (k) => DropdownMenuItem(
                            value: k,
                            child: Text(
                              k.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _kind = v!),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _institution,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Instituição (opcional)',
                    ),
                  ),
                  const SizedBox(height: 20),
                  ...[
                    DropdownButtonFormField<String>(
                      initialValue: _account,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Conta vinculada',
                      ),
                      items: [
                        if (widget.investment == null)
                          const DropdownMenuItem(
                            value: '',
                            child: Text(
                              'Criar conta para aplicação',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        for (final a in _accounts)
                          DropdownMenuItem(
                            value: a.id,
                            child:
                                Text(a.name, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _account = v!),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Uma aplicação representa todo o saldo da conta vinculada. '
                      'Vincule sua conta existente para não cadastrar o mesmo dinheiro duas vezes.',
                    ),
                    const SizedBox(height: 20),
                    if (_account.isEmpty) ...[
                      MonetaryCalculatorField(
                        controller: _initial,
                        minimumMinor: 0,
                        labelText: 'Saldo já existente',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Saldo de abertura, sem gerar receita ou aporte. '
                        'A nova conta fica fora do saldo do mês; isso pode ser alterado em Contas.',
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (widget.investment != null)
                      const Text(
                        'Trocar a conta altera somente o vínculo da aplicação. Saldos e movimentações permanecem nas contas originais.',
                      ),
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Vencimento (opcional)'),
                    subtitle: Text(
                      _maturity == null
                          ? 'Sem vencimento definido'
                          : '${_maturity!.day}/${_maturity!.month}/${_maturity!.year}',
                    ),
                    leading: const Icon(Icons.event_outlined),
                    trailing: _maturity == null
                        ? null
                        : IconButton(
                            tooltip: 'Remover vencimento',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _maturity = null),
                          ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _maturity ?? DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2100, 12, 31),
                      );
                      if (date != null && mounted) {
                        setState(() => _maturity = date);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Observações (opcional)',
                      hintText:
                          'Ex.: liquidez, vencimento e condições do banco',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

enum InvestmentAction {
  deposit('Aporte'),
  withdraw('Resgate'),
  returns('Rendimento'),
  balance('Saldo do banco');

  const InvestmentAction(this.label);
  final String label;
}

class InvestmentOperationForm extends StatefulWidget {
  const InvestmentOperationForm({
    super.key,
    required this.repository,
    required this.investment,
    required this.accounts,
    required this.action,
  });
  final InvestmentsRepository repository;
  final Investment investment;
  final List<Account> accounts;
  final InvestmentAction action;
  @override
  State<InvestmentOperationForm> createState() =>
      _InvestmentOperationFormState();
}

class _InvestmentOperationFormState extends State<InvestmentOperationForm> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.action == InvestmentAction.balance
        ? MoneyMinor.plain(widget.investment.account.currentBalanceMinor)
        : '0,00',
  );
  DateTime _date = DateTime.now();
  String? _other;
  bool _busy = false;
  String? _error;
  bool get _transfer =>
      widget.action == InvestmentAction.deposit ||
      widget.action == InvestmentAction.withdraw;
  String get _value => '${_amount.text}|$_date|$_other';

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = MoneyMinor.parse(_amount.text);
      if (_transfer) {
        await widget.repository.transfer(
          widget.investment.id,
          otherAccountId: _other!,
          deposit: widget.action == InvestmentAction.deposit,
          amountMinor: value,
          date: _date,
        );
      } else if (widget.action == InvestmentAction.returns) {
        await widget.repository.recordReturn(
          widget.investment.id,
          amountMinor: value,
          date: _date,
        );
      } else {
        final overview = await widget.repository.load(date: _date);
        final item = overview.investments.firstWhere(
          (i) => i.id == widget.investment.id,
        );
        final current = item.account.currentBalanceMinor;
        if (!mounted) return;
        final delta = value - current;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Conferir saldo do banco'),
            content: Text(
              'Saldo no Somia nessa data: ${MoneyMinor.display(current, 'BRL')}\n'
              'Saldo informado: ${MoneyMinor.display(value, 'BRL')}\n'
              'Ajuste: ${MoneyMinor.display(delta, 'BRL')}\n\n'
              '${delta == 0 ? 'Os saldos conferem. Nenhum lançamento será criado.' : 'A diferença será registrada na conta, sem entrar nos gráficos de receitas e despesas.'}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Voltar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Confirmar ajuste'),
              ),
            ],
          ),
        );
        if (confirm != true) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        await widget.repository.reconcile(
          item.id,
          targetMinor: value,
          expectedBalanceMinor: current,
          date: _date,
        );
      }
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

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
        allowCancel: !_busy,
        value: () => _value,
        builder: (context, cancel) => MovementFormFrame(
          title: widget.action.label,
          saveLabel: _busy
              ? 'Salvando…'
              : widget.action == InvestmentAction.balance
                  ? 'Conferir ajuste'
                  : 'Registrar',
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
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.investment.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 20),
                  MonetaryCalculatorField(
                    controller: _amount,
                    minimumMinor:
                        widget.action == InvestmentAction.balance ? 0 : 1,
                    labelText: widget.action == InvestmentAction.balance
                        ? 'Saldo mostrado pelo banco'
                        : 'Valor',
                  ),
                  const SizedBox(height: 20),
                  if (_transfer) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _other,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: widget.action == InvestmentAction.deposit
                            ? 'De qual conta saiu?'
                            : 'Em qual conta entrou?',
                      ),
                      items: widget.accounts
                          .where(
                            (a) =>
                                (!a.isArchived ||
                                    a.id == widget.investment?.account.id) &&
                                a.currencyCode == 'BRL' &&
                                a.id != widget.investment.account.id,
                          )
                          .map(
                            (a) => DropdownMenuItem(
                              value: a.id,
                              child:
                                  Text(a.name, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      validator: (v) => v == null
                          ? 'Selecione outra conta ativa em reais.'
                          : null,
                      onChanged: (v) => setState(() => _other = v),
                    ),
                    const SizedBox(height: 20),
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Data da movimentação'),
                    subtitle: Text(
                      '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                    ),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _transfer
                        ? 'Será criada uma transferência já realizada, sem gerar receita ou despesa.'
                        : widget.action == InvestmentAction.returns
                            ? 'Informe o rendimento creditado pelo banco. Será registrado como receita realizada na aplicação.'
                            : 'Informe o saldo total nessa data. O app mostrará a diferença antes de gravar. Aportes e resgates precisam estar registrados primeiro.',
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}
