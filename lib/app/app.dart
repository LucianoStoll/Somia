import 'package:flutter/material.dart';
import '../core/database/backup_manager.dart';
import '../core/database/backup_lifecycle.dart';
import '../core/di/injection.dart';

import '../core/routing/app_router.dart';
import '../core/theme/app_theme.dart';

class FinApp extends StatelessWidget {
  const FinApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp.router(
      title: 'Somia',
      debugShowCheckedModeBanner: false,
      darkTheme: AppTheme.dark,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
    );
    return getIt.isRegistered<BackupManager>()
        ? BackupLifecycle(manager: getIt<BackupManager>(), child: app)
        : app;
  }
}
