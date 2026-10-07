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
import 'package:finapp/features/assets/presentation/assets_page.dart';

Future<void> _fonts() async {
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
}

void main() {
  setUpAll(_fonts);
  late AppDatabase db;
  late SqliteAssetsRepository repo;
  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    repo = SqliteAssetsRepository(db);
    getIt.registerSingleton<AssetsRepository>(repo);
  });
  tearDown(() async {
    await getIt.reset();
    await db.close();
  });
  Future<void> open(WidgetTester tester, TargetPlatform platform,
      {double scale = 1}) async {
    tester.view.physicalSize = platform == TargetPlatform.android
        ? const Size(390, 844)
        : const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark.copyWith(platform: platform),
        builder: (c, child) => MediaQuery(
            data:
                MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: const AssetsPage()));
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
        'cadastro de bem exige credor e preserva campos; avaliação salva histórico $platform',
        (tester) async {
      await open(tester, platform);
      await tester.tap(find.text('Novo bem'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Nome do bem'), 'Palio');
      final fields = tester
          .widgetList<MonetaryCalculatorField>(
              find.byType(MonetaryCalculatorField))
          .toList();
      fields[0].controller.text = '30000,00';
      fields[1].controller.text = '25000,00';
      fields[2].controller.text = '10000,00';
      await tester.pump();
      if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(platform == TargetPlatform.android
                ? 'asset-form-mobile-preview.png'
                : 'asset-form-desktop-preview.png'));
      }
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect((await repo.load()).assets, isEmpty);
      expect(find.text('Informe o credor.'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Credor / banco do financiamento'),
          'Banco');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect((await repo.load()).netMinor, 1500000);
      await tester.scrollUntilVisible(find.text('Atualizar avaliação'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Atualizar avaliação'));
      await tester.pumpAndSettle();
      final values = tester
          .widgetList<MonetaryCalculatorField>(
              find.byType(MonetaryCalculatorField))
          .toList();
      values[0].controller.text = '26000,00';
      values[1].controller.text = '9000,00';
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect((await repo.load()).netMinor, 1700000);
      expect((await repo.load()).assets.single.history, hasLength(2));
      expect(tester.takeException(), isNull);
    });
    testWidgets('patrimônio renderiza bens e financiamento $platform',
        (tester) async {
      await repo.save(
          AssetDraft(
              name: 'Palio',
              kind: AssetKind.vehicle,
              acquiredAt: DateTime(2025, 1),
              acquisitionMinor: 3000000),
          initial: AssetValuationDraft(
              date: DateTime(2026, 1),
              valueMinor: 2500000,
              debtMinor: 1000000,
              creditor: 'Banco'));
      await open(tester, platform,
          scale: platform == TargetPlatform.android ? 1.2 : 1);
      expect(find.text('Patrimônio líquido cadastrado'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Palio'), 120);
      await tester.pumpAndSettle();
      expect(find.text('Palio'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
        await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
        await tester.pumpAndSettle();
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(platform == TargetPlatform.android
                ? 'assets-mobile-preview.png'
                : 'assets-desktop-preview.png'));
      }
    });
  }
}
