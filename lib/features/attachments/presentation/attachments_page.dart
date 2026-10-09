import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../transactions/domain/movement_management.dart';
import '../data/attachments_repository.dart';

Future<void> showAttachments(BuildContext context, MovementReference owner) =>
    Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => AttachmentsPage(
            repository: getIt<AttachmentsRepository>(), owner: owner)));

class AttachmentsPage extends StatefulWidget {
  const AttachmentsPage(
      {super.key, required this.repository, required this.owner});
  final AttachmentsRepository repository;
  final MovementReference owner;
  @override
  State<AttachmentsPage> createState() => _AttachmentsPageState();
}

class _AttachmentsPageState extends State<AttachmentsPage> {
  List<LocalAttachment> _items = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _run(() async {});
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      final items = await widget.repository.list(widget.owner);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is FormatException
            ? e.message.toString()
            : 'Não foi possível concluir. Confira se o lançamento ainda existe e tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() => _run(() async {
        final file = await FilePicker.pickFile(type: FileType.any);
        if (file == null) return;
        if ((await file.length() ?? 0) > AttachmentsRepository.maxBytes) {
          throw const FormatException('Selecione um arquivo de até 20 MB.');
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in file.readAsByteStream()) {
          if (builder.length + chunk.length > AttachmentsRepository.maxBytes) {
            throw const FormatException('Selecione um arquivo de até 20 MB.');
          }
          builder.add(chunk);
        }
        await widget.repository
            .add(widget.owner, file.name, builder.takeBytes());
      });
  Future<void> _save(LocalAttachment item) => _run(() async {
        final bytes = await widget.repository.read(widget.owner, item.id);
        final result = await FilePicker.saveFile(
            fileName: item.name,
            bytes: bytes,
            mimeType: 'application/octet-stream');
        if (result != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Cópia salva.')));
        }
      });
  Future<void> _preview(LocalAttachment item) => _run(() async {
        final bytes = await widget.repository.read(widget.owner, item.id);
        if (!mounted) return;
        await showDialog<void>(
            context: context,
            builder: (context) => Dialog(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(item.name)),
                  Flexible(
                      child: InteractiveViewer(
                          child: Image.memory(bytes,
                              cacheWidth: 1600,
                              errorBuilder: (_, error, stack) => const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                      'Prévia indisponível. Use Salvar cópia para abrir o arquivo em outro aplicativo.'))))),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fechar')),
                ])));
      });
  Future<void> _remove(LocalAttachment item) => _run(() async {
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('Excluir anexo?'),
                    content: Text(
                        'Excluir “${item.name}” deste lançamento? O arquivo original não será alterado.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Excluir'))
                    ]));
        if (confirmed == true) {
          await widget.repository.remove(widget.owner, item.id);
        }
      });
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Anexos')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(children: [
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Arquivos locais, até 20 MB cada. Incluídos no backup completo; ainda não sincronizados entre dispositivos.')),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FilledButton.icon(
                          onPressed: _busy ? null : _add,
                          icon: const Icon(Icons.attach_file),
                          label: const Text('Adicionar arquivo'))),
                  Expanded(
                      child: _items.isEmpty
                          ? const Center(
                              child: Text('Nenhum anexo neste lançamento.'))
                          : ListView.builder(
                              itemCount: _items.length,
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                return ListTile(
                                    leading: const Icon(
                                        Icons.insert_drive_file_outlined),
                                    title: Text(item.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                        '${(item.size / 1024).toStringAsFixed(1)} KB'),
                                    trailing: PopupMenuButton<String>(
                                        enabled: !_busy,
                                        onSelected: (action) {
                                          if (action == 'save') _save(item);
                                          if (action == 'preview') {
                                            _preview(item);
                                          }
                                          if (action == 'delete') _remove(item);
                                        },
                                        itemBuilder: (_) => [
                                              if (RegExp(
                                                      r'\.(png|jpe?g|gif|webp|bmp)$',
                                                      caseSensitive: false)
                                                  .hasMatch(item.name))
                                                const PopupMenuItem(
                                                    value: 'preview',
                                                    child: Text(
                                                        'Visualizar imagem')),
                                              const PopupMenuItem(
                                                  value: 'save',
                                                  child: Text('Salvar cópia')),
                                              const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Text('Excluir anexo')),
                                            ]));
                              })),
                ]))),
      ));
}
