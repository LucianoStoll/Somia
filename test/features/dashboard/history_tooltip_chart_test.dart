import 'dart:io';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/filters/reference_month.dart';
import 'package:finapp/core/routing/somia_shell.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/accounts/domain/money_minor.dart';
import 'package:finapp/features/dashboard/domain/dashboard_repository.dart';
import 'package:finapp/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:finapp/features/dashboard/presentation/dashboard_cubit.dart';
import 'package:finapp/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:finapp/features/dashboard/presentation/widgets/history_tooltip_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

List<DashboardMonthTotal> history({int amount = 10000}) => [
      for (var i = 0; i < 6; i++)
        DashboardMonthTotal(
            DateTime(2026, 5 + i),
            i == 0 ? 0 : amount,
            i == 0
                ? 0
                : i == 5
                    ? amount + 2500
                    : 2500)
    ];

class Repository implements DashboardRepository {
  int amount = 10000;
  @override
  Future<DashboardSummary> load(DateTime month) =>
      Future.value(DashboardSummary(month: month, currencies: [
        DashboardCurrencySummary(
            currencyCode: 'BRL',
            currentBalanceMinor: 999999,
            projectedBalanceMinor: 999999,
            incomeMinor: amount,
            expenseMinor: amount + 2500,
            history: history(amount: amount))
      ], recent: const []));
}

