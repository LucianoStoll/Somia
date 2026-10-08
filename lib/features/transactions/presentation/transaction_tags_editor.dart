import 'package:flutter/material.dart';
import '../../../core/database/app_database.dart';
import '../../../core/di/injection.dart';
import '../domain/transaction_tags.dart';

class TransactionTagsEditor extends StatefulWidget {
  const TransactionTagsEditor(
      {super.key, required this.tags, required this.onChanged});
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  @override
  State<TransactionTagsEditor> createState() => _TransactionTagsEditorState();
}

class _TransactionTagsEditorState extends State<TransactionTagsEditor> {
  final _input = TextEditingController();
  List<String> _suggestions = [];
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!getIt.isRegistered<AppDatabase>()) return;
    try {
      final rows = await getIt<AppDatabase>()
          .customSelect(
              'SELECT tags_json FROM transactions WHERE deleted_at IS NULL UNION ALL SELECT tags_json FROM card_entries WHERE deleted_at IS NULL')
          .get();
      final unique = <String, String>{};
      for (final row in rows) {
        for (final tag
            in TransactionTags.decode(row.read<String>('tags_json'))) {
          unique.putIfAbsent(TransactionTags.key(tag), () => tag);
        }
      }
      if (mounted) {
        setState(() => _suggestions = unique.values.toList()..sort());
      }
    } catch (_) {
      /* Suggestions are optional; manual entry remains available. */
    }
  }

  void _add(String value) {
    try {
      final tags = TransactionTags.normalize([...widget.tags, value]);
      widget.onChanged(tags);
      _input.clear();
      setState(() => _error = null);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFormField(
            controller: _input,
            validator: (value) => (value?.trim().isNotEmpty ?? false)
                ? 'Toque em + para adicionar a tag ou limpe o campo.'
                : null,
            maxLength: 40,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
                labelText: 'Tags',
                hintText: 'Digite uma etiqueta',
                errorText: _error,
                counterText: '',
                suffixIcon: IconButton(
                    tooltip: 'Adicionar tag',
                    onPressed: () => _add(_input.text),
                    icon: const Icon(Icons.add))),
            onChanged: (_) => setState(() {}),
            onFieldSubmitted: _add),
        Wrap(spacing: 6, children: [
          for (final tag in widget.tags)
            InputChip(
                label: Text(tag),
                onDeleted: () => widget
                    .onChanged(widget.tags.where((t) => t != tag).toList()))
        ]),
        if (_input.text.trim().isNotEmpty)
          Wrap(spacing: 6, children: [
            for (final tag in _suggestions
                .where((t) =>
                    TransactionTags.key(t)
                        .contains(TransactionTags.key(_input.text)) &&
                    !widget.tags.any((v) =>
                        TransactionTags.key(v) == TransactionTags.key(t)))
                .take(6))
              ActionChip(label: Text(tag), onPressed: () => _add(tag))
          ]),
      ]);
}
