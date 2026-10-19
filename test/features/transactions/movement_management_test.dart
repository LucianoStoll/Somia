import 'package:finapp/features/accounts/domain/accounts_repository.dart';
import 'package:finapp/features/categories/domain/categories_repository.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/transactions/domain/transactions_repository.dart';
import 'package:finapp/features/transactions/presentation/transactions_page.dart';
import 'package:finapp/core/filters/reference_month.dart';
import 'package:finapp/core/routing/somia_shell.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:finapp/features/transactions/data/transaction_settlements_repository.dart';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/series/movement_series.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/transactions/data/movement_management_repository.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transactions/domain/movement_management.dart';
import 'package:finapp/features/transactions/presentation/bulk_movement_toolbar.dart';
import 'package:finapp/features/transactions/presentation/trash_page.dart';
import 'package:finapp/features/transfers/data/sqlite_transfers_repository.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SqliteTransactionsRepository transactions;
  late MovementManagementRepository management;
  late String accountId;
  TransactionDraft draft(
          {String description = 'Compra',
          int amount = 1000,
          SeriesPlan? plan}) =>
      TransactionDraft(
          description: description,
          type: TransactionType.expense,
          amountMinor: amount,
          date: DateTime(2026, 10, 8),
          dueDate: DateTime(2026, 10, 10),
          isEffective: false,
          accountId: accountId,
          tags: ['Manter', 'Remover'],
          establishment: 'Mercado',
          seriesPlan: plan);
  Future<MovementReference> ref(String id) async =>
      MovementReference.transaction(
          (await transactions.list()).firstWhere((item) => item.id == id));
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    transactions = SqliteTransactionsRepository(db);
    management = MovementManagementRepository(db);
    accountId = (await SqliteAccountsRepository(db).create(const AccountDraft(
            name: 'Conta',
            type: AccountType.cash,
            currencyCode: 'BRL',
            initialBalanceMinor: 0,
            includeInAnalytics: true)))
        .id;
  });
  tearDown(() async {
    await getIt.reset();
    await db.close();
  });
  test('mês da movimentação usa efetivação ou vencimento do pendente',
      () async {
    final today = DateTime.now();
    final month = DateTime(today.year, today.month);
    final previous = DateTime(today.year, today.month, 0);
    await transactions.create(TransactionDraft(
        description: 'Recebido neste mês',
        type: TransactionType.income,
        amountMinor: 10000,
        date: previous,
        dueDate: previous,
        isEffective: true,
        effectiveDate: today,
        accountId: accountId));
    await transactions.create(TransactionDraft(
        description: 'A receber neste mês',
        type: TransactionType.income,
        amountMinor: 5000,
        date: month,
        dueDate: month,
        isEffective: false,
        accountId: accountId));
    final filter = TransactionFilter(
        type: TransactionType.income,
        dateField: TransactionDateField.activity,
        from: month,
        to: DateTime(today.year, today.month + 1, 0));
    expect((await transactions.list(filter)).map((item) => item.description),
        containsAll(['Recebido neste mês', 'A receber neste mês']));
    expect(
        (await transactions.list(TransactionFilter(
                type: TransactionType.income,
                dateField: TransactionDateField.due,
                from: month,
                to: DateTime(today.year, today.month + 1, 0))))
            .map((item) => item.description),
        isNot(contains('Recebido neste mês')));
  });
  test('lote preserva campos não escolhidos e combina tags sem duplicação',
      () async {
    final a = await transactions.create(draft());
    final b =
        await transactions.create(draft(description: 'Outra', amount: 2000));
    await management.apply(
        [await ref(a.id), await ref(b.id)],
        const BulkMovementPatch(
            establishment: 'Farmácia',
            addTags: ['manter', 'Nova'],
            removeTags: ['remover']));
    final items = await transactions.list();
    expect(items.map((item) => item.amountMinor).toSet(), {1000, 2000});
    expect(items.map((item) => item.description).toSet(), {'Compra', 'Outra'});
    for (final item in items) {
      expect(item.tags, ['Manter', 'Nova']);
      expect(item.establishment, 'Farmácia');
      expect(item.dueDate, DateTime.utc(2026, 10, 10));
    }
  });
  test(
      'campos históricos de valor efetivado e competência ficam intactos quando não escolhidos',
      () async {
    final item = await transactions.create(draft());
    final day = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
    await db.customStatement(
        'UPDATE transactions SET actual_amount_minor=800,effective_at=?,competence_at=? WHERE id=?',
        [day, day, item.id]);
    await management.apply([await ref(item.id)],
        const BulkMovementPatch(establishment: 'Nova loja'));
    final row = await db
        .customSelect(
            'SELECT actual_amount_minor,competence_at,posted_at FROM transactions')
        .getSingle();
    expect(row.read<int>('actual_amount_minor'), 800);
    expect(row.read<int>('competence_at'), day);
    expect(row.read<int>('posted_at'),
        DateTime.utc(2026, 10, 8).millisecondsSinceEpoch);
  });
  test('revisão antiga cancela todo o lote', () async {
    final a = await transactions.create(draft());
    final b = await transactions.create(draft());
    final refs = [await ref(a.id), await ref(b.id)];
    await transactions.update(b.id, draft(description: 'Mudou'));
    await expectLater(
        management.apply(refs, const BulkMovementPatch(description: 'Lote')),
        throwsStateError);
    expect((await transactions.list()).map((item) => item.description).toSet(),
        {'Compra', 'Mudou'});
  });
  test('erro no segundo movimento desfaz a alteração do primeiro', () async {
    final a = await transactions.create(draft());
    final other = (await SqliteAccountsRepository(db).create(const AccountDraft(
            name: 'USD',
            type: AccountType.cash,
            currencyCode: 'USD',
            initialBalanceMinor: 0,
            includeInAnalytics: true)))
        .id;
    final b = await transactions.create(TransactionDraft(
        description: 'Dólar',
        type: TransactionType.expense,
        amountMinor: 100,
        date: DateTime(2026, 10, 8),
        isEffective: false,
        accountId: other));
    await expectLater(
        management.apply([await ref(a.id), await ref(b.id)],
            BulkMovementPatch(description: 'Lote', accountId: accountId)),
        throwsStateError);
    expect((await transactions.list()).map((item) => item.description).toSet(),
        {'Compra', 'Dólar'});
  });
  test('edita apenas as ocorrências selecionadas da série', () async {
    final a = await transactions.create(
        draft(plan: const SeriesPlan(kind: SeriesKind.installments, count: 3)));
    await management.apply(
        [await ref(a.id)], const BulkMovementPatch(description: 'Selecionada'));
    expect(
        (await transactions.list())
            .where((item) => item.description == 'Selecionada')
            .length,
        1);
    expect((await transactions.list()).length, 3);
  });
  test(
      'baixas parciais sobrevivem à edição, exclusão e restauração sem duplicar saldo',
      () async {
    final item = await transactions.create(draft());
    final settlements = TransactionSettlementsRepository(db);
    final date = DateTime.now().subtract(const Duration(days: 1));
    await settlements.add(item.id,
        accountId: accountId, amountMinor: 1000, date: date);
    final paid = (await transactions.list()).single;
    expect(paid.isEffective, true);
    expect(paid.effectiveDate, isNull);
    await management.apply([await ref(item.id)],
        const BulkMovementPatch(description: 'Pago em baixas'));
    expect((await settlements.list(item.id)).single.amountMinor, 1000);
    expect((await transactions.list()).single.effectiveDate, isNull);
    await expectLater(
        management.apply(
            [await ref(item.id)], const BulkMovementPatch(effective: false)),
        throwsFormatException);
    expect((await settlements.list(item.id)).single.amountMinor, 1000);
    expect(
        (await SqliteAccountsRepository(db).list()).single.currentBalanceMinor,
        -1000);
    await management.trash([await ref(item.id)]);
    expect(
        (await SqliteAccountsRepository(db).list()).single.currentBalanceMinor,
        0);
    await management.restore([(await management.listTrash()).single.ref]);
    expect(
        (await SqliteAccountsRepository(db).list()).single.currentBalanceMinor,
        -1000);
    await expectLater(
        management.apply(
            [await ref(item.id)], const BulkMovementPatch(amountMinor: 999)),
        throwsFormatException);
    expect((await transactions.list()).single.amountMinor, 1000);
  });
  test('restauração rejeita conta excluída e aceita conta arquivada', () async {
    final item = await transactions.create(draft());
    await transactions.delete(item.id);
    final selected = (await management.listTrash()).single.ref;
    await db.customStatement(
        'UPDATE accounts SET deleted_at=1 WHERE id=?', [accountId]);
    await expectLater(management.restore([selected]), throwsStateError);
    expect((await management.listTrash()).length, 1);
    await db.customStatement(
        'UPDATE accounts SET deleted_at=NULL,is_archived=1 WHERE id=?',
        [accountId]);
    await management.restore([selected]);
    expect((await transactions.list()).length, 1);
  });
  test('exclusão comum vai à lixeira e restauração conserva metadados',
      () async {
    final a = await transactions.create(draft());
    await transactions.delete(a.id);
    expect(await transactions.list(), isEmpty);
    final trash = await management.listTrash();
    expect(trash.single.description, 'Compra');
    await management.restore([trash.single.ref]);
    final restored = (await transactions.list()).single;
    expect(restored.tags, ['Manter', 'Remover']);
    expect(restored.establishment, 'Mercado');
    expect(restored.amountMinor, 1000);
    expect(await management.listTrash(), isEmpty);
  });
  test('purga é definitiva e não expõe exclusões internas antigas', () async {
    final a = await transactions.create(draft());
    final old =
        await transactions.create(draft(description: 'Exclusão antiga'));
    await db.customStatement(
        'UPDATE transactions SET deleted_at=1 WHERE id=?', [old.id]);
    await management.trash([await ref(a.id)]);
    final deleted = (await management.listTrash()).single;
    await management.purge([deleted.ref]);
    expect(await management.listTrash(), isEmpty);
    await expectLater(management.restore([deleted.ref]), throwsStateError);
    expect(
        (await db
                .customSelect(
                    'SELECT trash_state FROM transactions WHERE id=\'${a.id}\'')
                .getSingle())
            .read<String>('trash_state'),
        'purged');
  });
  test('transferência volta com os mesmos dados após restaurar', () async {
    final destination = (await SqliteAccountsRepository(db).create(
            const AccountDraft(
                name: 'Reserva',
                type: AccountType.cash,
                currencyCode: 'BRL',
                initialBalanceMinor: 0,
                includeInAnalytics: true)))
        .id;
    final repo = SqliteTransfersRepository(db);
    final item = await repo.create(TransferDraft(
        description: 'Reserva',
        sourceAccountId: accountId,
        destinationAccountId: destination,
        amountMinor: 500,
        date: DateTime(2026, 10, 8),
        isEffective: true));
    await management.trash([MovementReference.transfer(item)]);
    expect(await repo.list(), isEmpty);
    await management.restore([(await management.listTrash()).single.ref]);
    expect((await repo.list()).single.isEffective, true);
    expect((await repo.list()).single.destinationAccountId, destination);
  });
  test('compra mantém fatura na edição em lote e pode ser restaurada',
      () async {
    final cards = CardsRepository(db);
    final card = await cards.save(CardDraft(
        name: 'Cartão',
        paymentAccountId: accountId,
        limitMinor: 100000,
        closingDay: 15,
        dueDay: 25));
    final id = await cards.createPurchase(TransactionDraft(
        description: 'Compra',
        type: TransactionType.expense,
        amountMinor: 1000,
        date: DateTime(2026, 10, 8),
        isEffective: false,
        accountId: card,
        cardId: card,
        cardInvoiceMonth: DateTime(2026, 12),
        tags: ['Viagem']));
    final before = await cards.entry(id);
    final selected =
        MovementReference.transaction(await cards.findMovement(id));
    await management.apply([selected],
        const BulkMovementPatch(establishment: 'Loja', addTags: ['Teste']));
    expect((await cards.entry(id)).invoiceId, before.invoiceId);
    await management
        .trash([MovementReference.transaction(await cards.findMovement(id))]);
    await management.restore([(await management.listTrash()).single.ref]);
    expect((await cards.entry(id)).tags, ['Viagem', 'Teste']);
    expect((await cards.entry(id)).invoiceId, before.invoiceId);
  });
  testWidgets(
      'seleção em lote aparece pelo menu e cancelar devolve lista sem checkbox',
      (tester) async {
    final item = await transactions.create(draft());
    referenceMonth.select(DateTime(2026, 10));
    getIt.registerSingleton<MovementManagementRepository>(management);
    getIt.registerSingleton<TransactionsRepository>(transactions);
    getIt.registerSingleton<AccountsRepository>(SqliteAccountsRepository(db));
    getIt.registerSingleton<CategoriesRepository>(
        SqliteCategoriesRepository(db));
    await tester.pumpWidget(const MaterialApp(
        home: TransactionsPage(sectionType: TransactionType.expense)));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('0 selecionado(s)'), findsNothing);
    await tester.tap(find.byKey(ValueKey('movement-menu-${item.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar em lote'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text('1 selecionado(s)'), findsOneWidget);
    await tester.tap(find.text('Cancelar seleção'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(await transactions.list(), hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('diálogo permite limpar estabelecimento sem mudar descrição',
      (tester) async {
    getIt.registerSingleton<MovementManagementRepository>(management);
    BulkMovementPatch? patch;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      patch = await showDialog<BulkMovementPatch>(
                          context: context,
                          builder: (_) => const BulkMovementDialog(count: 2));
                    },
                    child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.text('Estabelecimento (vazio para limpar)').first);
    await tester.tap(find.text('Estabelecimento (vazio para limpar)').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar alterações'));
    await tester.pumpAndSettle();
    expect(patch?.establishment, '');
    expect(patch?.description, isNull);
    expect(patch?.amountMinor, isNull);
  });
  testWidgets('lixeira restaura seleção após confirmação', (tester) async {
    final item = await transactions.create(draft());
    await transactions.delete(item.id);
    getIt.registerSingleton<MovementManagementRepository>(management);
    await tester.pumpWidget(const MaterialApp(home: TrashPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selecionar todos'));
    await tester.pump();
    await tester.tap(find.text('Restaurar (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurar'));
    await tester.pumpAndSettle();
    expect(find.text('A lixeira está vazia.'), findsOneWidget);
    expect((await transactions.list()).length, 1);
  });
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('prévia da tela de movimentos no celular', (tester) async {
      for (final pair in [
        ('Roboto', 'Roboto-Regular.ttf'),
        ('MaterialIcons', 'MaterialIcons-Regular.otf'),
      ]) {
        final loader = FontLoader(pair.$1)
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File(
                  '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/${pair.$2}',
                ).readAsBytesSync(),
              ),
            ),
          );
        await loader.load();
      }
      referenceMonth.select(DateTime(2026, 10));
      await transactions.create(
        draft(description: 'Mercado da semana', amount: 12345),
      );
      await transactions.create(
        draft(description: 'Financiamento do carro', amount: 999999999),
      );
      await transactions.create(
        TransactionDraft(
          description: 'Adiantamento',
          type: TransactionType.income,
          amountMinor: 60390,
          date: DateTime(2026, 10, 23),
          dueDate: DateTime(2026, 10, 23),
          isEffective: false,
          accountId: accountId,
        ),
      );
      await transactions.create(
        TransactionDraft(
          description: 'Lavagem dos carros',
          type: TransactionType.expense,
          amountMinor: 6000,
          date: DateTime(2026, 10, 8),
          dueDate: DateTime(2026, 10, 10),
          isEffective: true,
          effectiveDate: DateTime(2026, 10, 14),
          accountId: accountId,
        ),
      );
      await transactions.create(
        TransactionDraft(
          description: 'Salário',
          type: TransactionType.income,
          amountMinor: 420000,
          date: DateTime(2026, 10, 8),
          dueDate: DateTime(2026, 10, 10),
          isEffective: true,
          effectiveDate: DateTime(2026, 10, 17),
          accountId: accountId,
        ),
      );
      getIt.registerSingleton<TransactionsRepository>(transactions);
      getIt.registerSingleton<AccountsRepository>(SqliteAccountsRepository(db));
      getIt.registerSingleton<CategoriesRepository>(
        SqliteCategoriesRepository(db),
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.android),
          home: const RepaintBoundary(
            key: ValueKey('movements-preview'),
            child: SomiaShell(
              location: '/transactions',
              child: TransactionsPage(),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/branding/somia_horizontal.png'),
          tester.element(find.byType(TransactionsPage)),
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('R\$ 4.803,90'), findsOneWidget);
      expect(find.text('-R\$ 9.999.999,99'), findsOneWidget);
      expect(find.text('Pendentes'), findsOneWidget);
      expect(find.text('17 de outubro'), findsOneWidget);
      expect(find.text('23 de outubro'), findsNothing);
      await expectLater(
        find.byKey(const ValueKey('movements-preview')),
        matchesGoldenFile('movements-mobile-preview.png'),
      );
      for (final section in [
        (TransactionType.income, 'receitas'),
        (TransactionType.expense, 'despesas'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark.copyWith(platform: TargetPlatform.android),
            home: RepaintBoundary(
              key: ValueKey('${section.$2}-preview'),
              child: SomiaShell(
                location:
                    '/${section.$2 == 'receitas' ? 'income' : 'expenses'}',
                child: TransactionsPage(sectionType: section.$1),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Realizado'), findsOneWidget);
        expect(find.text('Previsto'), findsOneWidget);
        expect(find.text('Entradas'), findsNothing);
        expect(find.text('Pendentes'), findsOneWidget);
        expect(find.text('23 de outubro'), findsNothing);
        await expectLater(
          find.byKey(ValueKey('${section.$2}-preview')),
          matchesGoldenFile('${section.$2}-mobile-preview.png'),
        );
      }
    });
    testWidgets('prévias mobile e desktop de edição em lote e lixeira',
        (tester) async {
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
      getIt.registerSingleton<MovementManagementRepository>(management);
      final item =
          await transactions.create(draft(description: 'Mercado da semana'));
      await transactions.delete(item.id);
      for (final mobile in [true, false]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        tester.view.physicalSize =
            mobile ? const Size(390, 844) : const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final suffix = mobile ? 'mobile' : 'desktop';
        await tester.pumpWidget(const MaterialApp(home: TrashPage()));
        await tester.pumpAndSettle();
        await expectLater(find.byType(TrashPage),
            matchesGoldenFile('trash-$suffix-preview.png'));
        await tester.pumpWidget(MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showDialog<BulkMovementPatch>(
                            context: context,
                            builder: (_) => const BulkMovementDialog(count: 3)),
                        child: const Text('Abrir lote'))))));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Abrir lote'));
        await tester.pumpAndSettle();
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('bulk-$suffix-preview.png'));
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
      }
    });
  }
}
