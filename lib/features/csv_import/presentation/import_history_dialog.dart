import 'package:flutter/material.dart';

import '../domain/import_history.dart';

class ImportHistoryDialog extends StatefulWidget {
  const ImportHistoryDialog({super.key, required this.history});
  final CsvImportHistory history;

  @override
  State<ImportHistoryDialog> createState() => _ImportHistoryDialogState();
}

class _ImportHistoryDialogState extends State<ImportHistoryDialog> {
  late Future<List<ImportBatch>> _batches = widget.history.batches();
  String? _error;

  Future<void> _review(ImportBatch batch) async {
    try {
      final entries = await widget.history.inspectUndo(batch.id);
      if (!mounted) return;
      final chosen = {
        for (final e in entries)
          if (e.canUndo) e.id
      };
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            scrollable: true,
            title: Text('Desfazer ${batch.sourceName}?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Uma cópia de segurança será criada. Itens modificados ficam preservados; vínculos são apenas removidos.'),
                for (final entry in entries)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: chosen.contains(entry.id),
                    onChanged: entry.canUndo
                        ? (v) => update(() {
                              if (v == true) {
                                chosen.add(entry.id);
                              } else {
                                chosen.remove(entry.id);
                              }
                            })
                        : null,
                    title: Text('Linha ${entry.line}: ${entry.description}'),
                    subtitle: Text(entry.reason ??
                        (entry.action == 'linked'
                            ? 'Remover vínculo'
                            : 'Remover lançamento importado')),
                  ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: chosen.isEmpty
                      ? null
                      : () => Navigator.pop(context, true),
                  child: Text('Desfazer ${chosen.length} itens')),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.history.undo(batch.id, chosen);
      if (mounted)
        setState(() {
          _error = null;
          _batches = widget.history.batches();
        });
    } catch (e) {
      if (mounted)
        setState(() => _error = e is FormatException
            ? e.message
            : 'Não foi possível desfazer. Nenhum item foi alterado.');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const Text('Histórico de importações'),
        content: SizedBox(
          width: 500,
          child: FutureBuilder<List<ImportBatch>>(
            future: _batches,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return const Text('Não foi possível carregar o histórico.');
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (snapshot.data!.isEmpty) const Text('Nenhum lote ativo.'),
                  for (final batch in snapshot.data!)
                    ListTile(
                      title: Text(batch.sourceName),
                      subtitle: Text(
                          '${batch.createdAt.day}/${batch.createdAt.month}/${batch.createdAt.year}'),
                      trailing: const Icon(Icons.undo),
                      onTap: () => _review(batch),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'))
        ],
      );
}
