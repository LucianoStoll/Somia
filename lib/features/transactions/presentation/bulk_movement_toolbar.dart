import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../data/movement_management_repository.dart';
import '../domain/movement_management.dart';

class BulkMovementToolbar extends StatelessWidget {
  const BulkMovementToolbar({
    super.key,
    required this.selection,
    required this.available,
    required this.onSelection,
    required this.onCompleted,
    this.onCancel,
    this.transfer = false,
    this.card = false,
  });
  final Map<String, MovementReference> selection;
  final List<MovementReference> available;
  final ValueChanged<Map<String, MovementReference>> onSelection;
  final Future<void> Function() onCompleted;
  final VoidCallback? onCancel;
  final bool transfer, card;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${selection.length} selecionado(s)'),
            if (onCancel != null)
              TextButton(
                onPressed: onCancel,
                child: const Text('Cancelar seleção'),
              ),
            TextButton(
              onPressed: () =>
                  onSelection({for (final ref in available) ref.key: ref}),
              child: const Text('Selecionar todos'),
            ),
            if (selection.isNotEmpty) ...[
              TextButton(
                onPressed: () => onSelection({}),
                child: const Text('Limpar seleção'),
              ),
              OutlinedButton.icon(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar em lote'),
              ),
              OutlinedButton.icon(
                onPressed: () => _trash(context),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Mover para lixeira'),
              ),
            ],
          ],
        ),
      );
  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      onSelection({});
      await onCompleted();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Operação concluída.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _trash(BuildContext context) async {
    final refs = selection.values.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mover ${refs.length} lançamento(s) para a lixeira?'),
        content: const Text(
          'Somente as ocorrências selecionadas serão removidas dos saldos e relatórios. Você poderá restaurá-las na lixeira.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mover para lixeira'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _run(
        context,
        () => getIt<MovementManagementRepository>().trash(refs),
      );
    }
  }

  Future<void> _edit(BuildContext context) async {
    final refs = selection.values.toList();
    final patch = await showDialog<BulkMovementPatch>(
      context: context,
      builder: (_) => BulkMovementDialog(
        count: refs.length,
        transfer: transfer,
        card: card,
      ),
    );
    if (patch != null && context.mounted) {
      await _run(
        context,
        () => getIt<MovementManagementRepository>().apply(refs, patch),
      );
    }
  }
}

class SelectableMovementRow extends StatelessWidget {
  const SelectableMovementRow({
    super.key,
    required this.ref,
    required this.selection,
    required this.onSelection,
    required this.child,
  });
  final MovementReference ref;
  final Map<String, MovementReference> selection;
  final ValueChanged<Map<String, MovementReference>> onSelection;
  final Widget child;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: selection.containsKey(ref.key),
            semanticLabel: 'Selecionar lançamento',
            onChanged: (value) {
              final next = {...selection};
              if (value == true) {
                next[ref.key] = ref;
              } else {
                next.remove(ref.key);
              }
              onSelection(next);
            },
          ),
          Expanded(child: child),
        ],
      );
}

class BulkMovementDialog extends StatefulWidget {
  const BulkMovementDialog({
    super.key,
    required this.count,
    this.transfer = false,
    this.card = false,
  });
  final int count;
  final bool transfer, card;
  @override
  State<BulkMovementDialog> createState() => _BulkMovementDialogState();
}

