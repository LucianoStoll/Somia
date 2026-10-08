import 'package:flutter/material.dart';
import '../../../core/money/money_minor.dart';
import '../../../core/widgets/monetary_calculator.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../data/reimbursements_repository.dart';
import '../domain/reimbursement.dart';

Future<String?> editPerson(BuildContext context, ReimbursementsRepository repo,
    {Person? person}) async {
  final value = await showMovementForm<(String, String)>(
      context, (_) => _PersonForm(person: person));
  if (value == null) {
    return null;
  }
  return repo.savePerson(value.$1, id: person?.id, aliases: value.$2);
}

class _PersonForm extends StatefulWidget {
  const _PersonForm({this.person});
  final Person? person;
  @override
  State<_PersonForm> createState() => _PersonFormState();
}

class _PersonFormState extends State<_PersonForm> {
  final key = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.person?.name ?? '');
  late final aliases =
      TextEditingController(text: widget.person?.aliases ?? '');
  @override
  void dispose() {
    name.dispose();
    aliases.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
      value: () => (name.text, aliases.text),
      builder: (context, cancel) => MovementFormFrame(
          title: widget.person == null ? 'Nova pessoa' : 'Editar pessoa',
          compact: true,
          saveLabel: 'Salvar pessoa',
          onCancel: cancel,
          onSave: () {
            if (key.currentState!.validate()) {
              Navigator.pop(context, (name.text, aliases.text));
            }
          },
          child: Form(
              key: key,
              child: Column(children: [
                TextFormField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Nome'),
                    validator: (s) => s == null || s.trim().isEmpty
                        ? 'Informe o nome.'
                        : null),
                TextFormField(
                    controller: aliases,
                    decoration: const InputDecoration(
                        labelText: 'Outros nomes (opcional)'))
              ]))));
}

class ReimbursementEditor extends StatefulWidget {
  const ReimbursementEditor(
      {super.key,
      required this.repo,
      required this.onChanged,
      this.movementId,
      this.currency = 'BRL'});
  final ReimbursementsRepository repo;
  final String? movementId;
  final String currency;
  final ValueChanged<List<ReimbursementDraft>> onChanged;
  @override
  State<ReimbursementEditor> createState() => _ReimbursementEditorState();
}

class _ClaimInput {
  _ClaimInput({this.id, this.personId, int amount = 0})
      : amount = TextEditingController(text: MoneyMinor.plain(amount));
  final String? id;
  String? personId;
  final TextEditingController amount;
}

class _ReimbursementEditorState extends State<ReimbursementEditor> {
  List<Person> people = [];
  final rows = <_ClaimInput>[];
  bool loading = true, enabled = false;
  Object? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final persons = await widget.repo.people();
      final drafts = widget.movementId == null
          ? <ReimbursementDraft>[]
          : await widget.repo.drafts(widget.movementId!);
      if (!mounted) {
        return;
      }
      setState(() {
        people = persons;
        enabled = drafts.isNotEmpty;
        for (final d in drafts) {
          rows.add(_input(id: d.id, person: d.personId, amount: d.amountMinor));
        }
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  _ClaimInput _input({String? id, String? person, int amount = 0}) {
    final row = _ClaimInput(id: id, personId: person, amount: amount);
    row.amount.addListener(changed);
    return row;
  }

  void changed() {
    widget.onChanged(enabled
        ? rows
            .map((r) => ReimbursementDraft(
                r.personId ?? '', MoneyMinor.parse(r.amount.text),
                id: r.id))
            .toList()
        : []);
  }

  @override
  void dispose() {
    for (final r in rows) {
      r.amount.dispose();
    }
    super.dispose();
  }

  Future<void> addPerson() async {
    try {
      final id = await editPerson(context, widget.repo);
      if (id == null) {
        return;
      }
      final p = await widget.repo.people();
      if (!mounted) {
        return;
      }
      setState(() {
        people = p;
        rows.add(_input(person: id));
      });
      changed();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        FormField<bool>(
            validator: (_) => loading
                ? 'Aguarde carregar os reembolsos.'
                : error != null
                    ? 'Não foi possível carregar reembolsos. Reabra o formulário.'
                    : enabled && rows.isEmpty
                        ? 'Adicione a pessoa e o valor a receber.'
                        : null,
            builder: (field) =>
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Reembolso'),
                      subtitle: loading ? const Text('Carregando…') : null,
                      value: enabled,
                      onChanged: loading || error != null
                          ? null
                          : (v) {
                              setState(() {
                                enabled = v;
                                if (v && rows.isEmpty) rows.add(_input());
                              });
                              changed();
                            }),
                  if (field.hasError)
                    Text(field.errorText!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))
                ])),
        if (enabled && !loading) ...[
          const Text(
              'A despesa fica integral. Recebimentos são receitas vinculadas.'),
          for (final r in rows)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: DropdownButtonFormField<String>(
                            key: ObjectKey(r),
                            initialValue: r.personId,
                            isExpanded: true,
                            menuMaxHeight: 280,
                            itemHeight: 48,
                            borderRadius: BorderRadius.circular(16),
                            decoration:
                                const InputDecoration(labelText: 'Pessoa'),
                            items: people
                                .where((p) => !p.archived || p.id == r.personId)
                                .map((p) => DropdownMenuItem(
                                    value: p.id,
                                    child: Text(
                                        '${p.name}${p.archived ? ' (arquivada)' : ''}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            validator: (v) =>
                                v == null ? 'Selecione a pessoa.' : null,
                            onChanged: (v) {
                              setState(() => r.personId = v);
                              changed();
                            })),
                    IconButton(
                        tooltip: 'Remover pessoa do reembolso',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() => rows.remove(r));
                          r.amount.dispose();
                          changed();
                        })
                  ]),
                  MonetaryCalculatorField(
                      controller: r.amount,
                      currencyCode: widget.currency,
                      labelText: 'Valor a receber'),
                ])),
          Wrap(spacing: 8, children: [
            TextButton.icon(
                onPressed: () {
                  setState(() => rows.add(_input()));
                  changed();
                },
                icon: const Icon(Icons.add),
                label: const Text('Adicionar pessoa')),
            TextButton.icon(
                onPressed: addPerson,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Cadastrar pessoa'))
          ]),
        ],
      ]);
}