void main() {
  setUp(() async {
    await getIt.reset();
    referenceMonth.select(DateTime(2026, 10));
  });
  tearDown(() async {
    await getIt.reset();
    referenceMonth.select(DateTime.now());
  });
  Future<void> size(WidgetTester tester, Size viewport) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Finder month(int value, {int year = 2026}) =>
      find.byKey(ValueKey('history-month-BRL-$year-$value'));
  Finder tooltip() => find.byKey(const ValueKey('history-tooltip'));
  Finder value(int amount) => find.descendant(
      of: tooltip(), matching: find.text(MoneyMinor.display(amount, 'BRL')));
  Future<void> standalone(WidgetTester tester, List<DashboardMonthTotal> data,
      {double scale = 1, bool bottom = false, bool scroll = false}) async {
    Widget chart = HistoryTooltipChart(
        key: const ValueKey('chart'),
        history: data,
        currencyCode: 'BRL',
        builder: (target) => Row(children: [
              for (final item in data)
                Expanded(
                    child: target(
                        item, Center(child: Text('${item.month.month}'))))
            ]));
    chart = SizedBox(height: 100, child: chart);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.all(24)),
            child: child!),
        home: Scaffold(
            body: scroll
                ? ListView(children: [
                    const SizedBox(height: 500),
                    chart,
                    const SizedBox(height: 800)
                  ])
                : Stack(children: [
                    Positioned(
                        left: 24,
                        right: 24,
                        top: bottom ? null : 24,
                        bottom: bottom ? 24 : null,
                        child: chart)
                  ]))));
    await tester.pumpAndSettle();
  }

  for (final config in [
    (const Size(320, 640), 1.0, false),
    (const Size(320, 640), 2.0, true),
    (const Size(780, 360), 2.0, false),
    (const Size(1280, 900), 1.0, true)
  ]) {
    testWidgets(
        'balão cabe nas bordas, mostra zero e resultado negativo $config',
        (tester) async {
      await size(tester, config.$1);
      await standalone(tester, history(), scale: config.$2, bottom: config.$3);
      for (final selected in [5, 10]) {
        await tester.tap(month(selected));
        await tester.pumpAndSettle();
        expect(tooltip(), findsOneWidget);
        expect(
            find.descendant(
                of: tooltip(),
                matching:
                    find.text(selected == 5 ? 'Maio 2026' : 'Outubro 2026')),
            findsOneWidget);
        if (selected == 5) {
          expect(value(0), findsNWidgets(3));
        } else {
          expect(value(10000), findsOneWidget);
          expect(value(12500), findsOneWidget);
          expect(value(-2500), findsOneWidget);
        }
        final rect = tester.getRect(tooltip());
        expect(rect.left, greaterThanOrEqualTo(31));
        expect(rect.right, lessThanOrEqualTo(config.$1.width - 31));
        expect(rect.top, greaterThanOrEqualTo(31));
        expect(rect.bottom, lessThanOrEqualTo(config.$1.height - 31));
        expect(tester.takeException(), isNull);
      }
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(tooltip(), findsNothing);
    });
  }
  testWidgets(
      'dados atualizados mantêm mês escolhido e período removido fecha balão',
      (tester) async {
    await size(tester, const Size(390, 844));
    await standalone(tester, history());
    await tester.tap(month(9));
    await tester.pumpAndSettle();
    expect(value(7500), findsOneWidget);
    await standalone(tester, history(amount: 20000));
    expect(tooltip(), findsOneWidget);
    expect(value(20000), findsOneWidget);
    expect(value(17500), findsOneWidget);
    await standalone(tester, [DashboardMonthTotal(DateTime(2027, 1), 0, 0)]);
    expect(tooltip(), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'valores grandes continuam completos em tela baixa com texto ampliado',
      (tester) async {
    await size(tester, const Size(320, 360));
    await standalone(tester,
        [DashboardMonthTotal(DateTime(2026, 10), 123456789012, 99999999999)],
        scale: 2);
    await tester.tap(month(10));
    await tester.pumpAndSettle();
    expect(value(123456789012), findsOneWidget);
    expect(value(99999999999), findsOneWidget);
    final result = value(23456789013);
    await tester.ensureVisible(result);
    await tester.pumpAndSettle();
    expect(result, findsOneWidget);
    expect(tester.getRect(tooltip()).bottom, lessThanOrEqualTo(329));
    expect(tester.takeException(), isNull);
  });
  testWidgets('rolar fecha e descartar gráfico remove overlay', (tester) async {
    await size(tester, const Size(390, 844));
    await standalone(tester, history(), scroll: true);
    await tester.ensureVisible(month(9));
    await tester.tap(month(9));
    await tester.pumpAndSettle();
    expect(tooltip(), findsOneWidget);
    final position = tester
        .state<ScrollableState>(find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first)
        .position;
    position.jumpTo(position.pixels + 100);
    await tester.pumpAndSettle();
    expect(tooltip(), findsNothing);
    await tester.ensureVisible(month(9));
    await tester.tap(month(9));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tooltip(), findsNothing);
    expect(tester.takeException(), isNull);
  });
  Future<DashboardCubit> dashboard(WidgetTester tester, Repository repo,
      {Size viewport = const Size(390, 844),
      TargetPlatform platform = TargetPlatform.android}) async {
    await size(tester, viewport);
    getIt.registerSingleton<DashboardRepository>(repo);
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark.copyWith(platform: platform),
        home: const SomiaShell(location: '/', child: DashboardPage())));
    await tester.pumpAndSettle();
    await tester.ensureVisible(month(10));
    await tester.pumpAndSettle();
    return tester
        .element(find.byType(HistoryTooltipChart))
        .read<DashboardCubit>();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
        'dashboard $platform: barras/mês acionam valores reais do gráfico e atualização',
        (tester) async {
      final repo = Repository();
      final cubit = await dashboard(tester, repo,
          viewport: platform == TargetPlatform.android
              ? const Size(390, 844)
              : const Size(1280, 900),
          platform: platform);
      await tester.tap(month(10));
      await tester.pumpAndSettle();
      expect(value(-2500), findsOneWidget);
      expect(value(999999), findsNothing);
      repo.amount = 20000;
      await cubit.load();
      await tester.pumpAndSettle();
      expect(value(20000), findsOneWidget);
      expect(value(22500), findsOneWidget);
      await tester.tap(month(9));
      await tester.pumpAndSettle();
      expect(value(17500), findsOneWidget);
      expect(tooltip(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
      testWidgets('renderiza balão $platform', (tester) async {
        final fonts = Directory(
            '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts');
        final font = FontLoader('Roboto'), icons = FontLoader('MaterialIcons');
        for (final f in fonts.listSync().whereType<File>()) {
          if (f.path.endsWith('Roboto-Regular.ttf') ||
              f.path.endsWith('Roboto-Bold.ttf')) {
            font.addFont(
                Future.value(ByteData.sublistView(f.readAsBytesSync())));
          }
          if (f.path.endsWith('MaterialIcons-Regular.otf')) {
            icons.addFont(
                Future.value(ByteData.sublistView(f.readAsBytesSync())));
          }
        }
        await font.load();
        await icons.load();
        await dashboard(tester, Repository(),
            viewport: platform == TargetPlatform.android
                ? const Size(390, 844)
                : const Size(1280, 900),
            platform: platform);
        await tester.tap(month(10));
        await tester.pumpAndSettle();
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(platform == TargetPlatform.android
                ? 'history-tooltip-mobile-preview.png'
                : 'history-tooltip-desktop-preview.png'));
      });
    }
  }
}
