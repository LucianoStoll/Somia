import 'dart:io';
import 'package:finapp/core/series/movement_series.dart';
import 'package:finapp/core/series/series_form.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transactions/presentation/transactions_page.dart';
import 'package:finapp/features/transfers/domain/transfer.dart';
import 'package:finapp/features/transfers/presentation/transfers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'reference_form_test.dart' as forms;

const accounts = [
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
      includeInAnalytics: true)
];

Widget form(String kind) => kind == 'transfer'
    ? const TransferForm(accounts: accounts)
    : TransactionForm(
        accounts: accounts,
        categories: const [],
        initialType: kind == 'income'
            ? TransactionType.income
            : TransactionType.expense);

Future<void> select(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty &&
      find
          .byKey(const ValueKey('transaction-more-options'))
          .evaluate()
          .isNotEmpty) {
    await tester.ensureVisible(find.text('Mais opções'));
    await tester.tap(find.text('Mais opções'));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final kind in ['income', 'expense', 'transfer']) {
      testWidgets(
          '$kind cria parcelado nos dois modos e força pendente $platform',
          (tester) async {
        Object? result;
        await forms.open(tester, form(kind),
            platform: platform,
            size: platform == TargetPlatform.android
                ? const Size(390, 844)
                : const Size(1280, 900),
            onResult: (value) => result = value);
        await tester.enterText(find.byType(TextFormField).first, 'Série teste');
        forms.field(tester, 1).controller!.text = '100,01';
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await select(tester, 'series-kind', 'Parcelado');
        await tester.ensureVisible(find.byKey(const ValueKey('series-count')));
        await tester.enterText(find.byKey(const ValueKey('series-count')), '3');
        await tester
            .ensureVisible(find.byKey(const ValueKey('series-amount-mode')));
        await select(tester, 'series-amount-mode', 'Valor por parcela');
        await select(tester, 'series-amount-mode', 'Valor total');
        await tester.ensureVisible(find.byKey(const ValueKey('series-unit')));
        await select(tester, 'series-unit', 'Semanal');
        await tester
            .ensureVisible(find.byKey(const ValueKey('series-interval')));
        await tester.enterText(
            find.byKey(const ValueKey('series-interval')), '2');
        expect(
            tester
                .widget<SwitchListTile>(find.widgetWithText(
                    SwitchListTile,
                    kind == 'income'
                        ? 'Recebido'
                        : kind == 'expense'
                            ? 'Pago'
                            : 'Efetivada'))
                .value,
            isFalse);
        expect(
            tester
                .widget<SwitchListTile>(find.widgetWithText(
                    SwitchListTile,
                    kind == 'income'
                        ? 'Recebido'
                        : kind == 'expense'
                            ? 'Pago'
                            : 'Efetivada'))
                .onChanged,
            isNull);
        await tester.tap(find.text('Salvar lançamento'));
        await tester.pumpAndSettle();
        final plan = result is TransactionDraft
            ? (result as TransactionDraft).seriesPlan!
            : (result as TransferDraft).seriesPlan!;
        expect(plan.kind, SeriesKind.installments);
        expect(plan.count, 3);
        expect(plan.unit, SeriesUnit.week);
        expect(plan.interval, 2);
        expect(plan.amountIsTotal, true);
        expect(
            result is TransactionDraft
                ? (result as TransactionDraft).isEffective
                : (result as TransferDraft).isEffective,
            false);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'quantidade e intervalo inválidos mantêm formulário; cancelar descarte conserva série',
      (tester) async {
    await forms.open(tester, form('expense'));
    await select(tester, 'series-kind', 'Recorrente');
    await tester.ensureVisible(find.byKey(const ValueKey('series-count')));
    await tester.enterText(find.byKey(const ValueKey('series-count')), '0');
    await tester.tap(find.text('Salvar lançamento'));
    await tester.pumpAndSettle();
    expect(find.text('Informe de 2 a 1000.'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsOneWidget);
    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(find.text('Recorrente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('escopo oferece isolado e próximos com cancelamento',
      (tester) async {
    SeriesScope? result;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      result = await chooseSeriesScope(context, deleting: true);
                    },
                    child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esta e as próximas'));
    await tester.pumpAndSettle();
    expect(result, SeriesScope.thisAndNext);
  });
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('renderiza formulário parcelado Android', (tester) async {
      final fonts = Directory(
          '${Platform.environment['FLUTTER_ROOT']!}/bin/cache/artifacts/material_fonts');
      for (final (family, file) in [
        ('Roboto', 'Roboto-Regular.ttf'),
        ('MaterialIcons', 'MaterialIcons-Regular.otf')
      ]) {
        final loader = FontLoader(family);
        loader.addFont(Future.value(ByteData.sublistView(
            File('${fonts.path}/$file').readAsBytesSync())));
        await loader.load();
      }
      await forms.open(tester, form('expense'));
      await tester.enterText(
          find.byType(TextFormField).first, 'Compra parcelada');
      forms.field(tester, 1).controller!.text = '1000,00';
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await select(tester, 'series-kind', 'Parcelado');
      await tester.ensureVisible(find.byKey(const ValueKey('series-count')));
      await tester.enterText(find.byKey(const ValueKey('series-count')), '3');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const ValueKey('series-amount-mode')));
      await tester.pumpAndSettle();
      await expectLater(find.byKey(const ValueKey('movement-full-screen')),
          matchesGoldenFile('series-mobile-preview.png'));
    });
  }
}
