import 'dart:io';
import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/widgets/monetary_calculator.dart';
import 'package:finapp/features/assets/domain/asset.dart';
import 'package:finapp/features/assets/data/sqlite_assets_repository.dart';
import 'package:finapp/features/debts/domain/debt.dart';
import 'package:finapp/features/debts/data/sqlite_debts_repository.dart';
import 'package:finapp/features/debts/presentation/debts_page.dart';
import 'package:finapp/features/debts/presentation/debt_forms.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) return;
    for (final font in [
      ('Roboto', 'Roboto-Regular.ttf'),
      ('MaterialIcons', 'MaterialIcons-Regular.otf')
    ]) {
      final loader = FontLoader(font.$1)
        ..addFont(Future.value(ByteData.sublistView(File(
                '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/${font.$2}')
            .readAsBytesSync())));
      await loader.load();
    }
  });
  late AppDatabase db;
  late SqliteDebtsRepository repo;
  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    repo = SqliteDebtsRepository(db);
    getIt.registerSingleton<DebtsRepository>(repo);
    getIt.registerSingleton<AssetsRepository>(SqliteAssetsRepository(db));
  });
  tearDown(() async {
    await getIt.reset();
    await db.close();
  });
  for (final size in [const Size(390, 1000), const Size(320, 844)]) {
    testWidgets(
        'novo layout filtra dívidas e mantém amortização e histórico $size',
        (tester) async {
      final id = await repo.save(DebtDraft(
          name: 'Financiamento do carro',
          creditor: 'Banco',
          kind: DebtKind.financing,
          balanceMinor: 2000000,
          referenceAt: DateTime(2025, 1, 1),
          notes: 'Contrato do carro'));
      final account = await SqliteAccountsRepository(db).create(
          const AccountDraft(
              name: 'Conta',
              type: AccountType.checking,
              currencyCode: 'BRL',
              initialBalanceMinor: 3000000,
              includeInAnalytics: true));
      final transactions = SqliteTransactionsRepository(db);
      for (final paid in [true, false]) {
        final tx = await transactions.create(TransactionDraft(
            description: paid ? 'Parcela efetivada' : 'Parcela pendente',
            type: TransactionType.expense,
            amountMinor: 55000,
            date: DateTime(2025, 2, 10),
            dueDate: DateTime(2025, 2, 10),
            effectiveDate: paid ? DateTime(2025, 2, 10) : null,
            isEffective: paid,
            accountId: account.id));
        await repo.link(id, tx.id, 50000);
      }
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark, home: const DebtsPage()));
      await tester.pumpAndSettle();
      expect(find.text('Saldo devedor'), findsOneWidget);
      await tester.tap(find.text('Quitadas  0'));
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma dívida quitada.'), findsOneWidget);
      await tester.tap(find.text('Ativas  1'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.byKey(ValueKey('debt-open-$id')), 150,
          scrollable: find
              .byWidgetPredicate((w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.down)
              .first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('debt-open-$id')));
      await tester.pumpAndSettle();
      expect(find.text('Detalhes da dívida'), findsOneWidget);
      expect(find.text('Vincular despesa'), findsOneWidget);
      final payment = (await repo.load()).single.payments.first;
      await tester.scrollUntilVisible(
          find.byKey(ValueKey('debt-payment-${payment.id}')), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('debt-payment-${payment.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Juros e encargos'), findsOneWidget);
      await tester.tap(find.text('Desvincular parcela'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect((await repo.load()).single.balanceMinor, 1950000);
      expect((await repo.load()).single.projectedMinor, 1900000);

      // Editar a amortização de uma parcela já vinculada.
      await tester.tap(find.byKey(ValueKey('debt-payment-${payment.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('debt-edit-principal')));
      await tester.pumpAndSettle();
      expect(find.text('Editar amortização'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('debt-principal-edit')));
      await tester.pumpAndSettle();
      for (final key in ['C', '4', '0', '0', ',', '0', '0']) {
        await tester.tap(find.byKey(ValueKey('calculator-key-$key')));
      }
      await tester.tap(find.text('Confirmar valor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar amortização'));
      await tester.pumpAndSettle();
      final edited = (await repo.load()).single;
      expect(
          edited.payments.firstWhere((p) => p.id == payment.id).principalMinor,
          40000);
      expect(edited.projectedMinor, 1910000);
      await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Dados'), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dados'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Contrato do carro'), 150);
      await tester.pumpAndSettle();
      expect(find.text('Contrato do carro'), findsOneWidget);
      if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW') &&
          size.width == 390) {
        await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Parcelas vinculadas'), 150);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Parcelas vinculadas'));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
        await tester.pumpAndSettle();
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('debt-detail-mobile-preview.png'));
      }
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Dívidas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('cadastro valida credor e preserva campos $platform',
        (tester) async {
      tester.view.physicalSize = platform == TargetPlatform.android
          ? const Size(390, 844)
          : const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark.copyWith(platform: platform),
          home: const DebtsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Nova dívida'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Nome da dívida'),
          'Empréstimo família');
      tester
          .widget<MonetaryCalculatorField>(find.byType(MonetaryCalculatorField))
          .controller
          .text = '1000,00';
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.text('Informe o credor.'), findsOneWidget);
      expect(await repo.load(), isEmpty);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Credor / banco'), 'Família');
      await tester.pumpAndSettle();
      if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(platform == TargetPlatform.android
                ? 'debt-form-mobile-preview.png'
                : 'debt-form-desktop-preview.png'));
      }
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect((await repo.load()).single.balanceMinor, 100000);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(platform == TargetPlatform.android
                ? 'debts-mobile-preview.png'
                : 'debts-desktop-preview.png'));
      }
    });
    testWidgets('vincula várias despesas com o mesmo valor $platform',
        (tester) async {
      await repo.save(DebtDraft(
          name: 'Financiamento',
          creditor: 'Banco',
          kind: DebtKind.financing,
          balanceMinor: 100000,
          referenceAt: DateTime(2025, 1, 1)));
      final account = await SqliteAccountsRepository(db).create(
          const AccountDraft(
              name: 'Conta',
              type: AccountType.checking,
              currencyCode: 'BRL',
              initialBalanceMinor: 300000,
              includeInAnalytics: true));
      final transactions = SqliteTransactionsRepository(db);
      for (final month in [2, 3, 4]) {
        await transactions.create(TransactionDraft(
            description: 'Parcela $month',
            type: TransactionType.expense,
            amountMinor: 52000,
            date: DateTime(2025, month, 10),
            dueDate: DateTime(2025, month, 10),
            isEffective: false,
            accountId: account.id));
      }
      final debt = (await repo.load()).single;
      final expenses = await repo.expenses(debt.id);
      tester.view.physicalSize = platform == TargetPlatform.android
          ? const Size(390, 844)
          : const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          home: Scaffold(
              body: Builder(
                  builder: (c) => TextButton(
                      onPressed: () => showDialog<void>(
                          context: c,
                          builder: (_) => DebtPaymentForm(
                              repository: repo,
                              debt: debt,
                              expenses: expenses)),
                      child: const Text('Abrir'))))));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      final chosen = expenses.take(2).toList();
      for (final e in chosen) {
        await tester.tap(find.text(e.description));
        await tester.pumpAndSettle();
      }
      expect(find.text('2 selecionadas, amortização total'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('debt-link-same-value')));
      await tester.pumpAndSettle();
      for (final key in ['C', '3', '0', '0', ',', '0', '0']) {
        await tester.tap(find.byKey(ValueKey('calculator-key-$key')));
      }
      await tester.tap(find.text('Confirmar valor'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('debt-link-total')))
              .data,
          contains('600,00'));
      await tester.tap(find.text('Vincular 2 despesas'));
      await tester.pumpAndSettle();
      final linked = (await repo.load()).single;
      expect(linked.payments.map((p) => p.transactionId).toSet(),
          chosen.map((e) => e.id).toSet());
      expect(linked.payments.every((p) => p.principalMinor == 30000), isTrue);
      expect(linked.projectedMinor, 40000);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        'vincular exige despesa e mostra orientação quando vazio $platform',
        (tester) async {
      final id = await repo.save(DebtDraft(
          name: 'Dívida',
          creditor: 'Credor',
          kind: DebtKind.loan,
          balanceMinor: 100000,
          referenceAt: DateTime(2025, 1, 1)));
      final debt = (await repo.load()).single;
      tester.view.physicalSize = platform == TargetPlatform.android
          ? const Size(390, 844)
          : const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark.copyWith(platform: platform),
          home: Scaffold(
              body: Builder(
                  builder: (c) => TextButton(
                      onPressed: () => showDialog<void>(
                          context: c,
                          builder: (_) => DebtPaymentForm(
                              repository: repo,
                              debt: debt,
                              expenses: const [])),
                      child: const Text('Abrir'))))));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Selecione as despesas'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Selecione as despesas'))
              .onPressed,
          isNull);
      expect(
          find.text(
              'Nenhuma despesa disponível a partir da referência do saldo.'),
          findsOneWidget);
      expect((await repo.load()).single.id, id);
      expect((await repo.load()).single.payments, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
