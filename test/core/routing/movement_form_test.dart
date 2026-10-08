import 'dart:io';

import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/widgets/movement_form_frame.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transactions/presentation/transactions_page.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:finapp/features/transfers/presentation/transfers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _accounts = [
  Account(
      id: 'a',
      name: 'Banco',
      type: AccountType.checking,
      currencyCode: 'BRL',
      initialBalanceMinor: 0,
      currentBalanceMinor: 0,
      projectedBalanceMinor: 0,
      isArchived: false,
      includeInAnalytics: true),
  Account(
      id: 'b',
      name: 'Reserva',
      type: AccountType.savings,
      currencyCode: 'BRL',
      initialBalanceMinor: 0,
      currentBalanceMinor: 0,
      projectedBalanceMinor: 0,
      isArchived: false,
      includeInAnalytics: true),
];

Future<void> _open(WidgetTester tester, Widget form,
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
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
        body: Builder(
            builder: (context) => TextButton(
                  onPressed: () async {
                    final result =
                        await showMovementForm<Object>(context, (_) => form);
                    onResult?.call(result);
                  },
                  child: const Text('Abrir'),
                ))),
  ));
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

TextField _input(WidgetTester tester, Finder field) => tester.widget<TextField>(
    find.descendant(of: field, matching: find.byType(TextField)));

