import 'dart:io';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/widgets/movement_form_frame.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/accounts/presentation/accounts_page.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/categories/presentation/categories_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const parent = FinanceCategory(
    id: 'parent',
    name: 'Categoria principal longa para testar apresentação',
    type: CategoryType.expense,
    parentId: null,
    isArchived: true,
    iconKey: 'home',
    colorArgb: 0xff1976d2);
const child = FinanceCategory(
    id: 'child',
    name: 'Filha',
    type: CategoryType.expense,
    parentId: 'parent',
    isArchived: false,
    iconKey: 'food',
    colorArgb: 0xff388e3c);
const account = Account(
    id: 'bank',
    name: 'Investimento',
    type: AccountType.investment,
    currencyCode: 'USD',
    initialBalanceMinor: -12345,
    currentBalanceMinor: 500,
    projectedBalanceMinor: 1000,
    isArchived: true,
    includeInAnalytics: false,
    includeInBalance: false);

Future<void> open(WidgetTester tester, Widget form,
    {TargetPlatform platform = TargetPlatform.android,
    Size size = const Size(390, 844),
    double scale = 1,
    ValueChanged<Object?>? onResult}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });
  await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark.copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                  onPressed: () async {
                    final result =
                        await showMovementForm<Object>(context, (_) => form);
                    onResult?.call(result);
                  },
                  child: const Text('Abrir'))))));
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

Widget form(String kind) => kind == 'account'
    ? const AccountForm()
    : CategoryForm(
        categories: const [parent, child],
        defaultType: CategoryType.expense,
        category: kind == 'subcategory' ? child : null);
String save(String kind) =>
    kind == 'account' ? 'Salvar conta' : 'Salvar categoria';
TextField field(WidgetTester tester, int index) =>
    tester.widget<TextField>(find.descendant(
        of: find.byType(TextFormField).at(index),
        matching: find.byType(TextField)));

