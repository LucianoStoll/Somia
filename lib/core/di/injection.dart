import 'dart:io';
import '../drive/drive_backup.dart';
import '../drive/drive_backup_manager.dart';
import '../../features/accounts/data/account_statement_repository.dart';
import '../../features/transactions/data/category_history_repository.dart';
import '../../features/cards/data/cards_repository.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_environment.dart';
import '../database/app_database.dart';
import '../database/backup_manager.dart';
import '../database/local_backup_store.dart';
import '../../features/accounts/data/sqlite_accounts_repository.dart';
import '../../features/accounts/domain/accounts_repository.dart';
import '../../features/categories/data/sqlite_categories_repository.dart';
import '../../features/categories/domain/categories_repository.dart';
import '../../features/transactions/data/sqlite_transactions_repository.dart';
import '../../features/transactions/domain/transactions_repository.dart';
import '../../features/transfers/data/sqlite_transfers_repository.dart';
import '../../features/transfers/domain/transfers_repository.dart';
import '../../features/balances/data/sqlite_balances_repository.dart';
import '../../features/balances/domain/balances_repository.dart';
import '../../features/dashboard/data/sqlite_dashboard_repository.dart';
import '../../features/dashboard/domain/dashboard_repository.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies(AppEnvironment environment) async {
  if (getIt.isRegistered<AppEnvironment>()) {
    await getIt.reset();
  }

  getIt.registerSingleton<AppEnvironment>(environment);
  final database = AppDatabase.open();
  try {
    // Força a abertura e a criação/migration antes de exibir a interface.
    await database.customSelect('PRAGMA user_version').getSingle();
  } catch (_) {
    await database.close();
    rethrow;
  }
  getIt.registerSingleton<AppDatabase>(database, dispose: (db) => db.close());
  getIt.registerSingleton<BackupManager>(
      BackupManager(
          database, LocalBackupStore(await getApplicationSupportDirectory())),
      dispose: (manager) => manager.dispose());
  if (Platform.isAndroid) {
    getIt.registerSingleton<DriveBackupManager>(
        DriveBackupManager(getIt<BackupManager>(),
            DriveBackupApi(AndroidDriveAuth(), IoDriveTransport())),
        dispose: (manager) => manager.dispose());
  }
  getIt.registerLazySingleton<AccountStatementRepository>(
      () => AccountStatementRepository(getIt<AppDatabase>()));
  getIt.registerLazySingleton<AccountsRepository>(
    () => SqliteAccountsRepository(getIt<AppDatabase>()),
  );

  getIt.registerLazySingleton<CategoriesRepository>(
    () => SqliteCategoriesRepository(getIt<AppDatabase>()),
  );

  getIt.registerLazySingleton<CategoryHistoryRepository>(
    () => CategoryHistoryRepository(getIt<AppDatabase>()),
  );

  getIt.registerLazySingleton<TransactionsRepository>(
    () => SqliteTransactionsRepository(getIt<AppDatabase>()),
  );

  getIt.registerLazySingleton<TransfersRepository>(
    () => SqliteTransfersRepository(getIt<AppDatabase>()),
  );

  getIt.registerLazySingleton<BalancesRepository>(
    () => SqliteBalancesRepository(getIt<AppDatabase>()),
  );

  getIt.registerLazySingleton<DashboardRepository>(
    () => SqliteDashboardRepository(getIt<AppDatabase>()),
  );

  getIt.registerLazySingleton<CardsRepository>(
      () => CardsRepository(getIt<AppDatabase>()));

  // As dependências de cada feature serão registradas aqui por módulo.
}
