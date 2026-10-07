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
      await tester.tap(find.text('Nova dívida'));
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
      await tester.pump();
      if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW'))
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(platform == TargetPlatform.android
                ? 'debt-form-mobile-preview.png'
                : 'debt-form-desktop-preview.png'));
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect((await repo.load()).single.balanceMinor, 100000);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW'))
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(platform == TargetPlatform.android
                ? 'debts-mobile-preview.png'
                : 'debts-desktop-preview.png'));
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
      await tester.tap(find.text('Vincular'));
      await tester.pumpAndSettle();
      expect(find.text('Selecione uma despesa.'), findsOneWidget);
      expect((await repo.load()).single.id, id);
      expect((await repo.load()).single.payments, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