void main() {
  for (final kind in ['account', 'category', 'subcategory']) {
    for (final size in [const Size(320, 640), const Size(780, 360)]) {
      testWidgets(
          '$kind $size: tela cheia, texto ampliado e Salvar acessível com teclado',
          (tester) async {
        await open(tester, form(kind), size: size, scale: 2);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(BackButton), findsOneWidget);
        tester.view.viewInsets = const FakeViewPadding(bottom: 100);
        await tester.pumpAndSettle();
        expect(find.text(save(kind)).hitTestable(), findsOneWidget);
        final last = kind == 'account'
            ? find.text('Incluir em análises')
            : find.text('Cor');
        await tester.ensureVisible(last);
        await tester.pumpAndSettle();
        expect(last, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
    for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
      testWidgets(
          '$kind $platform: continuar preserva texto, descarte não grava',
          (tester) async {
        Object? result;
        await open(tester, form(kind),
            platform: platform,
            size: const Size(1280, 900),
            onResult: (value) => result = value);
        expect(find.byType(AlertDialog),
            platform == TargetPlatform.windows ? findsOneWidget : findsNothing);
        await tester.enterText(find.byType(TextFormField).first, 'Alterado');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Descartar alterações?'), findsOneWidget);
        await tester.tap(find.text('Continuar editando'));
        await tester.pumpAndSettle();
        expect(field(tester, 0).controller!.text, 'Alterado');
        await tester.tap(platform == TargetPlatform.android
            ? find.byType(BackButton)
            : find.text('Cancelar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Descartar'));
        await tester.pumpAndSettle();
        expect(find.byType(MovementFormFrame), findsNothing);
        expect(result, isNull);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('editar conta preserva tipo, moeda, saldo negativo e opções',
      (tester) async {
    Object? result;
    await open(tester, const AccountForm(account: account),
        onResult: (value) => result = value);
    await tester.enterText(find.byType(TextFormField).first, 'Novo nome');
    await tester.tap(find.text('Salvar conta'));
    await tester.pumpAndSettle();
    final draft = result as AccountDraft;
    expect(draft.name, 'Novo nome');
    expect(draft.type, account.type);
    expect(draft.currencyCode, 'USD');
    expect(draft.initialBalanceMinor, -12345);
    expect(draft.includeInBalance, false);
    expect(draft.includeInAnalytics, false);
  });
  testWidgets(
      'saldo inicial usa calculadora, permite negativo e zero; nome/moeda validam',
      (tester) async {
    Object? result;
    await open(tester, const AccountForm(),
        onResult: (value) => result = value);
    await tester.tap(find.text('Salvar conta'));
    await tester.pumpAndSettle();
    expect(find.text('Informe o nome.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'Banco');
    await tester.enterText(find.byType(TextFormField).at(1), 'XX');
    await tester.tap(find.text('Salvar conta'));
    await tester.pumpAndSettle();
    expect(find.text('Use três letras, como BRL.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), 'BRL');
    await tester.ensureVisible(find.byType(TextFormField).at(2));
    await tester.tap(find.byType(TextFormField).at(2));
    await tester.pumpAndSettle();
    for (final key in ['−', '1']) {
      await tester.tap(find.byKey(ValueKey('calculator-key-$key')));
    }
    await tester.tap(find.text('Confirmar valor'));
    await tester.pumpAndSettle();
    expect(field(tester, 2).controller!.text, '-1,00');
    await tester.tap(find.byType(TextFormField).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calculator-key-C')));
    await tester.tap(find.text('Confirmar valor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar conta'));
    await tester.pumpAndSettle();
    expect((result as AccountDraft).initialBalanceMinor, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('nova subcategoria recebe categoria e tipo pelo atalho',
      (tester) async {
    Object? result;
    await open(
        tester,
        const CategoryForm(
            categories: [parent, child],
            defaultType: CategoryType.income,
            parent: parent),
        onResult: (value) => result = value);
    expect(find.text('Nova subcategoria'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Outra filha');
    await tester.tap(find.text('Salvar categoria'));
    await tester.pumpAndSettle();
    expect((result as CategoryDraft).parentId, parent.id);
    expect((result as CategoryDraft).type, parent.type);
  });
  for (final item in [parent, child]) {
    testWidgets(
        'editar categoria ${item.id} preserva tipo, parent, ícone e cor',
        (tester) async {
      Object? result;
      await open(
          tester,
          CategoryForm(
              categories: const [parent, child],
              defaultType: CategoryType.income,
              category: item),
          platform: TargetPlatform.windows,
          size: const Size(1280, 900),
          onResult: (value) => result = value);
      await tester.enterText(find.byType(TextFormField).first, 'Renomeada');
      await tester.tap(find.text('Salvar categoria'));
      await tester.pumpAndSettle();
      final draft = result as CategoryDraft;
      expect(draft.name, 'Renomeada');
      expect(draft.type, item.type);
      expect(draft.parentId, item.parentId);
      expect(draft.iconKey, item.iconKey);
      expect(draft.colorArgb, item.colorArgb);
    });
  }
  for (final subcategory in [false, true]) {
    testWidgets(
        'criar categoria/subcategoria ($subcategory) mantém validação e vínculo',
        (tester) async {
      Object? result;
      const active = FinanceCategory(
          id: 'active',
          name: 'Alimentação',
          type: CategoryType.expense,
          parentId: null,
          isArchived: false,
          iconKey: 'food',
          colorArgb: 0xff388e3c);
      await open(
          tester,
          const CategoryForm(
              categories: [active], defaultType: CategoryType.expense),
          onResult: (value) => result = value);
      await tester.tap(find.text('Salvar categoria'));
      await tester.pumpAndSettle();
      expect(find.text('Informe o nome.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'Nova');
      if (subcategory) {
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Alimentação').last);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Salvar categoria'));
      await tester.pumpAndSettle();
      final draft = result as CategoryDraft;
      expect(draft.name, 'Nova');
      expect(draft.type, CategoryType.expense);
      expect(draft.parentId, subcategory ? 'active' : null);
      expect(tester.takeException(), isNull);
    });
  }
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('renderiza cadastros Android para revisão', (tester) async {
      final fonts = Directory(
          '${Platform.environment['FLUTTER_ROOT']!}/bin/cache/artifacts/material_fonts');
      final roboto = FontLoader('Roboto');
      for (final f in fonts.listSync().whereType<File>()) {
        if (f.path.endsWith('Roboto-Regular.ttf') ||
            f.path.endsWith('Roboto-Bold.ttf')) {
          roboto
              .addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
        }
      }
      await roboto.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(Future.value(ByteData.sublistView(
          File('${fonts.path}/MaterialIcons-Regular.otf').readAsBytesSync())));
      await icons.load();
      for (final kind in ['account', 'category']) {
        await open(tester, form(kind));
        await tester.enterText(find.byType(TextFormField).first,
            kind == 'account' ? 'Minha conta' : 'Alimentação');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await expectLater(find.byKey(const ValueKey('movement-full-screen')),
            matchesGoldenFile('$kind-mobile-preview.png'));
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Descartar'));
        await tester.pumpAndSettle();
      }
    });
  }
}
