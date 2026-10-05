import 'package:flutter/material.dart';
import '../../../core/database/backup_manager.dart';
import '../../../core/database/local_backup_store.dart';

String backupDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String backupKind(BackupKind kind) => switch (kind) {
      BackupKind.automatic => 'Automático',
      BackupKind.manual => 'Manual',
      BackupKind.beforeRestore => 'Antes de restaurar',
    };

class LocalBackupsPanel extends StatelessWidget {
  const LocalBackupsPanel(
      {super.key,
      required this.manager,
      this.enabled = true,
      required this.onCreate,
      required this.onExport,
      required this.onRestore,
      required this.onCancel});
  final BackupManager manager;
  final bool enabled;
  final VoidCallback onCreate, onCancel;
  final void Function(LocalBackupCopy) onExport, onRestore;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: manager,
      builder: (context, _) => Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Backups neste dispositivo',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text(
                        'Uma cópia por dia enquanto o app estiver aberto. Mantemos as três cópias automáticas mais recentes.'),
                    const SizedBox(height: 8),
                    const Text(
                        'As cópias manuais são mantidas. Guardamos também as três proteções mais recentes de restauração. Exporte uma cópia para guardar fora deste dispositivo.'),
                    const SizedBox(height: 8),
                    if (manager.error != null) ...[
                      Text(manager.error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                      TextButton(
                          onPressed:
                              (manager.busy || !enabled) ? null : manager.daily,
                          child:
                              const Text('Tentar backup automático novamente')),
                    ],
                    if (manager.databaseRevision > 0)
                      const Text(
                          'Backup restaurado. Os dados já estão atualizados.'),
                    if (manager.restorePending) ...[
                      if (manager.restoreFailed)
                        const Text(
                            'A restauração não pôde ser aplicada. Os dados atuais foram mantidos. Você pode cancelar e preparar outra cópia.'),
                      const Text(
                          'Restauração preparada. Feche e abra o Somia para aplicar. Uma cópia dos dados atuais será salva antes da substituição.'),
                      TextButton(
                          onPressed:
                              (manager.busy || !enabled) ? null : onCancel,
                          child: const Text('Cancelar restauração preparada')),
                    ],
                    TextButton.icon(
                        onPressed: (manager.busy || !enabled) ? null : onCreate,
                        icon: const Icon(Icons.backup_outlined),
                        label: const Text('Criar cópia agora')),
                    if (manager.busy) const LinearProgressIndicator(),
                    if (manager.copies.isEmpty && !manager.busy)
                      const Text('Nenhuma cópia local disponível.'),
                    for (final copy in manager.copies)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(backupKind(copy.kind)),
                          subtitle: Text(
                              '${backupDate(copy.createdAt)} · ${(copy.size / 1024).toStringAsFixed(1).replaceAll('.', ',')} KB'),
                          trailing: PopupMenuButton<String>(
                              tooltip:
                                  'Opções da cópia de ${backupDate(copy.createdAt)}',
                              enabled: !manager.busy && enabled,
                              onSelected: (value) => value == 'export'
                                  ? onExport(copy)
                                  : onRestore(copy),
                              itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'export',
                                        child: Text('Exportar cópia')),
                                    PopupMenuItem(
                                        value: 'restore',
                                        child: Text('Restaurar esta cópia')),
                                  ])),
                  ]))));
}
