import 'package:finapp/features/accounts/data/account_statement_repository.dart';
import 'account_statement_page_test.dart' as statements;
import 'package:finapp/core/series/movement_series.dart';
import 'package:finapp/app/app.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/filters/reference_month.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:finapp/features/transfers/domain/transfers_repository.dart';
import 'package:finapp/core/routing/app_router.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/accounts/domain/accounts_repository.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/categories/domain/categories_repository.dart';
import 'package:finapp/features/dashboard/domain/dashboard_repository.dart';
import 'package:finapp/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transactions/domain/transactions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _DashboardStub implements DashboardRepository {
  @override
  Future<DashboardSummary> load(DateTime month) async =>
      DashboardSummary(month: month, currencies: const [], recent: const []);
}

class _AccountsStub implements AccountsRepository {
  List<Account> items = [];
  @override
  Future<List<Account>> list({DateTime? asOf, DateTime? through}) async =>
      items;
  @override
  Future<Account> create(AccountDraft draft) => throw UnimplementedError();
  @override
  Future<Account> update(String id, AccountDraft draft) =>
      throw UnimplementedError();
  @override
  Future<Account> setArchived(String id, {required bool archived}) =>
      throw UnimplementedError();
}

class _CategoriesStub implements CategoriesRepository {
  @override
  Future<List<FinanceCategory>> list() async => [];
  @override
  Future<FinanceCategory> create(CategoryDraft draft) =>
      throw UnimplementedError();
  @override
  Future<FinanceCategory> update(String id, CategoryDraft draft) =>
      throw UnimplementedError();
  @override
  Future<FinanceCategory> setArchived(String id, {required bool archived}) =>
      throw UnimplementedError();
}

class _TransactionsStub implements TransactionsRepository {
  final requestedTypes = <TransactionType?>[];
  final requestedFilters = <TransactionFilter>[];
  final items = [
    FinancialTransaction(
        id: 'income',
        description: 'Salário',
        type: TransactionType.income,
        amountMinor: 500000,
        date: DateTime(2026, 9, 29),
        isEffective: true,
        accountId: 'a',
        accountName: 'Conta',
        categoryId: null,
        categoryName: null,
        currencyCode: 'BRL'),
    FinancialTransaction(
        id: 'expense',
        description: 'Mercado',
        type: TransactionType.expense,
        amountMinor: 18000,
        date: DateTime(2026, 9, 29),
        isEffective: false,
        accountId: 'a',
        accountName: 'Conta',
        categoryId: null,
        categoryName: null,
        currencyCode: 'BRL'),
  ];
  @override
  Future<List<FinancialTransaction>> list(
      [TransactionFilter filter = const TransactionFilter()]) async {
    requestedTypes.add(filter.type);
    requestedFilters.add(filter);
    return items
        .where((item) =>
            (filter.type == null || item.type == filter.type) &&
            (filter.from == null || !item.date.isBefore(filter.from!)) &&
            (filter.to == null || !item.date.isAfter(filter.to!)))
        .toList();
  }

  @override
  Future<FinancialTransaction> create(TransactionDraft draft) =>
      throw UnimplementedError();
  @override
  Future<FinancialTransaction> update(String id, TransactionDraft draft) =>
      throw UnimplementedError();
  @override
  Future<void> setEffective(String id,
          {required bool effective, DateTime? effectiveDate}) =>
      throw UnimplementedError();
  @override
  Future<void> changeEffectiveDate(String id,
      {required DateTime expectedDate, DateTime? effectiveDate}) async {}
  @override
  Future<void> updateAmount(String id,
      {required int expectedAmountMinor,
      required int amountMinor,
      SeriesScope scope = SeriesScope.onlyThis}) async {}

  @override
  Future<void> delete(String id, {SeriesScope scope = SeriesScope.onlyThis}) =>
      throw UnimplementedError();
}

