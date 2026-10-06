import 'dart:async';
import 'dart:io';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/filters/reference_month.dart';
import 'package:finapp/core/routing/somia_shell.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/accounts/data/account_statement_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/accounts/domain/account_statement.dart';
import 'package:finapp/features/accounts/presentation/account_statement_cubit.dart';
import 'package:finapp/features/accounts/presentation/account_statement_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const account = Account(
    id: 'a',
    name: 'Mercado Pago',
    type: AccountType.checking,
    currencyCode: 'BRL',
    initialBalanceMinor: 100000,
    currentBalanceMinor: 125000,
    projectedBalanceMinor: 118000,
    isArchived: false,
    includeInAnalytics: true,
    institutionId: 'mercadopago');
AccountStatement fixture(DateTime month) {
  StatementSection section(bool projected) => StatementSection(
          openingMinor: 100000,
          closingMinor: projected ? 118000 : 125000,
          dailyBalances: List.generate(
              30,
              (i) => i < 4
                  ? 100000
                  : i < 11 || !projected
                      ? 125000
                      : 118000),
          days: [
            StatementDay(
                date: DateTime.utc(month.year, month.month, 5),
                closingMinor: 125000,
                entries: [
                  StatementEntry(
                      id: 'income',
                      description: 'Salário',
                      date: DateTime.utc(month.year, month.month, 5),
                      amountMinor: 30000,
                      kind: StatementKind.income,
                      effective: true),
                  StatementEntry(
                      id: 'expense',
                      description: 'Mercado',
                      date: DateTime.utc(month.year, month.month, 5),
                      amountMinor: -5000,
                      kind: StatementKind.expense,
                      effective: true,
                      detail: 'Alimentação / Supermercado')
                ]),
            if (projected)
              StatementDay(
                  date: DateTime.utc(month.year, month.month, 12),
                  closingMinor: 118000,
                  entries: [
                    StatementEntry(
                        id: 'pending',
                        description: 'Conta pendente',
                        date: DateTime.utc(month.year, month.month, 12),
                        amountMinor: -7000,
                        kind: StatementKind.expense,
                        effective: false)
                  ])
          ]);
  return AccountStatement(
      account: account,
      month: month,
      realized: section(false),
      projected: section(true));
}

class FakeStatementRepository implements AccountStatementRepository {
  final calls = <DateTime>[];
  bool fails = false;
  final pending = <Completer<AccountStatement>>[];
  bool delayed = false;
  @override
  Future<AccountStatement> load(String id, DateTime month, {DateTime? today}) {
    calls.add(month);
    if (fails) return Future.error(StateError('Conta não encontrada.'));
    if (delayed) {
      final c = Completer<AccountStatement>();
      pending.add(c);
      return c.future;
    }
    return Future.value(fixture(month));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeStatementRepository repo;
  setUp(() async {
    await getIt.reset();
    repo = FakeStatementRepository();
    getIt.registerSingleton<AccountStatementRepository>(repo);
    referenceMonth.select(DateTime(2026, 9));
  });
  tearDown(() async {
    await getIt.reset();
    referenceMonth.select(DateTime.now());
  });
  Future<GoRouter> open(WidgetTester tester,
      {Size size = const Size(390, 844),
      TargetPlatform platform = TargetPlatform.android,
      double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final router = GoRouter(initialLocation: '/accounts/a', routes: [
      ShellRoute(
          builder: (context, state, child) =>
              SomiaSectionBackScope(location: state.uri.path, child: child),
          routes: [
            GoRoute(
                path: '/',
                builder: (_, __) => const Scaffold(body: Text('Resumo'))),
            GoRoute(
                path: '/accounts',
                builder: (_, __) => const Scaffold(body: Text('Contas')),
                routes: [
                  GoRoute(
                      path: ':id',
                      builder: (_, state) => AccountStatementPage(
                          accountId: state.pathParameters['id']!))
                ])
          ])
    ]);
    addTearDown(() {
      router.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.dark.copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!)));
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> bottom(WidgetTester tester) async {
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('statement-day-5')), 250,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('account-statement-scroll')),
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
  }

  for (final config in [
    (const Size(390, 844), TargetPlatform.android, 1.0),
    (const Size(320, 640), TargetPlatform.android, 2.0),
    (const Size(1280, 900), TargetPlatform.windows, 1.0)
  ]) {
    testWidgets(
        'extrato diário apenas consulta, realizado/previsto ${config.$1}',
        (tester) async {
      await open(tester,
          size: config.$1, platform: config.$2, scale: config.$3);
      expect(find.text('Detalhes da conta'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byTooltip('Pagar hoje'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('statement-projected')));
      await tester.pumpAndSettle();
      await bottom(tester);
      expect(find.byKey(const ValueKey('statement-day-5')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('statement-day-5')),
              matching: find.text('Saldo ao fim do dia')),
          findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('statement-day-12')), 250,
          scrollable: find
              .descendant(
                  of: find.byKey(const ValueKey('account-statement-scroll')),
                  matching: find.byType(Scrollable))
              .first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('statement-day-12')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('statement-day-12')),
              matching: find.text('Saldo ao fim do dia')),
          findsOneWidget);
      expect(find.text('Conta pendente'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('mês compartilhado, atualizar e retorno Android', (tester) async {
    final router = await open(tester);
    await tester.tap(find.byTooltip('Próximo mês'));
    await tester.pumpAndSettle();
    expect(referenceMonth.value, DateTime(2026, 10));
    expect(repo.calls.last, DateTime(2026, 10));
    await tester.tap(find.byTooltip('Atualizar extrato'));
    await tester.pumpAndSettle();
    expect(repo.calls.length, 3);
    expect(await router.routerDelegate.popRoute(), true);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/accounts');
    expect(await router.routerDelegate.popRoute(), true);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
  });
  testWidgets('falha permite tentar novamente e botão retorna no Windows',
      (tester) async {
    repo.fails = true;
    final router = await open(tester, platform: TargetPlatform.windows);
    expect(find.text('Conta não encontrada.'), findsOneWidget);
    repo.fails = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('statement-realized')), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/accounts');
  });
  test(
      'troca de mês ignora respostas antigas e descarte ignora resposta pendente',
      () async {
    repo.delayed = true;
    final selection = ReferenceMonth(DateTime(2026, 9));
    final cubit = AccountStatementCubit(repo, 'a', selection: selection);
    selection.move(1);
    repo.pending[1].complete(fixture(DateTime(2026, 10)));
    await Future<void>.delayed(Duration.zero);
    repo.pending[0].complete(fixture(DateTime(2026, 9)));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.statement!.month, DateTime(2026, 10));
    selection.move(1);
    await cubit.close();
    repo.pending[2].complete(fixture(DateTime(2026, 11)));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.statement!.month, DateTime(2026, 10));
    final count = repo.calls.length;
    selection.move(1);
    expect(repo.calls.length, count);
    selection.dispose();
  });
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('renderiza extrato mobile', (tester) async {
      final fonts = Directory(
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts');
      final font = FontLoader('Roboto'), icons = FontLoader('MaterialIcons');
      for (final file in fonts.listSync().whereType<File>()) {
        if (file.path.endsWith('Roboto-Regular.ttf') ||
            file.path.endsWith('Roboto-Bold.ttf')) {
          font.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
        if (file.path.endsWith('MaterialIcons-Regular.otf')) {
          icons.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await font.load();
      await icons.load();
      await open(tester);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('account-statement-summary-mobile-preview.png'));
      await bottom(tester);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('account-statement-daily-mobile-preview.png'));
    });
  }
}
