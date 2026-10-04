import 'dart:async';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/transactions/data/category_history_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transactions/presentation/transactions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'reference_form_test.dart' as forms;
import 'series_form_test.dart' as series;

const categories = [
  FinanceCategory(
      id: 'food',
      name: 'Alimentação',
      type: CategoryType.expense,
      parentId: null,
      isArchived: false,
      iconKey: null,
      colorArgb: null),
  FinanceCategory(
      id: 'dinner',
      name: 'Jantar fora',
      type: CategoryType.expense,
      parentId: 'food',
      isArchived: false,
      iconKey: null,
      colorArgb: null),
  FinanceCategory(
      id: 'lunch',
      name: 'Almoço fora',
      type: CategoryType.expense,
      parentId: 'food',
      isArchived: false,
      iconKey: null,
      colorArgb: null),
  FinanceCategory(
      id: 'pay',
      name: 'Salário',
      type: CategoryType.income,
      parentId: null,
      isArchived: false,
      iconKey: null,
      colorArgb: null),
];

class History implements CategoryHistoryRepository {
  Future<Map<String, String>>? delayed;
  List<HistorySuggestion> options = [];
  @override
  Future<List<HistorySuggestion>> suggestions(TransactionType type) async =>
      options;
  final types = <TransactionType>[];
  @override
  Future<Map<String, String>> load(TransactionType type) {
    types.add(type);
    return delayed ??
        Future.value(type == TransactionType.expense
            ? {'jantar': 'dinner', 'almoço': 'lunch'}
            : {'jantar': 'pay'});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late History history;
  setUp(() async {
    await getIt.reset();
    history = History();
    getIt.registerSingleton<CategoryHistoryRepository>(history);
  });
  tearDown(() => getIt.reset());
  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextFormField).first, text);
    await tester.pumpAndSettle();
  }

  String? value(WidgetTester tester, String key) =>
      tester.state<FormFieldState<String>>(find.byKey(ValueKey(key))).value;
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
        'sugere pai/filha, troca filha e limpa descrição desconhecida $platform',
        (tester) async {
      await forms.open(
          tester,
          const TransactionForm(
              accounts: series.accounts,
              categories: categories,
              fixedType: TransactionType.expense),
          platform: platform);
      await type(tester, '  JANTAR  ');
      expect(value(tester, 'category-expense-food'), 'food');
      expect(value(tester, 'subcategory-expense-food-dinner'), 'dinner');
      expect(find.text('Categoria preenchida pelo histórico.'), findsOneWidget);
      await type(tester, 'Almoço');
      expect(value(tester, 'subcategory-expense-food-lunch'), 'lunch');
      await type(tester, 'Novo');
      expect(value(tester, 'category-expense-null'), isNull);
      expect(find.text('Categoria preenchida pelo histórico.'), findsNothing);
    });
  }
  testWidgets(
      'escolha manual Sem categoria vence a próxima descrição e resposta atrasada',
      (tester) async {
    final completer = Completer<Map<String, String>>();
    history.delayed = completer.future;
    await forms.open(
        tester,
        const TransactionForm(
            accounts: series.accounts,
            categories: categories,
            fixedType: TransactionType.expense));
    await type(tester, 'Jantar');
    await series.select(tester, 'category-expense-null', 'Sem categoria');
    completer.complete({'jantar': 'dinner', 'almoço': 'lunch'});
    await tester.pumpAndSettle();
    await type(tester, 'Almoço');
    expect(value(tester, 'category-expense-null'), anyOf(isNull, ''));
    expect(find.text('Categoria preenchida pelo histórico.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('receita usa apenas classificação de receita', (tester) async {
    await forms.open(
        tester,
        const TransactionForm(
            accounts: series.accounts,
            categories: categories,
            fixedType: TransactionType.income,
            initialType: TransactionType.income));
    await type(tester, 'Jantar');
    expect(value(tester, 'category-income-pay'), 'pay');
    expect(history.types, [TransactionType.income]);
  });
  testWidgets('editar preserva categoria e não consulta histórico',
      (tester) async {
    final item = FinancialTransaction(
        id: 'a',
        description: 'Antes',
        type: TransactionType.expense,
        amountMinor: 1000,
        date: DateTime.now(),
        isEffective: false,
        accountId: 'a',
        accountName: 'Banco',
        categoryId: 'lunch',
        categoryName: 'Almoço fora',
        currencyCode: 'BRL');
    await forms.open(
        tester,
        TransactionForm(
            accounts: series.accounts, categories: categories, item: item));
    await type(tester, 'Jantar');
    expect(value(tester, 'subcategory-expense-food-lunch'), 'lunch');
    expect(history.types, isEmpty);
  });
  testWidgets('sugestão salva subcategoria sem mudar os demais campos',
      (tester) async {
    Object? saved;
    await forms.open(
        tester,
        const TransactionForm(
            accounts: series.accounts,
            categories: categories,
            fixedType: TransactionType.expense),
        onResult: (draft) => saved = draft);
    await type(tester, 'Jantar');
    forms.field(tester, 1).controller!.text = '15,00';
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar lançamento'));
    await tester.pumpAndSettle();
    final draft = saved as TransactionDraft;
    expect(draft.categoryId, 'dinner');
    expect(draft.amountMinor, 1500);
    expect(draft.accountId, 'a');
    expect(draft.isEffective, true);
  });
  testWidgets(
      'busca parcial lista e selecionar preenche conta, valor e categoria',
      (tester) async {
    history.options = [
      const HistorySuggestion(
          id: 'old',
          description: 'Rendimento CDI',
          accountId: 'b',
          accountName: 'Reserva',
          amountMinor: 25,
          currencyCode: 'BRL',
          categoryId: 'pay')
    ];
    Object? saved;
    await forms.open(
        tester,
        const TransactionForm(
            accounts: series.accounts,
            categories: categories,
            fixedType: TransactionType.income,
            initialType: TransactionType.income),
        onResult: (v) => saved = v);
    await type(tester, 'Ren');
    expect(find.text('Rendimento CDI'), findsOneWidget);
    expect(find.text('Reserva'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('history-suggestion-old')));
    await tester.pumpAndSettle();
    expect(forms.field(tester, 0).controller!.text, 'Rendimento CDI');
    expect(forms.field(tester, 1).controller!.text, '0,25');
    expect(value(tester, 'account-choice-b'), 'b');
    expect(value(tester, 'category-income-pay'), 'pay');
    expect(find.byKey(const ValueKey('history-suggestion-old')), findsNothing);
    await tester.tap(find.text('Salvar lançamento'));
    await tester.pumpAndSettle();
    final draft = saved as TransactionDraft;
    expect(draft.accountId, 'b');
    expect(draft.amountMinor, 25);
    expect(draft.categoryId, 'pay');
    expect(draft.isEffective, true);
  });
  testWidgets('ocultar sugestão não altera formulário nem histórico',
      (tester) async {
    history.options = [
      const HistorySuggestion(
          id: 'old',
          description: 'Rendimento CDI',
          accountId: 'a',
          accountName: 'Banco',
          amountMinor: 25,
          currencyCode: 'BRL')
    ];
    await forms.open(
        tester,
        const TransactionForm(
            accounts: series.accounts, categories: categories));
    await type(tester, 'Ren');
    await tester.tap(find.byTooltip('Ocultar sugestão'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-suggestion-old')), findsNothing);
    expect(forms.field(tester, 0).controller!.text, 'Ren');
    expect(history.options, hasLength(1));
  });
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('renderiza sugestões de histórico mobile', (tester) async {
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
      history.options = [
        const HistorySuggestion(
            id: 'one',
            description: 'Rendimento CDI',
            accountId: 'a',
            accountName: 'Banco',
            amountMinor: 25,
            currencyCode: 'BRL',
            categoryId: 'pay'),
        const HistorySuggestion(
            id: 'two',
            description: 'Rendimento C/C',
            accountId: 'b',
            accountName: 'Reserva',
            amountMinor: 1,
            currencyCode: 'BRL',
            categoryId: 'pay'),
      ];
      await forms.open(
          tester,
          const RepaintBoundary(
              key: ValueKey('suggestion-preview'),
              child: TransactionForm(
                  accounts: series.accounts,
                  categories: categories,
                  fixedType: TransactionType.income,
                  initialType: TransactionType.income)));
      await type(tester, 'Ren');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await expectLater(find.byKey(const ValueKey('suggestion-preview')),
          matchesGoldenFile('category-suggestions-mobile-preview.png'));
    });
  }
  testWidgets(
      'escolher compra muda seletor para cartão e mantém nova compra pendente',
      (tester) async {
    history.options = [
      const HistorySuggestion(
          id: 'card-old',
          description: 'Lanchonete',
          accountId: 'b',
          accountName: 'Cartão Nu',
          cardId: 'nu',
          amountMinor: 500,
          currencyCode: 'BRL',
          categoryId: 'dinner')
    ];
    Object? saved;
    await forms.open(
        tester,
        const TransactionForm(
            accounts: series.accounts,
            categories: categories,
            fixedType: TransactionType.expense,
            cards: [
              CreditCard(
                  id: 'nu',
                  name: 'Nu',
                  paymentAccountId: 'b',
                  closingDay: 25,
                  dueDay: 5)
            ]),
        onResult: (v) => saved = v);
    await type(tester, 'Lan');
    await tester.tap(find.byKey(const ValueKey('history-suggestion-card-old')));
    await tester.pumpAndSettle();
    expect(
        tester
            .state<FormFieldState<bool>>(
                find.byKey(const ValueKey('payment-method')))
            .value,
        true);
    expect(value(tester, 'card-choice-nu'), 'nu');
    expect(value(tester, 'subcategory-expense-food-dinner'), 'dinner');
    await tester.tap(find.text('Salvar lançamento'));
    await tester.pumpAndSettle();
    final draft = saved as TransactionDraft;
    expect(draft.cardId, 'nu');
    expect(draft.amountMinor, 500);
    expect(draft.isEffective, false);
    expect(draft.cardInvoiceMonth, isNull);
  });
}