class _BulkMovementDialogState extends State<BulkMovementDialog> {
  final _description = TextEditingController(),
      _amount = TextEditingController(),
      _establishment = TextEditingController(),
      _add = TextEditingController(),
      _remove = TextEditingController();
  final _enabled = <String>{};
  String? _error;
  List<({String id, String label})> _accounts = [], _categories = [];
  String? _accountId, _destinationAccountId, _categoryId;
  bool _changeCategory = false;
  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final repo = getIt<MovementManagementRepository>();
      final accounts = await repo.accountOptions();
      final categories = await repo.categoryOptions();
      if (mounted) {
        setState(() {
          _accounts = accounts;
          _categories = categories;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Widget _options(
    String label,
    List<({String id, String label})> values,
    ValueChanged<String?> change, {
    String? selected,
  }) =>
      DropdownButtonFormField<String>(
        key: ValueKey('$label/$selected'),
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem(
            value: '',
            child: Text(
              label.startsWith('Categoria')
                  ? 'Sem categoria'
                  : 'Manter conta atual',
            ),
          ),
          ...values.map(
            (item) => DropdownMenuItem(
              value: item.id,
              child: Text(item.label, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (value) => change(value == '' ? null : value),
      );
  DateTime? _posted, _due, _effectiveDate;
  bool? _effective;
  @override
  void dispose() {
    for (final controller in [
      _description,
      _amount,
      _establishment,
      _add,
      _remove,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(String key, String label, TextEditingController controller) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            value: _enabled.contains(key),
            onChanged: (value) => setState(() {
              if (value == true) {
                _enabled.add(key);
              } else {
                _enabled.remove(key);
              }
            }),
          ),
          if (_enabled.contains(key))
            TextField(
              controller: controller,
              decoration: InputDecoration(labelText: label),
              keyboardType: key == 'amount'
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
            ),
        ],
      );
  Widget _date(String label, DateTime? value, ValueChanged<DateTime?> change) =>
      TextButton.icon(
        icon: const Icon(Icons.calendar_today_outlined),
        label: Text(
          value == null
              ? 'Alterar $label'
              : '$label: ${value.day}/${value.month}/${value.year}',
        ),
        onPressed: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime(2100, 12, 31),
          );
          if (date != null && mounted) setState(() => change(date));
        },
      );
  void _save() {
    try {
      int? amount;
      if (_enabled.contains('amount')) {
        final raw = _amount.text.trim().replaceAll(',', '.');
        if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(raw)) {
          throw const FormatException(
            'Informe um valor positivo com até duas casas decimais.',
          );
        }
        final parts = raw.split('.');
        amount = int.parse(parts[0]) * 100 +
            (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
        if (amount <= 0 || amount > 9000000000000000) {
          throw const FormatException('Valor inválido.');
        }
      }
      if (_enabled.contains('description') &&
          _description.text.trim().isEmpty) {
        throw const FormatException('Informe uma descrição.');
      }
      final patch = BulkMovementPatch(
        description:
            _enabled.contains('description') ? _description.text.trim() : null,
        amountMinor: amount,
        establishment:
            _enabled.contains('establishment') ? _establishment.text : null,
        addTags: _enabled.contains('add') ? _add.text.split(',') : [],
        removeTags: _enabled.contains('remove') ? _remove.text.split(',') : [],
        accountId: _accountId,
        destinationAccountId: _destinationAccountId,
        changeCategory: _changeCategory,
        categoryId: _categoryId,
        postedDate: _posted,
        dueDate: _due,
        effective: _effective,
        effectiveDate: _effectiveDate,
      );
      if (patch.isEmpty) {
        throw const FormatException('Escolha pelo menos um campo.');
      }
      Navigator.pop(context, patch);
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Editar ${widget.count} lançamento(s)'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Marque apenas os campos que deseja alterar. Os demais serão preservados. A alteração vale somente para as ocorrências selecionadas.',
                ),
                if (widget.card)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'A alteração também afeta faturas já pagas. Confira os valores antes de aplicar.',
                    ),
                  ),
                if (!widget.card) ...[
                  _options(
                    widget.transfer
                        ? 'Alterar conta de origem'
                        : 'Alterar conta',
                    _accounts,
                    (value) => setState(() => _accountId = value),
                    selected: _accountId,
                  ),
                  if (widget.transfer)
                    _options(
                      'Alterar conta de destino',
                      _accounts,
                      (value) => setState(() => _destinationAccountId = value),
                      selected: _destinationAccountId,
                    ),
                ],
                if (!widget.transfer) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Alterar categoria'),
                    value: _changeCategory,
                    onChanged: (value) =>
                        setState(() => _changeCategory = value ?? false),
                  ),
                  if (_changeCategory) ...[
                    _options(
                      'Categoria (vazio para remover)',
                      _categories,
                      (value) => setState(() => _categoryId = value),
                      selected: _categoryId,
                    ),
                    TextButton(
                      onPressed: () => setState(() => _categoryId = null),
                      child: const Text('Remover categoria'),
                    ),
                  ],
                ],
                _field('description', 'Descrição', _description),
                _field('amount', 'Valor por lançamento', _amount),
                if (!widget.transfer) ...[
                  _field(
                    'establishment',
                    'Estabelecimento (vazio para limpar)',
                    _establishment,
                  ),
                  _field('add', 'Adicionar tags (separadas por vírgula)', _add),
                  _field('remove', 'Remover tags (separadas por vírgula)',
                      _remove),
                ],
                if (!widget.card) ...[
                  _date(
                      'data de lançamento', _posted, (date) => _posted = date),
                  _date('vencimento', _due, (date) => _due = date),
                  DropdownButtonFormField<bool>(
                    key: ValueKey(_effective),
                    decoration: const InputDecoration(labelText: 'Efetivação'),
                    initialValue: _effective,
                    items: const [
                      DropdownMenuItem(child: Text('Manter efetivação atual')),
                      DropdownMenuItem(value: true, child: Text('Efetivar')),
                      DropdownMenuItem(
                        value: false,
                        child: Text('Marcar como pendente'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _effective = value),
                  ),
                  if (_effective == true)
                    _date(
                      'data de efetivação',
                      _effectiveDate,
                      (date) => _effectiveDate = date,
                    ),
                ],
                if (_posted != null || _due != null || _effective != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _posted = null;
                      _due = null;
                      _effective = null;
                      _effectiveDate = null;
                    }),
                    child: const Text('Manter datas e efetivação atuais'),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
              onPressed: _save, child: const Text('Aplicar alterações')),
        ],
      );
}