class _TransfersStub implements TransfersRepository {
  @override
  Future<List<Transfer>> list({String? accountId}) async => [
        Transfer(
            id: 'dec',
            sourceAccountId: 'a',
            sourceAccountName: 'Banco',
            destinationAccountId: 'b',
            destinationAccountName: 'Carteira',
            currencyCode: 'BRL',
            amountMinor: 10000,
            date: DateTime(2026, 9, 1),
            dueDate: DateTime(2026, 12, 31),
            isEffective: false),
        Transfer(
            id: 'sep',
            sourceAccountId: 'a',
            sourceAccountName: 'Setembro',
            destinationAccountId: 'b',
            destinationAccountName: 'Reserva',
            currencyCode: 'BRL',
            amountMinor: 10000,
            date: DateTime(2026, 9, 1),
            isEffective: false),
      ];
  @override
  Future<Transfer> create(TransferDraft draft) => throw UnimplementedError();
  @override
  Future<Transfer> update(String id, TransferDraft draft) =>
      throw UnimplementedError();
  @override
  Future<void> setEffective(String id,
          {required bool effective, DateTime? effectiveDate}) =>
      throw UnimplementedError();
  @override
  Future<void> changeEffectiveDate(String id,
      {required DateTime expectedDate, DateTime? effectiveDate}) async {}
  @override
  Future<void> updateAmount(String id,
      {required int expectedAmountMinor,
      required int amountMinor,
      SeriesScope scope = SeriesScope.onlyThis}) async {}

  @override
  Future<void> delete(String id, {SeriesScope scope = SeriesScope.onlyThis}) =>
      throw UnimplementedError();
}

