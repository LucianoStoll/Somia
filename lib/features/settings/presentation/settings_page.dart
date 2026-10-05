import '../../../core/drive/drive_backup_manager.dart';
import 'drive_backups_panel.dart';
import 'sync_panel.dart';
import '../../../core/sync/sync_manager.dart';
import '../../../core/sync/auto_sync_controller.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/app_version.dart';
import '../../../core/widgets/balance_help_button.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/backup_service.dart';
import '../../../core/database/backup_manager.dart';
import '../../../core/database/local_backup_store.dart';
import 'local_backups_panel.dart';
import '../../../core/di/injection.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/routing/somia_shell.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  SyncManager? _sync;
  void _syncChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sync?.removeListener(_syncChanged);
    super.dispose();
  }

  BackupManager? get _manager =>
      getIt.isRegistered<BackupManager>() ? getIt<BackupManager>() : null;

  @override
  void initState() {
    super.initState();
    if (getIt.isRegistered<DriveBackupManager>()) {
      getIt<DriveBackupManager>().initialize();
    }
    _manager?.refresh().catchError((Object _) {});
    if (getIt.isRegistered<SyncManager>()) {
      _sync = getIt<SyncManager>();
      _sync!.addListener(_syncChanged);
      _sync!.refresh().catchError((Object _) {});
    }
  }

  Future<void> _localAction(
      Future<void> Function() action, String message) async {
    if (_busy || (_sync?.busy ?? false)) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _message(message);
    } catch (error) {
      if (mounted) {
        _message(error is FormatException
            ? error.message
            : 'Não foi possível concluir. Tente novamente e confira o espaço disponível.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _configureDrive() => _localAction(() async {
        final file = await FilePicker.pickFile(
            type: FileType.custom, allowedExtensions: ['json']);
        if (file == null || !mounted) return;
        if (getIt<DriveBackupManager>().email != null) {
          final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                    scrollable: true,
                    title: const Text('Alterar cliente Google?'),
                    content: const Text(
                        'A conta será desconectada neste computador. As cópias e os dados locais serão mantidos.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Alterar'))
                    ],
                  ));
          if (confirmed != true || !mounted) return;
        }
        await getIt<DriveBackupManager>().configure(await file.readAsBytes());
      }, '');

  Future<void> _exportCopy(LocalBackupCopy copy) => _localAction(() async {
        final bytes = await _manager!.readCopy(copy);
        final saved = await FilePicker.saveFile(
            fileName:
                'somia-backup-${copy.createdAt.microsecondsSinceEpoch}.sqlite',
            bytes: bytes,
            mimeType: 'application/vnd.sqlite3');
        if (saved != null && mounted) _message('Cópia exportada com sucesso.');
      }, '');

  Future<void> _restoreCopy(LocalBackupCopy copy) => _localAction(() async {
        if (!await _confirmRestore() || !mounted) return;
        final bytes = await _manager!.readCopy(copy);
        await _manager!.restore(bytes);
        if (mounted) {
          _message('Backup restaurado. Os dados já estão atualizados.');
        }
      }, '');

  Future<void> _export() async {
    if (_busy || (_sync?.busy ?? false)) return;
    setState(() => _busy = true);
    try {
      final directory = await getApplicationSupportDirectory();
      final bytes = _manager == null
          ? await BackupService.export(getIt<AppDatabase>(), directory)
          : await _manager!.export();
      final now = DateTime.now();
      final date = '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final saved = await FilePicker.saveFile(
        fileName: 'somia-backup-$date.sqlite',
        bytes: bytes,
        mimeType: 'application/vnd.sqlite3',
      );
      if (mounted && saved != null) _message('Backup exportado com sucesso.');
    } catch (error) {
      if (mounted) _message('Não foi possível exportar: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmRestore() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('Restaurar backup?'),
              content: const Text('Os dados atuais serão substituídos agora. '
                  'Uma cópia dos dados atuais será salva automaticamente antes '
                  'da substituição. A restauração não mescla os dados e desvincula a sincronização.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Restaurar')),
              ],
            ));
    return confirmed == true;
  }

  Future<void> _restore() => _localAction(() async {
        final file = await FilePicker.pickFile(type: FileType.any);
        if (file == null || !mounted) return;
        if (!await _confirmRestore() || !mounted) return;
        final bytes = await file.readAsBytes();
        if (_manager == null) {
          await BackupService.restoreOpen(getIt<AppDatabase>(),
              LocalBackupStore(await getApplicationSupportDirectory()), bytes);
        } else {
          await _manager!.restore(bytes);
        }
        if (mounted) {
          _message('Backup restaurado. Os dados já estão atualizados.');
        }
      }, '');

  void _message(String text) {
    if (text.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Ajustes'), leading: somiaMenuLeading(context)),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Text('Somia',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 16),
                  const Card(
                      child: ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('Versão do aplicativo'),
                          subtitle: SelectableText(AppVersion.label))),
                  Card(
                      child: ListTile(
                          leading: const Icon(Icons.help_outline),
                          title: const Text('Entender os saldos'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => showBalanceHelp(context))),
                  const Card(
                      child: ListTile(
                          title: Text('Seus dados'),
                          subtitle: Text(
                              'As informações ficam armazenadas neste dispositivo.'))),
                  Card(
                      child: ListTile(
                          leading: const Icon(Icons.file_upload_outlined),
                          title: const Text('Exportar backup'),
                          subtitle: const Text(
                              'Salve uma cópia do banco local em outro lugar.'),
                          onTap: _busy || (_sync?.busy ?? false)
                              ? null
                              : _export)),
                  Card(
                      child: ListTile(
                          leading: const Icon(Icons.restore_outlined),
                          title: const Text('Restaurar backup'),
                          subtitle: const Text(
                              'Selecione um arquivo .sqlite para atualizar os dados agora.'),
                          onTap: _busy || (_sync?.busy ?? false)
                              ? null
                              : _restore)),
                  if (_manager != null)
                    LocalBackupsPanel(
                        manager: _manager!,
                        enabled: !_busy &&
                            !(getIt.isRegistered<SyncManager>() &&
                                getIt<SyncManager>().busy),
                        onCreate: () => _localAction(() async {
                              await _manager!.create();
                            }, 'Cópia local criada com sucesso.'),
                        onExport: _exportCopy,
                        onRestore: _restoreCopy,
                        onCancel: () => _localAction(_manager!.cancelRestore,
                            'Restauração cancelada. Os dados atuais foram mantidos.')),
                  if (getIt.isRegistered<DriveBackupManager>())
                    DriveBackupsPanel(
                        manager: getIt<DriveBackupManager>(),
                        enabled: !_busy &&
                            !(getIt.isRegistered<SyncManager>() &&
                                getIt<SyncManager>().busy),
                        onConfigure: _configureDrive),
                  if (getIt.isRegistered<SyncManager>())
                    SyncPanel(manager: getIt<SyncManager>(), enabled: !_busy,automatic:getIt.isRegistered<AutoSyncController>()?getIt<AutoSyncController>():null),
                  if (_busy) const Center(child: CircularProgressIndicator()),
                  Card(
                      child: ListTile(
                          leading: const Icon(Icons.category_outlined),
                          title: const Text('Categorias e subcategorias'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.goNamed(AppRoutes.categories))),
                  Card(
                      child: ListTile(
                          leading: const Icon(Icons.swap_horiz),
                          title: const Text('Transferências'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.goNamed(AppRoutes.transfers))),
                ]))),
      );
}
