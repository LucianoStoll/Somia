import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/filters/reference_month.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/analysis/data/expense_analysis_repository.dart';
import 'package:finapp/features/analysis/presentation/expense_analysis_page.dart';
import 'expense_analysis_repository_test.dart' as fixture;

void main() {
  late AppDatabase db;
  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    await fixture.seedAnalysis(db);
    await fixture.tx(db, 'Mercado outubro', 18000, 10);
    await fixture.tx(db, 'Mercado setembro', 12000, 9, effective: true);
    await fixture.tx(db, 'Mercado agosto', 15000, 8, effective: true);
    await fixture.tx(db, 'Mercado julho', 9000, 7, effective: true);
    await fixture.tx(db, 'Parcela carro', 53000, 11);
    await fixture.invoice(db, 'nov', 11, 20000);
    await db.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,include_in_balance,created_at,updated_at) VALUES('i','Reserva CDB','investment','BRL',450000,0,0,0),('w','Dinheiro','cash','BRL',-2000,1,0,0)");
    getIt.registerSingleton<ExpenseAnalysisRepository>(
        ExpenseAnalysisRepository(db, now: () => DateTime(2026, 10, 9)));
    referenceMonth.select(DateTime(2026, 10));
  });
  tearDown(() async {
    await getIt.reset();
    await db.close();
  });
  Future<void> open(WidgetTester t, TargetPlatform platform,
      {double scale = 1}) async {
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    t.view.physicalSize = platform == TargetPlatform.android
        ? const Size(390, 844)
        : const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark.copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: const ExpenseAnalysisPage()));
    await t.pumpAndSettle();
  }

  Future<void> select(WidgetTester t, int view) async {
    t
        .widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>))
        .onChanged!(view);
    await t.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('categorias, detalhes e quatro análises $platform', (t) async {
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await open(t, platform);
      expect(find.text('Total: R\$ 180,00'), findsOneWidget);
      await t.tap(find.text('Alimentação'));
      await t.pumpAndSettle();
      expect(find.text('Mercado outubro'), findsOneWidget);
      expect(find.text('Mercado'), findsOneWidget);
      await t.tap(find.byTooltip('Fechar detalhes'));
      await t.pumpAndSettle();
      await select(t, 1);
      expect(find.text('Média dos 3 meses'), findsOneWidget);
      await select(t, 2);
      expect(find.text('11/2026 · R\$ 730,00'), findsOneWidget);
      await select(t, 3);
      expect(find.text('Investimento'), findsOneWidget);
      expect(find.text('R\$ -20,00'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'texto ampliado e mês compartilhado não mantêm dados do mês anterior',
      (t) async {
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await open(t, TargetPlatform.android, scale: 1.8);
    expect(t.takeException(), isNull);
    referenceMonth.select(DateTime(2026, 9));
    await t.pumpAndSettle();
    expect(find.text('Total: R\$ 120,00'), findsOneWidget);
    for (var i = 1; i < 4; i++) {
      await select(t, i);
      expect(t.takeException(), isNull);
    }
  });
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('prévias análises Android e Windows', (t) async {
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
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
      for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
        await open(t, platform);
        final suffix =
            platform == TargetPlatform.android ? 'mobile' : 'desktop';
        for (var i = 0; i < 4; i++) {
          await select(t, i);
          await expectLater(find.byType(ExpenseAnalysisPage),
              matchesGoldenFile('analysis-$i-$suffix-preview.png'));
        }
      }
    });
  }
}
