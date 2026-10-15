import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/filters/reference_month.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/widgets/monetary_calculator.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/accounts_repository.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/categories/domain/categories_repository.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/planning/data/planning_repository.dart';
import 'package:finapp/features/planning/domain/planning.dart';
import 'package:finapp/features/planning/presentation/planning_page.dart';

void main() {
  late AppDatabase db;
  late PlanningRepository repo;
  late String category, account;
  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    repo = PlanningRepository(db);
    final accounts = SqliteAccountsRepository(db),
        categories = SqliteCategoriesRepository(db);
    account = (await accounts.create(const AccountDraft(
            name: 'Minha reserva',
            type: AccountType.savings,
            currencyCode: 'BRL',
            initialBalanceMinor: 40000,
            includeInAnalytics: true)))
        .id;
    category = (await categories.create(const CategoryDraft(
            name: 'Alimentação', type: CategoryType.expense)))
        .id;
    getIt.registerSingleton<PlanningRepository>(repo);
    getIt.registerSingleton<AccountsRepository>(accounts);
    getIt.registerSingleton<CategoriesRepository>(categories);
    referenceMonth.select(DateTime.now());
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
        home: const PlanningPage()));
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('cria limite mensal e navega para metas $platform',
        (tester) async {
      await open(tester, platform);
      await tester.tap(find.text('Novo limite'));
      await tester.pumpAndSettle();
      final field = find.byType(DropdownButtonFormField<String>).first;
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alimentação').last);
      await tester.pumpAndSettle();
      tester
          .widget<MonetaryCalculatorField>(find.byType(MonetaryCalculatorField))
          .controller
          .text = '500,00';
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar limite'));
      await tester.pumpAndSettle();
      expect((await repo.budgets(referenceMonth.value)).single.amount, 50000);
      expect(find.text('Limite: R\$ 500,00'), findsOneWidget);
      await tester.tap(find.text('Metas'));
      await tester.pumpAndSettle();
      expect(find.text('Nova meta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('meta vincula conta e indicadores sem renda $platform',
        (tester) async {
      await open(tester, platform);
      await tester.tap(find.text('Metas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nova meta'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Viagem');
      FocusManager.instance.primaryFocus?.unfocus();
      tester
          .widget<MonetaryCalculatorField>(find.byType(MonetaryCalculatorField))
          .controller
          .text = '1000,00';
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Minha reserva'));
      await tester.tap(find.text('Minha reserva'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar meta'));
      await tester.pumpAndSettle();
      expect((await repo.goals()).single.saved, 40000);
      await tester.tap(find.text('Indicadores'));
      await tester.pumpAndSettle();
      expect(find.text('Sem movimentos neste mês.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('prévias do planejamento', (tester) async {
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
      await repo.saveBudget(referenceMonth.value, category, 'BRL', 50000);
      await repo.saveGoal(GoalDraft(
          name: 'Viagem',
          kind: 'goal',
          currency: 'BRL',
          target: 100000,
          accounts: [account]));
      for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
        await open(tester, platform);
        final suffix =
            platform == TargetPlatform.android ? 'mobile' : 'desktop';
        await expectLater(find.byType(PlanningPage),
            matchesGoldenFile('planning-$suffix-preview.png'));
        await tester.tap(find.text('Metas'));
        await tester.pumpAndSettle();
        await expectLater(find.byType(PlanningPage),
            matchesGoldenFile('goals-$suffix-preview.png'));
      }
    });
  }
}
