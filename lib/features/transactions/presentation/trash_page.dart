import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/routing/somia_shell.dart';
import '../../accounts/domain/money_minor.dart';
import '../data/movement_management_repository.dart';
import '../domain/movement_management.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});
  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<TrashedMovement> _items = [];
  final Set<String> _selected = {};
  bool _loading = true, _acting = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await getIt<MovementManagementRepository>().listTrash();
      if (mounted)
        setState(() {
          _items = items;
          _selected.clear();
          _loading = false;
          _error = null;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _error = '$error';
          _loading = false;
        });
    }
  }

  Future<void> _act(bool restore) async {
    final refs = _items
        .where((item) => _selected.contains(item.ref.key))
        .map((item) => item.ref)
        .toList();
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(restore
                    ? 'Restaurar ${refs.length} lançamento(s)?'
                    : 'Excluir definitivamente ${refs.length} lançamento(s)?'),
                content: Text(restore
                    ? 'Os movimentos voltarão aos saldos, faturas e relatórios com seus dados e históricos.'
                    : 'Estes movimentos não poderão mais ser restaurados pela lixeira. Esta ação não pode ser desfeita.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                          restore ? 'Restaurar' : 'Excluir definitivamente'))
                ]));
    if (accepted != true || !mounted) return;
    setState(() => _acting = true);
    try {
      final repo = getIt<MovementManagementRepository>();
      if (restore) {
        await repo.restore(refs);
      } else {
        await repo.purge(refs);
      }
      await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Lixeira'), leading: somiaMenuLeading(context)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: TextButton(
                      onPressed: _load,
                      child: Text('$_error · Tentar novamente')))
              : Column(children: [
                  const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                          'Lançamentos excluídos ficam aqui até você restaurar ou excluir definitivamente.')),
                  if (_items.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          TextButton(
                              onPressed: _acting
                                  ? null
                                  : () => setState(() => _selected.addAll(
                                      _items.map((item) => item.ref.key))),
                              child: const Text('Selecionar todos')),
                          TextButton(
                              onPressed: _acting
                                  ? null
                                  : () => setState(_selected.clear),
                              child: const Text('Limpar seleção')),
                          FilledButton.icon(
                              onPressed: _selected.isEmpty || _acting
                                  ? null
                                  : () => _act(true),
                              icon: const Icon(Icons.restore),
                              label: Text('Restaurar (${_selected.length})')),
                          OutlinedButton.icon(
                              onPressed: _selected.isEmpty || _acting
                                  ? null
                                  : () => _act(false),
                              icon: const Icon(Icons.delete_forever),
                              label: const Text('Excluir definitivamente')),
                        ])),
                  if (_acting) const LinearProgressIndicator(),
                  Expanded(
                      child: _items.isEmpty
                          ? const Center(child: Text('A lixeira está vazia.'))
                          : ListView.builder(
                              itemCount: _items.length,
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                return CheckboxListTile(
                                    value: _selected.contains(item.ref.key),
                                    onChanged: _acting
                                        ? null
                                        : (value) => setState(() {
                                              if (value == true) {
                                                _selected.add(item.ref.key);
                                              } else {
                                                _selected.remove(item.ref.key);
                                              }
                                            }),
                                    title: Text(item.description),
                                    subtitle: Text(
                                        '${item.contextLabel}\nExcluído em ${item.deletedAt.day}/${item.deletedAt.month}/${item.deletedAt.year}'),
                                    isThreeLine: true,
                                    secondary: Text(MoneyMinor.display(
                                        item.amountMinor, item.currencyCode)));
                              })),
                ]));
}
