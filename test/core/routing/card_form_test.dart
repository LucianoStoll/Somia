import 'dart:io';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/cards/presentation/card_forms.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transactions/presentation/transactions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'reference_form_test.dart' as forms;
import 'series_form_test.dart' as series;

const card = CreditCard(
    id: 'nu',
    name: 'Nubank',
    paymentAccountId: 'a',
    closingDay: 25,
    dueDay: 5,
    limitMinor: 500000,
    institutionId: 'nubank');
final invoice = CardInvoice(
    id: 'bill',
    cardId: 'nu',
    month: DateTime(2026, 10),
    closingAt: DateTime(2026, 9, 25),
    dueAt: DateTime(2026, 10, 5),
    previousMinor: 0,
    chargesMinor: 125050,
    paidMinor: 0,
    scheduledMinor: 0);
void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
        'cartão cria compra parcelada pelo formulário Despesas $platform',
        (tester) async {
      Object? result;
      await forms.open(
          tester,
          const TransactionForm(
              accounts: series.accounts,
              categories: [],
              cards: [card],
              fixedType: TransactionType.expense),
          platform: platform,
          size: platform == TargetPlatform.android
              ? const Size(390, 844)
              : const Size(1280, 900),
          onResult: (v) => result = v);
      await tester.enterText(find.byType(TextFormField).first, 'Compra cartão');
      forms.field(tester, 1).controller!.text = '100,01';
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await series.select(tester, 'series-kind', 'Parcelado');
      await series.select(tester, 'payment-method', 'Cartão');
      await tester.ensureVisible(find.byKey(const ValueKey('series-count')));
      await tester.enterText(find.byKey(const ValueKey('series-count')), '3');
      expect(find.byKey(const ValueKey('series-unit')), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.tap(find.text('Salvar lançamento'));
      await tester.pumpAndSettle();
      final draft = result as TransactionDraft;
      expect(draft.cardId, 'nu');
      expect(draft.isEffective, isFalse);
      expect(draft.seriesPlan!.count, 3);
      expect(draft.seriesPlan!.amounts(draft.amountMinor), [3334, 3334, 3333]);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        'cadastro valida dias e retorna dados; pagamento mantém débito e ajustes separados $platform',
        (tester) async {
      CardDraft? saved;
      await forms.open(
          tester,
          CardForm(
              accounts: series.accounts,
              month: DateTime(2026, 10),
              onSubmit: (draft, amount, month) async {
                saved = draft;
              }),
          platform: platform);
      await tester.enterText(find.byType(TextFormField).first, 'Meu cartão');
      final fields =
          tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
      fields[2].controller!.text = '32';
      await tester.tap(find.text('Salvar cartão'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('Informe de 1 a 31.'), findsOneWidget);
      fields[2].controller!.text = '25';
      await tester.tap(find.text('Salvar cartão'));
      await tester.pumpAndSettle();
      expect(saved!.name, 'Meu cartão');
      expect(saved!.closingDay, 25);
      (String, int, DateTime, int, int)? payment;
      await forms.open(
          tester,
          CardPaymentForm(
              invoice: invoice,
              card: card,
              accounts: series.accounts,
              onSubmit: (a, v, d, f, c) async {
                payment = (a, v, d, f, c);
              }),
          platform: platform);
      final paymentFields =
          tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
      paymentFields[0].controller!.text = '500,00';
      paymentFields[1].controller!.text = '10,00';
      paymentFields[2].controller!.text = '5,00';
      await tester.tap(find.text('Registrar pagamento'));
      await tester.pumpAndSettle();
      expect(payment!.$2, 50000);
      expect(payment!.$4, 1000);
      expect(payment!.$5, 500);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('pagamento erro mantém formulário e voltar confirma descarte',
      (tester) async {
    await forms.open(
        tester,
        CardPaymentForm(
            invoice: invoice,
            card: card,
            accounts: series.accounts,
            onSubmit: (a, v, d, f, c) async {
              throw StateError('Conta inativa.');
            }));
    forms.field(tester, 0).controller!.text = '500,00';
    await tester.tap(find.text('Registrar pagamento'));
    await tester.pumpAndSettle();
    expect(find.text('Conta inativa.'), findsOneWidget);
    expect(find.text('Registrar pagamento'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsOneWidget);
    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('prévia pagamento cartão Android', (tester) async {
      final fonts = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(File(
                '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf')
            .readAsBytesSync())));
      await fonts.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(File(
                '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
            .readAsBytesSync())));
      await icons.load();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.android),
          home: CardPaymentForm(
              invoice: invoice,
              card: card,
              accounts: series.accounts,
              onSubmit: (a, v, d, f, c) async {})));
      await tester.pumpAndSettle();
      await expectLater(find.byKey(const ValueKey('movement-full-screen')),
          matchesGoldenFile('card-payment-mobile-preview.png'));
      expect(tester.takeException(), isNull);
    });
  }
}