void main() {
  setUp(() => referenceMonth.select(DateTime(2026, 9)));
  tearDown(() => referenceMonth.select(DateTime.now()));

  Future<void> openBackTest(WidgetTester tester,
      {TargetPlatform platform = TargetPlatform.android,
      Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    getIt.registerSingleton<DashboardRepository>(_DashboardStub());
    getIt.registerSingleton<TransactionsRepository>(_TransactionsStub());
    getIt.registerSingleton<TransfersRepository>(_TransfersStub());
    getIt.registerSingleton<AccountsRepository>(_AccountsStub());
    getIt.registerSingleton<CategoriesRepository>(_CategoriesStub());
    addTearDown(() async {
      appRouter.go('/');
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await getIt.reset();
    });
    appRouter.go('/');
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: appRouter,
        theme: AppTheme.dark.copyWith(platform: platform)));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(390, 844), const Size(915, 412)]) {
    testWidgets(
        'Android $size: Voltar retorna ao Resumo em todas as seções e só então permite sair',
        (tester) async {
      await openBackTest(tester, size: size);
      for (final path in [
        '/income',
        '/expenses',
        '/transfers',
        '/accounts',
        '/categories',
        '/settings',
        '/transactions'
      ]) {
        appRouter.go(path);
        await tester.pumpAndSettle();
        expect(await appRouter.routerDelegate.popRoute(), true);
        await tester.pumpAndSettle();
        expect(appRouter.routeInformationProvider.value.uri.path, '/');
        // false devolve ao Android a saída padrão, sem remover a rota Resumo.
        expect(await appRouter.routerDelegate.popRoute(), false);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'conta abre extrato e Voltar Android retorna à lista antes do Resumo',
      (tester) async {
    await openBackTest(tester);
    (getIt<AccountsRepository>() as _AccountsStub).items = [statements.account];
    getIt.registerSingleton<AccountStatementRepository>(
        statements.FakeStatementRepository());
    appRouter.go('/accounts');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mercado Pago'));
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/accounts/a');
    expect(find.text('Detalhes da conta'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/accounts');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Android: drawer, balão + e filtros fecham antes de sair da seção',
      (tester) async {
    await openBackTest(tester);
    for (final path in ['/', '/expenses']) {
      appRouter.go(path);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Abrir menu'));
      await tester.pumpAndSettle();
      expect(await appRouter.routerDelegate.popRoute(), true);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Fechar menu'), findsNothing);
      expect(appRouter.routeInformationProvider.value.uri.path, path);
    }
    await tester.tap(find.byTooltip('Adicionar lançamento ou transferência'));
    await tester.pumpAndSettle();
    expect(await appRouter.routerDelegate.popRoute(), true);
    await tester.pumpAndSettle();
    expect(find.text('Receita'), findsNothing);
    expect(appRouter.routeInformationProvider.value.uri.path, '/expenses');
    await tester.tap(find.text('Filtros'));
    await tester.pumpAndSettle();
    expect(await appRouter.routerDelegate.popRoute(), true);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Fechar filtros'), findsNothing);
    expect(appRouter.routeInformationProvider.value.uri.path, '/expenses');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Android: navegador principal mantém tratamento nativo do Voltar ao alternar seções',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final signals = <bool>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
        signals.add(call.arguments as bool);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await openBackTest(tester);
    for (final path in [
      '/income',
      '/transfers',
      '/expenses',
      '/transfers',
      '/accounts',
      '/transfers'
    ]) {
      appRouter.go(path);
      await tester.pumpAndSettle();
      expect(signals, isNotEmpty);
      expect(signals.last, true,
          reason: 'O Android deve entregar Voltar ao Flutter em $path');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(appRouter.routeInformationProvider.value.uri.path, '/');
      expect(signals.last, false,
          reason: 'O Resumo deve liberar a saída nativa');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows mantém navegação sem retorno automático ao Resumo',
      (tester) async {
    await openBackTest(tester,
        platform: TargetPlatform.windows, size: const Size(1280, 900));
    appRouter.go('/accounts');
    await tester.pumpAndSettle();
    expect(await appRouter.routerDelegate.popRoute(), false);
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/accounts');
  });
  for (final path in ['/accounts', '/categories']) {
    testWidgets(
        '$path: Voltar/Cancelar protege cadastro alterado e preserva campos ao continuar',
        (tester) async {
      await openBackTest(tester);
      appRouter.go(path);
      await tester.pumpAndSettle();
      await tester.tap(
          find.text(path == '/accounts' ? 'Nova conta' : 'Nova categoria'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Novo nome');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Descartar alterações?'), findsOneWidget);
      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();
      expect(find.text('Novo nome'), findsOneWidget);
      expect(appRouter.routeInformationProvider.value.uri.path, path);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(appRouter.routeInformationProvider.value.uri.path, path);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mês compartilhado e filtros avançados nas três abas',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final transactions = _TransactionsStub();
    getIt.registerSingleton<DashboardRepository>(_DashboardStub());
    getIt.registerSingleton<TransactionsRepository>(transactions);
    getIt.registerSingleton<TransfersRepository>(_TransfersStub());
    getIt.registerSingleton<AccountsRepository>(_AccountsStub());
    getIt.registerSingleton<CategoriesRepository>(_CategoriesStub());
    addTearDown(() async {
      appRouter.go('/');
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await getIt.reset();
    });
    appRouter.go('/');
    await tester.pumpWidget(const FinApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dashboard-month-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dezembro'));
    await tester.pumpAndSettle();
    for (final path in ['/income', '/expenses']) {
      appRouter.go(path);
      await tester.pumpAndSettle();
      expect(find.text('Dezembro 2026'), findsOneWidget);
      expect(transactions.requestedFilters.last.from, DateTime(2026, 12));
      expect(transactions.requestedFilters.last.to, DateTime(2026, 12, 31));
      expect(find.text('Salário'), findsNothing);
      expect(find.text('Mercado'), findsNothing);
      expect(find.text('Todas as contas'), findsNothing);
      await tester.tap(find.text('Filtros'));
      await tester.pumpAndSettle();
      expect(find.text('Todas as contas'), findsOneWidget);
      await tester.tap(find.text('Todos os meses'));
      await tester.pumpAndSettle();
      expect(transactions.requestedFilters.last.from, isNull);
      await tester.tap(find.byTooltip('Fechar filtros'));
      await tester.pumpAndSettle();
      expect(
          find.text(path == '/income' ? 'Salário' : 'Mercado'), findsOneWidget);
      expect(referenceMonth.value, DateTime(2026, 12));
    }
    appRouter.go('/transfers');
    await tester.pumpAndSettle();
    expect(find.text('Dezembro 2026'), findsOneWidget);
    expect(find.text('Banco → Carteira'), findsOneWidget);
    expect(find.text('Setembro → Reserva'), findsNothing);
    await tester.tap(find.text('Filtros'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todos os meses'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fechar filtros'));
    await tester.pumpAndSettle();
    expect(find.text('Setembro → Reserva'), findsOneWidget);
    await tester.tap(find.byTooltip('Próximo mês'));
    await tester.pumpAndSettle();
    expect(find.text('Janeiro 2027'), findsOneWidget);
    expect(find.text('Banco → Carteira'), findsNothing);
    expect(find.text('Todos os meses'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'sidebar em paisagem respeita recorte do Android e permite rolagem',
      (tester) async {
    tester.view.physicalSize = const Size(915, 412);
    tester.view.devicePixelRatio = 1;
    getIt.registerSingleton<DashboardRepository>(_DashboardStub());
    addTearDown(() async {
      appRouter.go('/');
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await getIt.reset();
    });
    appRouter.go('/');
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: appRouter,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: const EdgeInsets.only(left: 32, bottom: 24)),
            child: child!)));
    await tester.pumpAndSettle();
    final tile = tester.getRect(find.byKey(const ValueKey('menu-/income')));
    final icon = tester.getRect(find.descendant(
        of: find.byKey(const ValueKey('menu-/income')),
        matching: find.byType(Icon)));
    expect(icon.left, greaterThanOrEqualTo(32));
    expect(icon.left, greaterThan(tile.left));
    expect(icon.right, lessThan(tile.right));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('menu-/settings')), 100,
        scrollable: find
            .descendant(
                of: find.byType(SafeArea).first,
                matching: find.byType(Scrollable))
            .first);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawer mobile separa receitas e despesas sem barra inferior',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final transactions = _TransactionsStub();
    getIt.registerSingleton<DashboardRepository>(_DashboardStub());
    getIt.registerSingleton<TransactionsRepository>(transactions);
    getIt.registerSingleton<AccountsRepository>(_AccountsStub());
    getIt.registerSingleton<CategoriesRepository>(_CategoriesStub());
    addTearDown(() async {
      appRouter.go('/');
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await getIt.reset();
    });
    appRouter.go('/');
    await tester.pumpWidget(const FinApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('Abrir menu'));
    await tester.pumpAndSettle();
    for (final label in [
      'Resumo',
      'Receitas',
      'Despesas',
      'Transferências',
      'Contas',
      'Categorias',
      'Configurações'
    ]) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.byKey(const ValueKey('menu-/income')));
    await tester.pumpAndSettle();
    expect(find.text('Salário'), findsOneWidget);
    expect(find.text('Mercado'), findsNothing);
    expect(transactions.requestedTypes.last, TransactionType.income);

    await tester.tap(find.byTooltip('Abrir menu'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('menu-/income')))
            .selected,
        isTrue);
    await tester.tap(find.byKey(const ValueKey('menu-/expenses')));
    await tester.pumpAndSettle();
    expect(find.text('Mercado'), findsOneWidget);
    expect(find.text('Salário'), findsNothing);
    expect(transactions.requestedTypes.last, TransactionType.expense);
    expect(find.byTooltip('Pagar hoje'), findsOneWidget);

    await tester.tap(find.byTooltip('Adicionar lançamento ou transferência'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receita').last);
    await tester.pumpAndSettle();
    expect(find.text('Nova receita'), findsOneWidget);
    expect(find.byType(TextFormField).first, findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Receitas'), findsOneWidget);
  });

  testWidgets('sidebar larga mantém as mesmas seções', (tester) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    getIt.registerSingleton<DashboardRepository>(_DashboardStub());
    getIt.registerSingleton<TransactionsRepository>(_TransactionsStub());
    getIt.registerSingleton<AccountsRepository>(_AccountsStub());
    getIt.registerSingleton<CategoriesRepository>(_CategoriesStub());
    addTearDown(() async {
      appRouter.go('/');
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await getIt.reset();
    });
    appRouter.go('/');
    await tester.pumpWidget(const FinApp());
    await tester.pumpAndSettle();
    expect(find.byTooltip('Abrir menu'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('menu-/income')));
    await tester.pumpAndSettle();
    expect(find.text('Salário'), findsOneWidget);
  });
}