void main() {
  for (final offset in [-7, 7]) {
    testWidgets('despesa paga usa vencimento como efetivação $offset',
        (tester) async {
      Object? result;
      final today = DateUtils.dateOnly(DateTime.now());
      final due = today.add(Duration(days: offset));
      await _open(
          tester,
          const TransactionForm(
              accounts: _accounts,
              categories: [],
              fixedType: TransactionType.expense),
          onResult: (value) => result = value);
      await tester.enterText(find.byType(TextFormField).first, 'Despesa teste');
      _input(tester, find.byType(TextFormField).at(1)).controller!.text =
          '100,00';
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.text('Data de efetivação'), findsNothing);
      expect(find.text('Lançamento'), findsNothing);
      await tester.ensureVisible(find.text('Vencimento'));
      await tester.tap(find.text('Vencimento'));
      await tester.pumpAndSettle();
      tester
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(due);
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Pago'));
      await tester.tap(find.text('Pago'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pago'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Mais opções'));
      await tester.tap(find.text('Mais opções'));
      await tester.pumpAndSettle();
      expect(find.text('Data de efetivação'), findsOneWidget);
      expect(find.text('Lançamento'), findsOneWidget);
      await tester.ensureVisible(find.text('Mais opções'));
      await tester.tap(find.text('Mais opções'));
      await tester.pumpAndSettle();
      expect(find.text('Lançamento'), findsNothing);
      await tester.tap(find.text('Salvar lançamento'));
      await tester.pumpAndSettle();
      final draft = result as TransactionDraft;
      expect(DateUtils.isSameDay(draft.date, today), true);
      expect(DateUtils.isSameDay(draft.dueDate, due), true);
      expect(DateUtils.isSameDay(draft.effectiveDate, due), true);
      expect(draft.isEffective, true);
      expect(tester.takeException(), isNull);
    });
  }
  for (final type in ['receita', 'despesa', 'transferência']) {
    testWidgets('$type: descrição, próximo, valor e salvar no Android',
        (tester) async {
      Object? result;
      final form = type == 'transferência'
          ? const TransferForm(accounts: _accounts)
          : TransactionForm(
              accounts: _accounts,
              categories: const [],
              fixedType: type == 'receita'
                  ? TransactionType.income
                  : TransactionType.expense,
              initialType: type == 'receita'
                  ? TransactionType.income
                  : TransactionType.expense);
      await _open(tester, form, onResult: (value) => result = value);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Nova $type'), findsOneWidget);
      final description = find.byType(TextFormField).at(0);
      final amount = find.byType(TextFormField).at(1);
      expect(_input(tester, description).focusNode!.hasFocus, true);
      expect(tester.testTextInput.isVisible, true);
      expect(tester.getTopLeft(description).dy,
          lessThan(tester.getTopLeft(amount).dy));
      await tester.enterText(description, 'Teste $type');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('Calculadora'), findsOneWidget);
      expect(tester.testTextInput.isVisible, false);
      expect(_input(tester, amount).readOnly, true);
      for (final key in ['1', '2', '3', ',', '4', '5']) {
        await tester.tap(find.byKey(ValueKey('calculator-key-$key')));
      }
      await tester.tap(find.text('Confirmar valor'));
      await tester.pumpAndSettle();
      expect(_input(tester, amount).controller!.text, '123,45');
      final save = find.text('Salvar lançamento');
      expect(save.hitTestable(), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      if (result is TransferDraft) {
        expect((result as TransferDraft).description, 'Teste $type');
        expect((result as TransferDraft).amountMinor, 12345);
        expect((result as TransferDraft).sourceAccountId, 'a');
        expect((result as TransferDraft).destinationAccountId, 'b');
      } else {
        expect(result, isA<TransactionDraft>());
        expect((result as TransactionDraft).description, 'Teste $type');
        expect((result as TransactionDraft).amountMinor, 12345);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final kind in ['expense', 'transfer']) {
    testWidgets('formulário $kind prioriza essenciais e usa linhas simples',
        (tester) async {
      await _open(
          tester,
          kind == 'transfer'
              ? const TransferForm(accounts: _accounts)
              : const TransactionForm(
                  accounts: _accounts,
                  categories: [],
                  fixedType: TransactionType.expense));
      final inputContext = tester.element(find.byType(TextFormField).first);
      expect(Theme.of(inputContext).inputDecorationTheme.filled, false);
      expect(Theme.of(inputContext).inputDecorationTheme.border,
          isA<UnderlineInputBorder>());
      expect(tester.getTopLeft(find.text('Vencimento')).dy,
          lessThan(tester.getTopLeft(find.text('Mais opções')).dy));
      expect(
          tester
              .getTopLeft(
                  find.text(kind == 'transfer' ? 'Conta de origem' : 'Conta'))
              .dy,
          lessThan(tester.getTopLeft(find.text('Vencimento')).dy));
      expect(tester.takeException(), isNull);
    });
  }
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final kind in ['income', 'expense', 'transfer']) {
      testWidgets(
          '$kind $platform: Voltar protege alterações e Cancelar preserva campos',
          (tester) async {
        final form = kind == 'transfer'
            ? const TransferForm(accounts: _accounts)
            : TransactionForm(
                accounts: _accounts,
                categories: const [],
                initialType: kind == 'income'
                    ? TransactionType.income
                    : TransactionType.expense);
        Object? result;
        await _open(tester, form,
            platform: platform,
            size: const Size(1280, 900),
            onResult: (value) => result = value);
        await tester.enterText(find.byType(TextFormField).first, 'Alteração');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Descartar alterações?'), findsOneWidget);
        await tester.tap(find.text('Continuar editando'));
        await tester.pumpAndSettle();
        expect(find.text('Alteração'), findsOneWidget);
        if (platform == TargetPlatform.android) {
          await tester.tap(find.byType(BackButton));
        } else {
          await tester.tap(find.text('Cancelar'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Descartar alterações?'), findsOneWidget);
        await tester.tap(find.text('Descartar'));
        await tester.pumpAndSettle();
        expect(find.byType(MovementFormFrame), findsNothing);
        expect(result, isNull);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'Android: calculadora e data fecham antes do formulário; alterações revertidas não pedem descarte',
      (tester) async {
    await _open(
        tester, const TransactionForm(accounts: _accounts, categories: []));
    await tester.enterText(find.byType(TextFormField).first, 'Teste');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(find.text('Calculadora'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Calculadora'), findsNothing);
    expect(find.text('Descartar alterações?'), findsNothing);
    expect(find.byType(MovementFormFrame), findsOneWidget);
    await tester.ensureVisible(find.text('Vencimento'));
    await tester.tap(find
        .ancestor(of: find.text('Vencimento'), matching: find.byType(InkWell))
        .first);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('Descartar alterações?'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MovementFormFrame), findsNothing);
    expect(find.text('Descartar alterações?'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Android: mudar apenas efetivação também exige confirmação, Voltar na confirmação mantém formulário',
      (tester) async {
    await _open(tester, const TransferForm(accounts: _accounts));
    await tester.ensureVisible(find.text('Efetivada'));
    await tester.tap(find.text('Efetivada'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsNothing);
    expect(find.byType(MovementFormFrame), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 640), const Size(780, 360)]) {
    testWidgets('formulário em $size com texto ampliado e teclado',
        (tester) async {
      await _open(
          tester, const TransactionForm(accounts: _accounts, categories: []),
          size: size, scale: 2);
      tester.view.viewInsets = const FakeViewPadding(bottom: 100);
      await tester.pumpAndSettle();
      expect(find.text('Salvar lançamento').hitTestable(), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Mais detalhes'), 250,
          scrollable: find
              .ancestor(
                  of: find.text('Mais detalhes'),
                  matching: find.byType(Scrollable))
              .first);
      await tester.tap(find.text('Mais detalhes'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Windows mantém janela central e edição preserva valores',
      (tester) async {
    Object? result;
    final date = DateTime(2026, 1, 23);
    await _open(
        tester,
        TransferForm(
            accounts: _accounts,
            item: Transfer(
                id: 't',
                description: 'Aplicação',
                sourceAccountId: 'a',
                sourceAccountName: 'Banco',
                destinationAccountId: 'b',
                destinationAccountName: 'Reserva',
                currencyCode: 'BRL',
                amountMinor: 45000,
                date: date,
                dueDate: date,
                effectiveDate: date,
                isEffective: true)),
        platform: TargetPlatform.windows,
        size: const Size(1280, 900),
        onResult: (value) => result = value);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('movement-full-screen')), findsNothing);
    expect(find.text('Editar transferência'), findsOneWidget);
    expect(_input(tester, find.byType(TextFormField).first).focusNode!.hasFocus,
        false);
    await tester.tap(find.text('Salvar lançamento'));
    await tester.pumpAndSettle();
    final draft = result as TransferDraft;
    expect(draft.description, 'Aplicação');
    expect(draft.amountMinor, 45000);
    expect(draft.date, date);
    expect(draft.dueDate, date);
    expect(draft.effectiveDate, date);
  });

  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('renderiza formulário Android para revisão', (tester) async {
      final root = Platform.environment['FLUTTER_ROOT']!;
      final fonts = Directory('$root/bin/cache/artifacts/material_fonts');
      final loader = FontLoader('Roboto');
      for (final file in fonts.listSync().whereType<File>()) {
        if (file.path.endsWith('Roboto-Regular.ttf') ||
            file.path.endsWith('Roboto-Bold.ttf')) {
          loader.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(Future.value(ByteData.sublistView(File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytesSync())));
      await icons.load();
      await _open(
          tester,
          const TransactionForm(
              accounts: _accounts,
              categories: [],
              fixedType: TransactionType.expense));
      await tester.enterText(find.byType(TextFormField).first, 'Supermercado');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      for (final key in ['3', '2', '0', ',', '5', '0']) {
        await tester.tap(find.byKey(ValueKey('calculator-key-$key')));
      }
      await tester.tap(find.text('Confirmar valor'));
      await tester.pumpAndSettle();
      await expectLater(find.byKey(const ValueKey('movement-full-screen')),
          matchesGoldenFile('movement-mobile-preview.png'));
    });
  }
}
