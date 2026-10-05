import 'package:flutter/material.dart';
import '../core/database/backup_manager.dart';
import '../core/database/backup_lifecycle.dart';
import '../core/di/injection.dart';
import '../core/routing/app_router.dart';
import '../core/theme/app_theme.dart';
import '../core/sync/auto_sync_controller.dart';
import '../core/sync/sync_lifecycle.dart';

class FinApp extends StatefulWidget {
  const FinApp({super.key});

  @override
  State<FinApp> createState() => _FinAppState();
}

class _FinAppState extends State<FinApp> {
  BackupManager? _manager;
  AutoSyncController? _auto;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    if(getIt.isRegistered<AutoSyncController>())_auto=getIt<AutoSyncController>();
    if (getIt.isRegistered<BackupManager>()) {
      _manager = getIt<BackupManager>();
      _revision = _manager!.databaseRevision;
      _manager!.addListener(_databaseChanged);
    }
  }

  void _databaseChanged() {
    if (_manager!.databaseRevision != _revision) {
      final previous = appRouter;
      appRouter = createAppRouter(initialLocation:_manager!.preserveLocation?previous.routeInformationProvider.value.uri.toString():AppRoutes.settingsPath);
      _revision = _manager!.databaseRevision;
      // Descarta páginas, formulários e navegação associados à base anterior.
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
    if (_manager!.restoring) FocusManager.instance.primaryFocus?.unfocus();
    setState(() {});
  }

  @override
  void dispose() {
    _manager?.removeListener(_databaseChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp.router(
      key: ValueKey(_revision),
      title: 'Somia',
      debugShowCheckedModeBanner: false,
      darkTheme: AppTheme.dark,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
      builder: (context, child) => Stack(children: [
        ExcludeFocus(
          excluding: _manager?.restoring ?? false,
          child: child!,
        ),
        if (_manager?.restoring ?? false) ...[
          const ModalBarrier(dismissible: false, color: Colors.black54),
          const Center(
              child: Card(
                  child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Atualizando dados…'),
            ]),
          ))),
        ],
      ]),
    );
    final child=_auto==null?app:SyncLifecycle(controller:_auto!,child:app);
    return _manager != null
        ? BackupLifecycle(manager: _manager!, child: child)
        : child;
  }
}
