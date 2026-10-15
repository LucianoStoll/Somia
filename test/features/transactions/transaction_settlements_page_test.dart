import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/accounts/domain/accounts_repository.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/data/transaction_settlements_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transactions/presentation/transaction_settlements_page.dart';

void main() {
  late AppDatabase db;
  late FinancialTransaction item;
  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    final accounts = SqliteAccountsRepository(db);
    final a = await accounts.create(const AccountDraft(
        name: 'Minha conta',
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 100000,
        includeInAnalytics: true));
    item = await SqliteTransactionsRepository(db).create(TransactionDraft(
        description: 'Compra de móveis',
        type: TransactionType.expense,
        amountMinor: 100000,
        date: DateTime.now(),
        isEffective: false,
        accountId: a.id));
    getIt.registerSingleton<AppDatabase>(db);
    getIt.registerSingleton<AccountsRepository>(accounts);
  });
  tearDown(() async {
    await getIt.reset();
    await db.close();
  });
  Future<void> open(WidgetTester tester, TargetPlatform platform) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    tester.view.physicalSize = platform == TargetPlatform.android
        ? const Size(390, 844)
        : const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark.copyWith(platform: platform),
        home: TransactionSettlementsPage(item: item)));
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('registrar e desfazer baixa em $platform', (tester) async {
      await open(tester, platform);
      await tester.enterText(find.byType(TextField).first, '250,00');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Registrar pagamento'));
      await tester.tap(find.text('Registrar pagamento'));
      await tester.pumpAndSettle();
      expect(find.text('Restante para baixar: R\$ 750,00'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Desfazer baixa'));
      await tester.tap(find.byTooltip('Desfazer baixa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      expect(await TransactionSettlementsRepository(db).list(item.id), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('prévias de baixas e histórico', (tester) async {
      for (final pair in [
        ('Roboto', 'Roboto-Regular.ttf'),
        ('MaterialIcons', 'MaterialIcons-Regular.otf')
      ]) {
        final loader = FontLoader(pair.$1)
          ..addFont(Future.value(ByteData.sublistView(File(
                  '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/${pair.$2}')
              .readAsBytesSync())));
        await loader.load();
      }
      await TransactionSettlementsRepository(db).add(item.id,
          accountId: item.accountId,
          amountMinor: 25000,
          date: DateTime(2026, 10, 8));
      for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
        await open(tester, platform);
        final suffix =
            platform == TargetPlatform.android ? 'mobile' : 'desktop';
        await expectLater(find.byType(TransactionSettlementsPage),
            matchesGoldenFile('settlements-$suffix-preview.png'));
      }
    });
  }
}
