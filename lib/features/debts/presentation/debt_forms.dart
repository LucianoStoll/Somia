import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
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

/// Vincula uma ou mais despesas à dívida (protótipo P-49): lista enxuta com
/// seleção múltipla, amortização por despesa e totais no rodapé.
class _DebtPaymentFormState extends State<DebtPaymentForm> {
  final _search = TextEditingController();
  // Ordem de seleção preservada; a chave é o id da despesa.
  final _selected = <String, TextEditingController>{};
  bool _busy = false;
  String? _error;

  int _principalOf(String id) {
    try {
      return MoneyMinor.parse(_selected[id]!.text);
    } catch (_) {
      return 0;
    }
  }

  int get _total => _selected.keys.fold(0, (sum, id) => sum + _principalOf(id));
  int get _available => widget.debt.projectedMinor;

  void _toggle(DebtExpense expense) => setState(() {
        _error = null;
        final removed = _selected.remove(expense.id);
        if (removed != null) {
          removed.dispose();
        } else {
          _selected[expense.id] = TextEditingController(text: '0,00')
            ..addListener(() => setState(() {}));
        }
      });

  Future<void> _sameForAll() async {
    final first =
        _selected.keys.isEmpty ? 0 : _principalOf(_selected.keys.first);
    final value = await showMonetaryCalculator(context,
        initialMinor: first, minimumMinor: 0);
    if (value == null || !mounted) return;
    setState(() {
      for (final controller in _selected.values) {
        controller.text = MoneyMinor.plain(value);
      }
    });
  }

  Future<void> _help() => showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
            title: const Text('Como funciona'),
            content: const Text(
                'Escolha despesas já cadastradas em BRL a partir da referência do saldo. '
                'A amortização é a parte da parcela que reduz a dívida; a diferença '
                'fica como juros e encargos. Zero é permitido quando o pagamento tem '
                'só encargos. Vincular não altera nem efetiva as despesas.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialog),
                  child: const Text('Entendi'))
            ],
          ));

  Future<void> _save() async {
    if (_busy || _selected.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.linkMany(widget.debt.id, {
        for (final id in _selected.keys)
          id: MoneyMinor.parse(_selected[id]!.text),
      });
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
    for (final controller in _selected.values) {
      controller.dispose();
    }
    _search.dispose();
    super.dispose();
  }

  String _money(int minor) => MoneyMinor.display(minor, 'BRL')
      .replaceAllMapped(RegExp(r'\d{1,3}(?=(\d{3})+,)'), (m) => '${m[0]}.');

  String _short(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

  Widget _row(DebtExpense e) {
    final t = context.somia;
    final selected = _selected.containsKey(e.id);
    final principal = selected ? _principalOf(e.id) : 0;
    return Container(
      key: ValueKey('debt-link-${e.id}'),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color:
            selected ? t.accent.withValues(alpha: t.isDark ? .10 : .08) : null,
        borderRadius: BorderRadius.circular(SomiaRadius.md),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(SomiaRadius.md),
          onTap: () => _toggle(e),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Semantics(
                checked: selected,
                label: 'Selecionar ${e.description}',
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: selected ? t.accent : null,
                    border: selected
                        ? null
                        : Border.all(color: t.outline, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: selected
                      ? Icon(Icons.check, size: 16, color: t.onAccent)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(
                          '${_short(e.date)}, ${e.effective ? 'paga' : 'prevista'}',
                          style: TextStyle(fontSize: 13, color: t.muted)),
                    ]),
              ),
              const SizedBox(width: 8),
              Text(_money(e.amountMinor),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        if (selected)
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    principal > e.amountMinor
                        ? 'Maior que a parcela'
                        : 'Juros e encargos ${_money(e.amountMinor - principal)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: principal > e.amountMinor ? t.expense : t.muted),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 168,
                  child: MonetaryCalculatorField(
                      key: ValueKey('debt-link-principal-${e.id}'),
                      controller: _selected[e.id]!,
                      labelText: 'Amortização',
                      minimumMinor: 0),
                ),
              ],
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.somia;
    final query = _search.text.trim().toLowerCase();
    final visible = widget.expenses
        .where((e) => e.description.toLowerCase().contains(query))
        .toList();
    final exceeds = _total - _available;
    final overParcel = _selected.keys.any((id) =>
        _principalOf(id) >
        widget.expenses.firstWhere((e) => e.id == id).amountMinor);
    final count = _selected.length;
    return UnsavedChangesGuard(
        allowCancel: !_busy,
        value: () =>
            _selected.entries.map((e) => '${e.key}:${e.value.text}').join('|'),
        builder: (context, cancel) => MovementFormFrame(
            title: 'Vincular despesas',
            saveLabel: _busy
                ? 'Salvando…'
                : count == 0
                    ? 'Selecione as despesas'
                    : count == 1
                        ? 'Vincular 1 despesa'
                        : 'Vincular $count despesas',
            canSave: count > 0 && exceeds <= 0 && !overParcel && !_busy,
            onSave: _save,
            onCancel: () {
              if (!_busy) cancel();
            },
            footer: count == 0 && _error == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (count > 0)
                        Row(children: [
                          Expanded(
                            child: Text(
                                count == 1
                                    ? '1 selecionada, amortização total'
                                    : '$count selecionadas, amortização total',
                                style: TextStyle(color: t.muted)),
                          ),
                          Text(_money(_total),
                              key: const ValueKey('debt-link-total'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                      if (exceeds > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                              'Passa do disponível em ${_money(exceeds)}.',
                              style: TextStyle(color: t.expense)),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child:
                              Text(_error!, style: TextStyle(color: t.expense)),
                        ),
                    ],
                  ),
            child: AbsorbPointer(
                absorbing: _busy,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(widget.debt.name,
                              style: TextStyle(color: t.muted, fontSize: 14)),
                        ),
                        IconButton(
                            tooltip: 'Como funciona a amortização',
                            color: t.muted,
                            onPressed: _help,
                            icon: const Icon(Icons.help_outline)),
                      ]),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: t.surface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(children: [
                          Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                  color: t.accent, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text('Pode amortizar até',
                                  style:
                                      TextStyle(color: t.muted, fontSize: 13))),
                          Text(_money(_available),
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                          controller: _search,
                          decoration: InputDecoration(
                              hintText: 'Buscar despesa',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(SomiaRadius.pill),
                                  borderSide: BorderSide(color: t.outline)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(SomiaRadius.pill),
                                  borderSide: BorderSide(color: t.outline))),
                          onChanged: (_) => setState(() {})),
                      if (count >= 2)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: const ValueKey('debt-link-same-value'),
                            onPressed: _sameForAll,
                            icon: const Icon(Icons.copy_all_outlined, size: 18),
                            label: const Text('Mesmo valor em todas'),
                          ),
                        )
                      else
                        const SizedBox(height: 8),
                      if (widget.expenses.isEmpty)
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                                'Nenhuma despesa disponível a partir da referência do saldo.',
                                style: TextStyle(color: t.muted))),
                      for (final e in visible) _row(e),
                    ]))));
  }
}
