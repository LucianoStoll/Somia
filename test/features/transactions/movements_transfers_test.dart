import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/filters/reference_month.dart';
import 'package:finapp/core/routing/somia_shell.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/accounts/domain/accounts_repository.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/categories/domain/categories_repository.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transactions/domain/transactions_repository.dart';
import 'package:finapp/features/transactions/domain/transfer_movement_filter.dart';
import 'package:finapp/features/transactions/presentation/transactions_cubit.dart';
import 'package:finapp/features/transactions/presentation/transactions_page.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:finapp/features/transfers/domain/transfers_repository.dart';

void main() {
  late AppDatabase db;
  late SqliteTransfersRepository transfers;
  late SqliteAccountsRepository accounts;
  late SqliteTransactionsRepository transactions;
  late SqliteCategoriesRepository categories;
  late Account source, destination;
  late Transfer moved;
  final month = DateTime(2020, 1);
  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    accounts = SqliteAccountsRepository(db);
    transfers = SqliteTransfersRepository(db);
    transactions = SqliteTransactionsRepository(db);
    categories = SqliteCategoriesRepository(db);
    source = await accounts.create(const AccountDraft(
        name: 'Conta A',
        type: AccountType.checking,
        currencyCode: 'BRL',
        initialBalanceMinor: 0,
        includeInAnalytics: true));
    destination = await accounts.create(const AccountDraft(
        name: 'Conta B',
        type: AccountType.savings,
        currencyCode: 'BRL',
        initialBalanceMinor: 0,
        includeInAnalytics: true));
    moved = await transfers.create(TransferDraft(
        description: 'Entre contas',
        sourceAccountId: source.id,
        destinationAccountId: destination.id,
        amountMinor: 10000,
        date: DateTime(2020, 1, 15),
        effectiveDate: DateTime(2020, 1, 15),
        isEffective: true));
    for (final type in TransactionType.values) {
      await transactions.create(TransactionDraft(
          description: type.label,
          type: type,
          amountMinor: type == TransactionType.income ? 20000 : 5000,
          date: DateTime(2020, 1, 15),
          effectiveDate: DateTime(2020, 1, 15),
          isEffective: true,
          accountId: source.id));
    }
    getIt.registerSingleton<TransactionsRepository>(transactions);
    getIt.registerSingleton<AccountsRepository>(accounts);
    getIt.registerSingleton<CategoriesRepository>(categories);
    getIt.registerSingleton<TransfersRepository>(transfers);
    referenceMonth.select(month);
  });
  tearDown(() async {
    await getIt.reset();
    await db.close();
  });

  test(
      'feed filtra conta de origem/destino e período sem alterar receitas/despesas',
      () async {
    final cubit = TransactionsCubit(transactions, accounts, categories,
        transfers: transfers, month: month);
    addTearDown(cubit.close);
    await cubit.load();
    expect(cubit.state.error, isNull);
    expect(cubit.state.transfers.map((t) => t.id), [moved.id]);
    expect(cubit.state.items.length, 2);
    await cubit.load(TransactionFilter(
        accountId: destination.id, from: month, to: DateTime(2020, 1, 31)));
    expect(cubit.state.transfers.single.id, moved.id);
    expect(cubit.state.items, isEmpty);
    await cubit.load(const TransactionFilter(type: TransactionType.income));
    expect(cubit.state.transfers, isEmpty);
    await cubit.load(
        TransactionFilter(from: DateTime(2020, 2), to: DateTime(2020, 2, 29)));
    expect(cubit.state.transfers, isEmpty);
    final section = TransactionsCubit(transactions, accounts, categories,
        transfers: transfers,
        month: month,
        sectionType: TransactionType.expense);
    addTearDown(section.close);
    await section.load();
    expect(section.state.transfers, isEmpty);
  });

  test('filtros de status, categoria, tags e datas não misturam transferências',
      () {
    final pending = Transfer(
        id: 'p',
        sourceAccountId: source.id,
        sourceAccountName: source.name,
        destinationAccountId: destination.id,
        destinationAccountName: destination.name,
        currencyCode: 'BRL',
        amountMinor: 3000,
        date: DateTime(2019, 12, 20),
        dueDate: DateTime(2020, 1, 31, 23, 59),
        effectiveDate: DateTime(2030, 2),
        isEffective: false);
    bool matches(TransactionFilter f) => matchesTransferMovement(pending, f);
    expect(
        matches(TransactionFilter(
            from: month,
            to: DateTime(2020, 1, 31),
            dateField: TransactionDateField.activity)),
        isTrue);
    expect(matches(const TransactionFilter(status: TransactionStatus.pending)),
        isTrue);
    expect(
        matches(const TransactionFilter(status: TransactionStatus.effective)),
        isFalse);
    for (final f in [
      const TransactionFilter(categoryId: 'x'),
      const TransactionFilter(tag: 'x'),
      const TransactionFilter(establishment: 'x'),
      const TransactionFilter(type: TransactionType.expense)
    ]) {
      expect(matches(f), isFalse);
    }
    expect(
        matches(TransactionFilter(
            from: DateTime(2030, 2),
            dateField: TransactionDateField.effective)),
        isTrue);
  });

  testWidgets(
      'mobile mostra transferência única com origem/destino e totais separados',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.android),
        home: const SomiaShell(
            location: '/transactions', child: TransactionsPage())));
    await tester.pumpAndSettle();
    final row = find.byKey(ValueKey('feed-transfer-${moved.id}'));
    await tester.scrollUntilVisible(row, 160);
    expect(row, findsOneWidget);
    expect(find.text('Conta A → Conta B'), findsOneWidget);
    expect(find.text('R\$ 200,00'), findsOneWidget);
    expect(find.text('R\$ 50,00'), findsOneWidget);
    referenceMonth.select(DateTime(2020, 2));
    await tester.pumpAndSettle();
    expect(row, findsNothing);
    expect(find.text('Nenhum lançamento para estes filtros.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
