import 'package:flutter/material.dart';
import '../core/database/backup_manager.dart';
import '../core/database/backup_lifecycle.dart';
import '../core/di/injection.dart';
import '../core/routing/app_router.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../core/sync/auto_sync_controller.dart';
import '../core/sync/sync_lifecycle.dart';

class FinApp extends StatefulWidget {
  const FinApp({super.key});

  @override
  State<FinApp> createState() => _FinAppState();
}

class _FinAppState extends State<FinApp> with WidgetsBindingObserver {
  BackupManager? _manager;
  late final ThemeController _theme = getIt.isRegistered<ThemeController>()
      ? getIt<ThemeController>()
      : ThemeController();
  AutoSyncController? _auto;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _theme.addListener(_themeChanged);
    if (getIt.isRegistered<AutoSyncController>()) {
      _auto = getIt<AutoSyncController>();
    }
    if (getIt.isRegistered<BackupManager>()) {
      _manager = getIt<BackupManager>();
      _revision = _manager!.databaseRevision;
      _manager!.addListener(_databaseChanged);
    }
  }

  void _databaseChanged() {
    if (_manager!.databaseRevision != _revision) {
      final previous = appRouter;
      appRouter = createAppRouter(
          initialLocation: _manager!.preserveLocation
              ? previous.routeInformationProvider.value.uri.toString()
              : AppRoutes.settingsPath);
      _revision = _manager!.databaseRevision;
      // Descarta páginas, formulários e navegação associados à base anterior.
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
    if (_manager!.restoring) FocusManager.instance.primaryFocus?.unfocus();
    setState(() {});
  }

  @override
  void didChangePlatformBrightness() {
    if (_theme.mode == ThemeMode.system) _themeChanged();
  }

  void _themeChanged() => setState(() {});

  /// Tokens do tema efetivo, considerando a escolha do usuário e o sistema.
  SomiaTokens _effectiveTokens() {
    final platform =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final dark = switch (_theme.mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platform == Brightness.dark,
    };
    return dark ? SomiaTokens.dark : SomiaTokens.light;
  }

  /// Telas antigas leem `SomiaColors` fora do `Theme`; ao trocar de tema,
  /// reconstrói a árvore inteira preservando estado (formulários, rolagem).
  void _rebuildEverything() {
    void mark(Element element) {
      element.markNeedsBuild();
      element.visitChildren(mark);
    }

    if (mounted) (context as Element).visitChildren(mark);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _theme.removeListener(_themeChanged);
    _manager?.removeListener(_databaseChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _effectiveTokens();
    if (!identical(SomiaColors.active, tokens)) {
      SomiaColors.active = tokens;
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildEverything());
    }
    final app = MaterialApp.router(
      key: ValueKey(_revision),
      title: 'Somia',
      debugShowCheckedModeBanner: false,
      darkTheme: AppTheme.dark,
      theme: AppTheme.light,
      themeMode: _theme.mode,
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
    final child =
        _auto == null ? app : SyncLifecycle(controller: _auto!, child: app);
    return _manager != null
        ? BackupLifecycle(manager: _manager!, child: child)
        : child;
  }
}
