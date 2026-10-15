import 'package:flutter/material.dart';
import '../../../core/widgets/monetary_calculator.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../accounts/domain/money_minor.dart';
import '../../investments/presentation/investment_forms.dart'
    show investmentError;
import '../domain/asset.dart';

String assetDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class AssetForm extends StatefulWidget {
  const AssetForm(
      {super.key,
      required this.repository,
      this.asset,
      this.valuationOnly = false});
  final AssetsRepository repository;
  final Asset? asset;
  final bool valuationOnly;
  @override
  State<AssetForm> createState() => _AssetFormState();
}

class _AssetFormState extends State<AssetForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.asset?.name ?? '');
  late final _cost = TextEditingController(
      text: MoneyMinor.plain(widget.asset?.acquisitionMinor ?? 0));
  late final _value = TextEditingController(
      text: MoneyMinor.plain(widget.asset?.valueMinor ?? 0));
  late final _debt = TextEditingController(
      text: MoneyMinor.plain(widget.asset?.debtMinor ?? 0));
  late final _creditor =
      TextEditingController(text: widget.asset?.current?.creditor ?? '');
  late final _notes = TextEditingController(
      text: widget.valuationOnly ? '' : widget.asset?.notes ?? '');
  late AssetKind _kind = widget.asset?.kind ?? AssetKind.vehicle;
  late DateTime _acquired =
      widget.asset?.acquiredAt ?? DateUtils.dateOnly(DateTime.now());
  DateTime _assessed = DateUtils.dateOnly(DateTime.now());
  bool _busy = false;
  String? _error;
  bool get _values => widget.asset == null || widget.valuationOnly;
  String get _snapshot => [
        _name.text,
        _cost.text,
        _value.text,
        _debt.text,
        _creditor.text,
        _notes.text,
        _kind.name,
        _acquired.toString(),
        _assessed.toString()
      ].join('|');
  Future<void> _pick(bool acquisition) async {
    final d = await showDatePicker(
        context: context,
        initialDate: acquisition ? _acquired : _assessed,
        firstDate: DateTime(1900),
        lastDate: DateTime.now());
    if (d != null && mounted) {
      setState(() => acquisition ? _acquired = d : _assessed = d);
    }
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final assessment = _values
          ? AssetValuationDraft(
              date: _assessed,
              valueMinor: MoneyMinor.parse(_value.text),
              debtMinor: widget.asset?.managedDebtMinor != null
                  ? widget.asset!.current!.debtMinor
                  : MoneyMinor.parse(_debt.text),
              creditor: widget.asset?.managedDebtMinor != null
                  ? widget.asset!.current!.creditor
                  : _creditor.text,
              notes: widget.valuationOnly ? _notes.text : '')
          : null;
      if (widget.valuationOnly) {
        await widget.repository.assess(widget.asset!.id, assessment!,
            expectedLatestId: widget.asset!.current?.id);
      } else {
        await widget.repository.save(
            AssetDraft(
                name: _name.text,
                kind: _kind,
                acquiredAt: _acquired,
                acquisitionMinor: MoneyMinor.parse(_cost.text),
                notes: _notes.text),
            id: widget.asset?.id,
            initial: assessment);
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

  @override
  void dispose() {
    for (final c in [_name, _cost, _value, _debt, _creditor, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      allowCancel: !_busy,
      value: () => _snapshot,
      builder: (context, cancel) => MovementFormFrame(
          title: widget.valuationOnly
              ? 'Atualizar avaliação'
              : widget.asset == null
                  ? 'Novo bem'
                  : 'Editar bem',
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
                    if (!widget.valuationOnly) ...[
                      TextFormField(
                          controller: _name,
                          autofocus: true,
                          textInputAction: TextInputAction.next,
                          decoration:
                              const InputDecoration(labelText: 'Nome do bem'),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Informe o nome.'
                              : null),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<AssetKind>(
                          initialValue: _kind,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Tipo de bem'),
                          items: AssetKind.values
                              .map((k) => DropdownMenuItem(
                                  value: k, child: Text(k.label)))
                              .toList(),
                          onChanged: (v) => setState(() => _kind = v!)),
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Data de aquisição'),
                          subtitle: Text(assetDate(_acquired)),
                          trailing: const Icon(Icons.calendar_month),
                          onTap: () => _pick(true)),
                      MonetaryCalculatorField(
                          controller: _cost,
                          labelText: 'Valor de aquisição',
                          minimumMinor: 0),
                      const SizedBox(height: 20),
                    ] else
                      Text(widget.asset!.name,
                          style: Theme.of(context).textTheme.titleLarge),
                    if (_values) ...[
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Data da avaliação'),
                          subtitle: Text(assetDate(_assessed)),
                          trailing: const Icon(Icons.calendar_month),
                          onTap: () => _pick(false)),
                      MonetaryCalculatorField(
                          controller: _value,
                          labelText: 'Valor atual do bem',
                          minimumMinor: 0),
                      const SizedBox(height: 20),
                      if (widget.asset?.managedDebtMinor != null)
                        const Text(
                            'Financiamento controlado em Dívidas e empréstimos. A avaliação altera somente o valor do bem.')
                      else ...[
                        MonetaryCalculatorField(
                            controller: _debt,
                            labelText: 'Saldo devedor do financiamento',
                            minimumMinor: 0),
                        const SizedBox(height: 12),
                        const Text(
                            'Informe o saldo atual devido ao banco, sem somar juros futuros nem repetir dívidas já registradas nos cartões.'),
                        const SizedBox(height: 20),
                        TextFormField(
                            controller: _creditor,
                            decoration: const InputDecoration(
                                labelText: 'Credor / banco do financiamento'),
                            validator: (v) {
                              try {
                                return MoneyMinor.parse(_debt.text) > 0 &&
                                        (v?.trim().isEmpty ?? true)
                                    ? 'Informe o credor.'
                                    : null;
                              } catch (_) {
                                return null;
                              }
                            }),
                        const SizedBox(height: 20),
                      ],
                    ],
                    TextFormField(
                        controller: _notes,
                        maxLines: 3,
                        decoration: const InputDecoration(
                            labelText: 'Observações (opcional)')),
                    const SizedBox(height: 16),
                    const Text(
                        'Cadastro e avaliações não movimentam o saldo das contas. Registre pagamentos e recebimentos nas telas de lançamentos.'),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                  ])))));
}
