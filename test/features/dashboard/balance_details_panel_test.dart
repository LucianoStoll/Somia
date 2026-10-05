import 'dart:io';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/filters/reference_month.dart';
import 'package:finapp/core/routing/somia_shell.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/accounts/domain/money_minor.dart';
import 'package:finapp/features/balances/domain/balance_details.dart';
import 'package:finapp/features/dashboard/domain/dashboard_repository.dart';
import 'package:finapp/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:finapp/features/dashboard/presentation/dashboard_cubit.dart';
import 'package:finapp/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:finapp/features/dashboard/presentation/widgets/balance_details_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class Repository implements DashboardRepository {
  int income = 50000;
  int calls = 0;
  bool fail = false;
  @override
  Future<DashboardSummary> load(DateTime month) {
    calls++;
    if (fail) return Future.error(StateError('Falha'));
    final details = BalanceDetails(
        openingMinor: 100000,
        incomeMinor: income,
        expenseMinor: 20000,
        transferInMinor: 15000,
        transferOutMinor: 10000,
        cardPaymentsMinor: 5000,
        pendingIncomeMinor: 10000,
        pendingExpenseMinor: 25000,
        pendingTransferInMinor: 3000,
        pendingTransferOutMinor: 2000,
        pendingInvoicesMinor: 8000);
    const dollar =
        BalanceDetails(openingMinor: -5000, pendingIncomeMinor: 3000);
    return Future.value(DashboardSummary(month: month, currencies: [
      DashboardCurrencySummary(
          currencyCode: 'BRL',
          currentBalanceMinor: details.currentMinor,
          projectedBalanceMinor: details.projectedMinor,
          incomeMinor: income,
          expenseMinor: 20000,
          balanceDetails: details),
      DashboardCurrencySummary(
          currencyCode: 'USD',
          currentBalanceMinor: dollar.currentMinor,
          projectedBalanceMinor: dollar.projectedMinor,
          incomeMinor: 0,
          expenseMinor: 0,
          balanceDetails: dollar)
    ], recent: const []));
  }
}

void main() {
  late Repository repository;
  setUp(() async {
    await getIt.reset();
    repository = Repository();
    getIt.registerSingleton<DashboardRepository>(repository);
    referenceMonth.select(DateTime(2026, 10));
  });
  tearDown(() async {
    await getIt.reset();
    referenceMonth.select(DateTime.now());
  });
  Future<DashboardCubit> open(WidgetTester tester,
      {TargetPlatform platform = TargetPlatform.android,
      Size size = const Size(390, 844),
      double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark.copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: const SomiaShell(location: '/', child: DashboardPage())));
    await tester.pumpAndSettle();
    return tester
        .element(find.byType(BalanceDetailCard).first)
        .read<DashboardCubit>();
  }

  Future<void> scrollTo(WidgetTester tester, String key) async {
    await tester.scrollUntilVisible(find.byKey(ValueKey(key)), 200,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('balance-details-scroll')),
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
  }

  for (final config in [
    (TargetPlatform.android, const Size(390, 844), 1.0),
    (TargetPlatform.android, const Size(320, 640), 2.0),
    (TargetPlatform.windows, const Size(1280, 900), 1.0),
    (TargetPlatform.windows, const Size(780, 560), 2.0)
  ]) {
    testWidgets('abre, reconcilia, rola e fecha $config', (tester) async {
      await open(tester,
          platform: config.$1, size: config.$2, scale: config.$3);
      await tester.ensureVisible(
          find.byKey(const ValueKey('balance-detail-BRL')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('balance-detail-BRL')).first);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('balance-details-panel')), findsOneWidget);
      expect(find.text('Outubro 2026 · BRL'), findsOneWidget);
      expect(
          config.$1 == TargetPlatform.android
              ? find.byType(BottomSheet)
              : find.byType(Dialog),
          findsOneWidget);
      await scrollTo(tester, 'balance-current');
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('balance-current')),
              matching: find.text(MoneyMinor.display(130000, 'BRL'))),
          findsOneWidget);
      await scrollTo(tester, 'balance-projected');
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('balance-projected')),
              matching: find.text(MoneyMinor.display(108000, 'BRL'))),
          findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Fechar detalhamento'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('balance-details-panel')), findsNothing);
    });
  }
  testWidgets(
      'aberto acompanha atualização e mês; falha permite tentar novamente',
      (tester) async {
    final cubit = await open(tester);
    await tester.tap(find.byKey(const ValueKey('balance-detail-BRL')));
    await tester.pumpAndSettle();
    repository.income = 60000;
    await cubit.load();
    await tester.pumpAndSettle();
    await scrollTo(tester, 'balance-current');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('balance-current')),
            matching: find.text(MoneyMinor.display(140000, 'BRL'))),
        findsOneWidget);
    referenceMonth.select(DateTime(2027, 1));
    await tester.pumpAndSettle();
    expect(find.text('Janeiro 2027 · BRL'), findsOneWidget);
    repository.fail = true;
    await cubit.load();
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find
        .descendant(
            of: find.byKey(const ValueKey('balance-details-scroll')),
            matching: find.byType(Scrollable))
        .first);
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Tentar novamente'), findsWidgets);
    repository.fail = false;
    await tester.tap(find.text('Tentar novamente').last);
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar o resumo.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Voltar e toque externo fecham painel sem sair do Resumo',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('balance-detail-BRL')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('balance-details-panel')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('balance-detail-BRL')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('balance-details-panel')), findsNothing);
    expect(find.byType(DashboardPage), findsOneWidget);
  });
  testWidgets('moeda selecionada e saldo negativo preservados', (tester) async {
    await open(tester,
        platform: TargetPlatform.windows, size: const Size(1280, 900));
    final card = find.byKey(const ValueKey('desktop-projected-USD'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('Outubro 2026 · USD'), findsOneWidget);
    expect(find.text('Outubro 2026 · BRL'), findsNothing);
    await scrollTo(tester, 'balance-projected');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('balance-projected')),
            matching: find.text(MoneyMinor.display(-2000, 'USD'))),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('renderiza detalhamento do saldo', (tester) async {
      final fonts = Directory(
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts');
      final font = FontLoader('Roboto'), icons = FontLoader('MaterialIcons');
      for (final f in fonts.listSync().whereType<File>()) {
        if (f.path.endsWith('Roboto-Regular.ttf') ||
            f.path.endsWith('Roboto-Bold.ttf')) {
          font.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
        }
        if (f.path.endsWith('MaterialIcons-Regular.otf')) {
          icons
              .addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
        }
      }
      await font.load();
      await icons.load();
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('balance-detail-BRL')));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('balance-details-current-mobile-preview.png'));
      await scrollTo(tester, 'balance-projected');
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('balance-details-projected-mobile-preview.png'));
    });
  }
}
