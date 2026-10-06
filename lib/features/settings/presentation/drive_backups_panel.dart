import 'package:flutter/material.dart';
import '../../../core/drive/drive_backup.dart';
import '../../../core/drive/drive_backup_manager.dart';

class DriveBackupsPanel extends StatelessWidget {
  const DriveBackupsPanel(
      {super.key,
      required this.manager,
      this.enabled = true,
      this.onConfigure});
  final DriveBackupManager manager;
  final bool enabled;
  final VoidCallback? onConfigure;

  Future<void> _restore(BuildContext context, DriveCopy copy) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('Restaurar cópia do Drive?'),
              content: Text(
                  'Conta: ${manager.email}\n\nOs dados atuais serão substituídos agora. Uma cópia local será salva antes da substituição. A restauração não mescla os dados.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Restaurar'))
              ],
            ));
    if (confirmed == true && context.mounted && enabled && !manager.busy) {
      await manager.restore(copy);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final active = enabled && !manager.busy;
        return Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Backup no Google Drive',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const Text(
                          'Envio manual de cópias privadas do Somia. Os lançamentos não são sincronizados entre dispositivos.'),
                      if (manager.configurable) ...[
                        if (!manager.configured)
                          const Text(
                              'Importe o JSON do cliente Google do tipo App para computador, criado no mesmo projeto do Android.'),
                        TextButton(
                            onPressed: active ? onConfigure : null,
                            child: Text(manager.configured
                                ? 'Alterar cliente Google'
                                : 'Configurar Google Drive')),
                      ],
                      if (manager.email != null) ...[
                        const SizedBox(height: 8),
                        Text(manager.email!),
                        Wrap(spacing: 8, children: [
                          FilledButton.icon(
                              onPressed: active ? manager.upload : null,
                              icon: const Icon(Icons.cloud_upload_outlined),
                              label: const Text('Enviar backup')),
                          TextButton(
                              onPressed: active ? manager.refresh : null,
                              child: const Text('Atualizar lista')),
                          TextButton(
                              onPressed: active && manager.configured
                                  ? manager.connect
                                  : null,
                              child: const Text('Reconectar')),
                          TextButton(
                              onPressed: active ? manager.disconnect : null,
                              child: const Text('Desconectar')),
                        ]),
                        if (manager.copies.isEmpty && !manager.busy)
                          const Text(
                              'Nenhuma cópia carregada. Atualize a lista para consultar o Drive.'),
                        for (final copy in manager.copies)
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.cloud_done_outlined),
                              title: Text(_date(copy.createdAt.toLocal())),
                              subtitle: Text(
                                  '${(copy.size / 1024).toStringAsFixed(1)} KB'),
                              trailing: IconButton(
                                  tooltip: 'Restaurar cópia do Drive',
                                  icon: const Icon(Icons.restore),
                                  onPressed: active
                                      ? () => _restore(context, copy)
                                      : null)),
                      ] else
                        FilledButton.icon(
                            onPressed: active && manager.configured
                                ? manager.connect
                                : null,
                            icon: const Icon(Icons.cloud_outlined),
                            label: const Text('Conectar conta Google')),
                      if (manager.busy)
                        const Padding(
                            padding: EdgeInsets.all(12),
                            child: LinearProgressIndicator()),
                      if (manager.connecting && manager.configurable)
                        TextButton(
                            onPressed: manager.cancelConnection,
                            child: const Text('Cancelar conexão')),
                      if (manager.error != null)
                        Text(manager.error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      if (manager.message != null) Text(manager.message!),
                    ])));
      });

  String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} às ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
