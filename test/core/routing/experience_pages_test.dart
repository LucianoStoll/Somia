import 'dart:io';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/routing/somia_shell.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/categories/domain/categories_repository.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/categories/presentation/categories_page.dart';
import 'package:finapp/features/settings/presentation/settings_page.dart';
import 'package:finapp/features/transactions/presentation/transactions_page.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'reference_form_test.dart' as forms;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  late AppDatabase db;
  late CategoriesRepository categories;
  late String food;
  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    categories = SqliteCategoriesRepository(db);
    getIt.registerSingleton<CategoriesRepository>(categories);
    food = (await categories.create(const CategoryDraft(
            name: 'Alimentação',
            type: CategoryType.expense,
            iconKey: 'food',
            colorArgb: 0xff388e3c)))
        .id;
    await categories.create(CategoryDraft(
        name: 'Restaurante', type: CategoryType.expense, parentId: food));
    final other = await categories.create(const CategoryDraft(
        name: 'Transporte', type: CategoryType.expense, iconKey: 'transport'));
    await categories.create(CategoryDraft(
        name: 'Combustível', type: CategoryType.expense, parentId: other.id));
  });
  tearDown(() async {
    await getIt.reset();
    await db.close();
  });
  Future<GoRouter> open(
      WidgetTester tester, String path, TargetPlatform platform) async {
    tester.view.physicalSize = platform == TargetPlatform.android
        ? const Size(390, 844)
        : const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(initialLocation: path, routes: [
      GoRoute(
          path: '/settings',
          builder: (_, state) => SomiaSectionBackScope(
              location: '/settings',
              child:
                  SettingsPage(section: state.uri.queryParameters['section']))),
      GoRoute(
          path: '/categories', builder: (_, state) => const CategoriesPage()),
      GoRoute(
          path: '/',
          builder: (_, state) => const Scaffold(body: Text('Resumo'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.dark.copyWith(platform: platform)));
    await tester.pumpAndSettle();
    return router;
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
        'categoria recolhe independentemente e atalho cria filha $platform',
        (tester) async {
      await open(tester, '/categories', platform);
      await tester.tap(find.byKey(ValueKey('category-expand-$food')));
      await tester.pumpAndSettle();
      expect(find.text('Restaurante'), findsNothing);
      expect(find.text('Combustível'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('category-add-$food')));
      await tester.pumpAndSettle();
      expect(find.text('Nova subcategoria'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'Padaria');
      await tester.tap(find.text('Salvar categoria'));
      await tester.pumpAndSettle();
      final saved =
          (await categories.list()).singleWhere((c) => c.name == 'Padaria');
      expect(saved.parentId, food);
      expect(saved.type, CategoryType.expense);
      expect(find.text('Padaria'), findsOneWidget);
      expect(find.text('Restaurante'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('configurações agrupadas abrem backup e retornam $platform',
        (tester) async {
      final router = await open(tester, '/settings', platform);
      expect(find.text('Finanças'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Backup e restauração'), 180);
      await tester.tap(find.text('Backup e restauração'));
      await tester.pumpAndSettle();
      expect(find.text('Exportar backup'), findsOneWidget);
      expect(find.text('Restaurar backup'), findsOneWidget);
      if (platform == TargetPlatform.android) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byType(BackButton));
      }
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.toString(), '/settings');
      expect(find.text('Finanças'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('seletor de muitas contas ocupa área limitada e mantém descrição',
      (tester) async {
    final accounts = List.generate(
        30,
        (i) => Account(
            id: 'a$i',
            name: 'Banco $i',
            type: AccountType.checking,
            currencyCode: 'BRL',
            initialBalanceMinor: 0,
            currentBalanceMinor: 0,
            projectedBalanceMinor: 0,
            includeInAnalytics: true,
            isArchived: false));
    await forms.open(
        tester, TransactionForm(accounts: accounts, categories: const []));
    await tester.enterText(
        find.byType(TextFormField).first, 'Despesa em edição');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final dropdown = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    final popup = find.byType(Scrollable).last;
    expect(tester.getSize(popup).height, lessThanOrEqualTo(280));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(forms.field(tester, 0).controller!.text, 'Despesa em edição');
    expect(tester.takeException(), isNull);
  });
  const render = bool.fromEnvironment('SOMIA_RENDER_PREVIEW');
  testWidgets('prévias de categorias e configurações', (tester) async {
    if (!render) return;
    final loader = FontLoader('Roboto')
      ..addFont(File(
              '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf')
          .readAsBytes()
          .then((b) => ByteData.sublistView(b)));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(File(
              '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then((b) => ByteData.sublistView(b)));
    await icons.load();
    for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
      for (final page in ['categories', 'settings']) {
        await open(tester, '/$page', platform);
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
                '$page-${platform == TargetPlatform.android ? 'mobile' : 'desktop'}-preview.png'));
      }
    }
  });
}
