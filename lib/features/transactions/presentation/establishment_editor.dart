import 'package:flutter/material.dart';
import '../../../core/database/app_database.dart';
import '../../../core/di/injection.dart';
import '../domain/establishment.dart';

class EstablishmentEditor extends StatefulWidget {
  const EstablishmentEditor(
      {super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  State<EstablishmentEditor> createState() => _EstablishmentEditorState();
}

class _EstablishmentEditorState extends State<EstablishmentEditor> {
  late final TextEditingController _input;
  List<String> _suggestions = [];
  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.value);
    _load();
  }

  Future<void> _load() async {
    if (!getIt.isRegistered<AppDatabase>()) return;
    try {
      final rows = await getIt<AppDatabase>()
          .customSelect(
              "SELECT establishment FROM transactions WHERE deleted_at IS NULL AND establishment<>'' UNION ALL SELECT establishment FROM card_entries WHERE deleted_at IS NULL AND establishment<>''")
          .get();
      final unique = <String, String>{};
      for (final row in rows) {
        final name = Establishment.normalize(row.read<String>('establishment'));
        unique.putIfAbsent(Establishment.key(name), () => name);
      }
      final values = unique.values.toList()
        ..sort((a, b) => Establishment.key(a).compareTo(Establishment.key(b)));
      if (mounted) {
        setState(() => _suggestions = values);
      }
    } catch (_) {
      /* Suggestions are optional; manual entry remains available. */
    }
  }

  void _choose(String value) {
    _input.text = value;
    widget.onChanged(value);
    setState(() {});
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
            maxLength: 100,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
                labelText: 'Estabelecimento',
                hintText: 'Ex.: Mercado, farmácia ou empresa',
                counterText: '',
                suffixIcon: IconButton(
                    tooltip: 'Limpar estabelecimento',
                    onPressed: () => _choose(''),
                    icon: const Icon(Icons.close))),
            validator: (value) {
              try {
                Establishment.normalize(value ?? '');
                return null;
              } on FormatException catch (e) {
                return e.message;
              }
            },
            onChanged: (value) {
              widget.onChanged(value);
              setState(() {});
            }),
        if (_input.text.trim().isNotEmpty)
          Wrap(spacing: 6, children: [
            for (final name in _suggestions
                .where((s) =>
                    s
                        .toLowerCase()
                        .contains(_input.text.trim().toLowerCase()) &&
                    s.toLowerCase() != _input.text.trim().toLowerCase())
                .take(6))
              ActionChip(label: Text(name), onPressed: () => _choose(name))
          ]),
      ]);
}
