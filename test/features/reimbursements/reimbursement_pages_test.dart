import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/widgets/movement_form_frame.dart';
import 'package:finapp/core/widgets/monetary_calculator.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/categories/domain/categories_repository.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transactions/presentation/transactions_page.dart';
import 'package:finapp/features/reimbursements/data/reimbursements_repository.dart';
import 'package:finapp/features/reimbursements/domain/reimbursement.dart';
import 'package:finapp/features/reimbursements/presentation/reimbursements_page.dart';

void main() {
  late AppDatabase db;
  late ReimbursementsRepository repo;
  late List<Account> accounts;
  late String person;
  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    repo = ReimbursementsRepository(db);
    final accountRepo = SqliteAccountsRepository(db);
    await accountRepo.create(const AccountDraft(
        name: 'Conta principal',
        type: AccountType.cash,
        currencyCode: 'BRL',
        initialBalanceMinor: 20000,
        includeInAnalytics: true));
    accounts = await accountRepo.list();
    person = await repo.savePerson('Mãe');
    getIt.registerSingleton<ReimbursementsRepository>(repo);
    getIt.registerSingleton<AccountsRepository>(accountRepo);
    getIt.registerSingleton<CategoriesRepository>(
        SqliteCategoriesRepository(db));
  });
  tearDown(() async {
    await getIt.reset();
    await db.close();
  });
  Future<void> open(
      WidgetTester tester, Widget child, TargetPlatform platform) async {
    tester.view.physicalSize = platform == TargetPlatform.android
        ? const Size(390, 844)
        : const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark.copyWith(platform: platform),
        home: child));
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('reembolso fica em Mais opções e salva pessoa/valor $platform',
        (tester) async {
      TransactionDraft? result;
      await open(
          tester,
          Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () async {
                        result = await showMovementForm<TransactionDraft>(
                            context,
                            (_) => TransactionForm(
                                accounts: accounts,
                                categories: const [],
                                fixedType: TransactionType.expense));
                      },
                      child: const Text('Abrir')))),
          platform);
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextFormField).first, 'Jantar compartilhado');
      tester
          .widget<MonetaryCalculatorField>(
              find.byType(MonetaryCalculatorField).first)
          .controller
          .text = '100,00';
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.text('Reembolso'), findsNothing);
      await tester.ensureVisible(find.text('Mais opções'));
      await tester.tap(find.text('Mais opções'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reembolso'));
      await tester.tap(find.text('Reembolso'));
      await tester.pumpAndSettle();
      final field = find
          .ancestor(
              of: find.text('Pessoa'),
              matching: find.byType(DropdownButtonFormField<String>))
          .first;
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mãe').last);
      await tester.pumpAndSettle();
      tester
          .widget<MonetaryCalculatorField>(
              find.byType(MonetaryCalculatorField).last)
          .controller
          .text = '40,00';
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Mais opções'));
      await tester.tap(find.text('Mais opções'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar lançamento'));
      await tester.pumpAndSettle();
      expect(result!.reimbursements!.single.personId, person);
      expect(result!.reimbursements!.single.amountMinor, 4000);
      expect(result!.amountMinor, 10000);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        'histórico permite receber parcialmente sem compensar despesa $platform',
        (tester) async {
      await SqliteTransactionsRepository(db).create(TransactionDraft(
          description: 'Mercado',
          type: TransactionType.expense,
          amountMinor: 10000,
          date: DateTime.now(),
          isEffective: true,
          accountId: accounts.single.id,
          reimbursements: [ReimbursementDraft(person, 4000)]));
      await open(tester, const ReimbursementsPage(), platform);
      await tester.tap(find.text('Mãe · Mercado'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Registrar recebimento'));
      await tester.tap(find.text('Registrar recebimento'));
      await tester.pumpAndSettle();
      tester
          .widget<MonetaryCalculatorField>(find.byType(MonetaryCalculatorField))
          .controller
          .text = '15,00';
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar recebimento'));
      await tester.pumpAndSettle();
      expect((await repo.load()).single.pending, 2500);
      expect((await repo.load()).single.received, 1500);
      expect(find.text('A receber: BRL 25,00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('prévias do histórico de reembolsos', (tester) async {
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
      await SqliteTransactionsRepository(db).create(TransactionDraft(
          description: 'Jantar compartilhado',
          type: TransactionType.expense,
          amountMinor: 10000,
          date: DateTime.now(),
          isEffective: true,
          accountId: accounts.single.id,
          reimbursements: [ReimbursementDraft(person, 4000)]));
      await repo.receive((await repo.load()).single,
          amount: 1500, accountId: accounts.single.id, date: DateTime.now());
      for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
        await open(tester, const ReimbursementsPage(), platform);
        await tester.tap(find.text('Mãe · Jantar compartilhado'));
        await tester.pumpAndSettle();
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
                'reimbursements-${platform == TargetPlatform.android ? 'mobile' : 'desktop'}-preview.png'));
        expect(tester.takeException(), isNull);
      }
    });
  }
}
