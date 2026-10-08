import '../../../core/drive/drive_backup_manager.dart';
import '../../csv_import/domain/csv_import.dart';
import '../../csv_import/presentation/csv_import_page.dart';
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
  const SettingsPage({super.key, this.section});
  final String? section;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  SyncManager? _sync;
  BackupManager? _local;
  void _syncChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sync?.removeListener(_syncChanged);
    _local?.removeListener(_syncChanged);
    super.dispose();
  }

  BackupManager? get _manager =>
      getIt.isRegistered<BackupManager>() ? getIt<BackupManager>() : null;

  @override
  void initState() {
    super.initState();
    _local = _manager;
    _local?.addListener(_syncChanged);
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

  Future<void> _importCsv() async {
    if (_busy || (_sync?.busy ?? false) || (_manager?.busy ?? false)) return;
    final result = await Navigator.of(context, rootNavigator: true)
        .push<CsvImportResult>(MaterialPageRoute(
            builder: (_) =>
                CsvImportPage(repository: getIt<CsvImportRepository>())));
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (result.imported > 0 && _manager != null) {
      try {
        await _manager!.maintain(() async {}, preserveLocation: true);
      } catch (_) {
        messenger.showSnackBar(const SnackBar(
            content: Text(
                'Lançamentos importados. Reabra a seção para atualizar a lista.')));
        return;
      }
    }
    messenger.showSnackBar(SnackBar(
        content: Text(
            '${result.imported} lançamentos importados.${result.skipped == 0 ? '' : ' ${result.skipped} duplicados ignorados após nova conferência.'}')));
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

  Widget _heading(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 12),
      child: Text(label,
          style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600)));

  Widget _option(String label, IconData icon, VoidCallback? onTap,
          {String? subtitle}) =>
      ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).dividerColor)),
              child: Icon(icon, size: 22)),
          title: Text(label),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap);

  void _open(String section) =>
      context.go('${AppRoutes.settingsPath}?section=$section');

  List<Widget> _content(String? section) {
    final disabled = _busy || (_sync?.busy ?? false);
    switch (section) {
      case 'local':
        return [
          _option('Exportar backup', Icons.file_upload_outlined,
              disabled ? null : _export),
          _option('Restaurar backup', Icons.restore_outlined,
              disabled ? null : _restore),
          if (_manager != null)
            LocalBackupsPanel(
                manager: _manager!,
                enabled: !disabled,
                onCreate: () => _localAction(() async {
                      await _manager!.create();
                    }, 'Cópia local criada com sucesso.'),
                onExport: _exportCopy,
                onRestore: _restoreCopy,
                onCancel: () => _localAction(_manager!.cancelRestore,
                    'Restauração cancelada. Os dados atuais foram mantidos.')),
        ];
      case 'drive':
        return [
          if (getIt.isRegistered<DriveBackupManager>())
            DriveBackupsPanel(
                manager: getIt<DriveBackupManager>(),
                enabled: !disabled,
                onConfigure: _configureDrive)
        ];
      case 'sync':
        return [
          if (_sync != null)
            SyncPanel(
                manager: _sync!,
                enabled: !_busy,
                automatic: getIt.isRegistered<AutoSyncController>()
                    ? getIt<AutoSyncController>()
                    : null)
        ];
      default:
        return [
          if ((_manager?.databaseRevision ?? 0) > 0)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child:
                    Text('Backup restaurado. Os dados já estão atualizados.')),
          _heading('Finanças'),
          _option('Planejamento', Icons.flag_outlined,
              () => context.go(AppRoutes.planningPath)),
          _option('Pessoas e reembolsos', Icons.people_outline,
              () => context.go(AppRoutes.reimbursementsPath)),
          _option('Contas', Icons.account_balance_outlined,
              () => context.goNamed(AppRoutes.accounts)),
          _option('Categorias e subcategorias', Icons.category_outlined,
              () => context.goNamed(AppRoutes.categories)),
          _option('Receitas', Icons.arrow_circle_up_outlined,
              () => context.goNamed(AppRoutes.income)),
          _option('Despesas', Icons.arrow_circle_down_outlined,
              () => context.goNamed(AppRoutes.expenses)),
          _option('Transferências', Icons.swap_horiz,
              () => context.goNamed(AppRoutes.transfers)),
          _option('Cartões', Icons.credit_card_outlined,
              () => context.goNamed(AppRoutes.cards)),
          _heading('Dados e utilidades'),
          if (getIt.isRegistered<CsvImportRepository>())
            _option('Importar extrato CSV', Icons.file_download_outlined,
                disabled || (_manager?.busy ?? false) ? null : _importCsv),
          _option('Backup e restauração', Icons.restore_outlined,
              () => _open('local'),
              subtitle: 'Cópias locais e recuperação dos dados'),
          if (getIt.isRegistered<DriveBackupManager>())
            _option('Google Drive', Icons.cloud_outlined, () => _open('drive')),
          if (_sync != null)
            _option('Sincronização', Icons.sync, () => _open('sync')),
          _heading('Ajuda e aplicativo'),
          _option('Entender os saldos', Icons.help_outline,
              () => showBalanceHelp(context)),
          const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.info_outline),
              title: Text('Versão do aplicativo'),
              subtitle: SelectableText(AppVersion.label)),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final title = switch (section) {
      'local' => 'Backup e restauração',
      'drive' => 'Google Drive',
      'sync' => 'Sincronização',
      _ => 'Configurações',
    };
    return Scaffold(
        appBar: AppBar(
            title: Text(title),
            leading: section == null
                ? somiaMenuLeading(context)
                : BackButton(
                    onPressed: () => context.go(AppRoutes.settingsPath))),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    children: [
                      ..._content(section),
                      if (_busy)
                        const Center(child: CircularProgressIndicator())
                    ]))));
  }
}
