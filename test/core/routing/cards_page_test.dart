import 'package:go_router/go_router.dart';
import 'package:finapp/core/routing/somia_shell.dart';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/filters/reference_month.dart';
import 'package:finapp/core/series/movement_series.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/accounts/domain/accounts_repository.dart';
import 'package:finapp/features/categories/domain/categories_repository.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/cards/presentation/cards_page.dart';
import 'package:finapp/features/cards/presentation/card_forms.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'series_form_test.dart' as series;
import 'reference_form_test.dart' as reference;

class _Accounts extends Fake implements AccountsRepository {
  @override
  Future<List<Account>> list({DateTime? asOf, DateTime? through}) async =>
      series.accounts;
}

class _Categories extends Fake implements CategoriesRepository {
  @override
  Future<List<FinanceCategory>> list() async => [];
}

class _Cards extends CardsRepository {
  _Cards() : super(AppDatabase(NativeDatabase.memory()));
  (String, String, int, DateTime, int, int)? payment;
  TransactionDraft? edited;
  String? deleted;
  @override
  Future<bool> purchaseHasPayments(String id, SeriesScope scope,
          {DateTime? invoiceMonth, DateTime? purchaseDate}) async =>
      true;
  @override
  Future<void> editPurchase(String id, TransactionDraft draft) async {
    edited = draft;
  }

  @override
  Future<void> deletePurchase(String id, SeriesScope scope) async {
    deleted = id;
  }

  @override
  Future<List<CreditCard>> list() async => [
        const CreditCard(
            id: 'nu',
            name: 'Nubank',
            paymentAccountId: 'a',
            closingDay: 25,
            dueDay: 5,
            limitMinor: 500000,
            institutionId: 'nubank',
            committedMinor: 85050)
      ];
  @override
  Future<List<CardInvoice>> invoices(String cardId,
          {DateTime? selected}) async =>
      [
        CardInvoice(
            id: 'bill',
            cardId: 'nu',
            month: DateTime(2026, 10),
            closingAt: DateTime(2026, 9, 25),
            dueAt: DateTime(2026, 10, 5),
            previousMinor: 0,
            chargesMinor: 125050,
            paidMinor: 40000,
            scheduledMinor: 0,
            entries: [
              CardEntry(
                  id: 'buy',
                  cardId: 'nu',
                  invoiceId: 'bill',
                  purchaseId: 'purchase',
                  index: 1,
                  count: 3,
                  description: 'Compra parcelada com descrição longa',
                  kind: 'purchase',
                  amountMinor: 125050,
                  postedAt: DateTime(2026, 9, 1),
                  dueAt: DateTime(2026, 10, 5),
                  invoiceMonth: DateTime(2026, 10),
                  categoryName: 'Alimentação')
            ],
            payments: [
              CardPayment(
                  id: 'payment',
                  amountMinor: 40000,
                  date: DateTime(2026, 10, 2),
                  accountName: 'Banco')
            ]),
        CardInvoice(
            id: 'next',
            cardId: 'nu',
            month: DateTime(2026, 11),
            closingAt: DateTime(2026, 10, 25),
            dueAt: DateTime(2026, 11, 5),
            previousMinor: 85050,
            chargesMinor: 0,
            paidMinor: 0,
            scheduledMinor: 0),
      ];
  @override
  Future<void> pay(
      String invoiceId, String accountId, int amount, DateTime date,
      {int fee = 0, int discount = 0}) async {
    payment = (invoiceId, accountId, amount, date, fee, discount);
  }
}

void main() {
  late _Cards repo;
  setUp(() async {
    await getIt.reset();
    repo = _Cards();
    getIt.registerSingleton<CardsRepository>(repo);
    getIt.registerSingleton<AccountsRepository>(_Accounts());
    getIt.registerSingleton<CategoriesRepository>(_Categories());
    referenceMonth.select(DateTime(2026, 10));
  });
  tearDown(() async {
    await getIt.reset();
    await repo.db.close();
  });
  Future<void> open(WidgetTester tester, TargetPlatform platform,
      {double scale = 1, bool detail = true}) async {
    tester.view.physicalSize = platform == TargetPlatform.android
        ? const Size(390, 844)
        : const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
        initialLocation: detail ? '/cards?card=nu' : '/cards',
        routes: [
          GoRoute(
              path: '/cards',
              builder: (context, state) => SomiaSectionBackScope(
                  location: '/cards',
                  child: CardsPage(
                      key: ValueKey(state.uri.toString()),
                      cardId: state.uri.queryParameters['card']))),
          for (final path in ['/income', '/expenses', '/transfers'])
            GoRoute(
                path: path,
                builder: (_, state) =>
                    Scaffold(body: Text(state.uri.toString())))
        ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.dark.copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
    ));
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('próxima fatura mostra mês sem acumular anterior $platform',
        (tester) async {
      await open(tester, platform);
      await tester.scrollUntilVisible(find.text('11/2026'), 200);
      await tester.pumpAndSettle();
      final tile = tester.widget<ListTile>(find.ancestor(
          of: find.text('11/2026'), matching: find.byType(ListTile)));
      expect((tile.trailing! as Text).data, cardMoney(0));
      expect((tile.subtitle! as Text).data, contains(cardMoney(85050)));
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        'corrigir compra paga pede confirmação e cancelar preserva dados $platform',
        (tester) async {
      await open(tester, platform);
      Future<void> edit() async {
        final title = find.text('Compra parcelada com descrição longa');
        await tester.scrollUntilVisible(title, 200);
        await tester.pumpAndSettle();
        final tile =
            find.ancestor(of: title, matching: find.byType(ListTile)).first;
        final menu = find.descendant(
            of: tile, matching: find.byType(PopupMenuButton<String>));
        await tester.ensureVisible(menu);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Editar / mudar fatura'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Somente esta'));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byType(TextFormField).first, 'Compra corrigida');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Salvar lançamento'));
        await tester.pumpAndSettle();
        expect(find.text('Corrigir compra em fatura com pagamento?'),
            findsOneWidget);
      }

      await edit();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.edited, isNull);
      await edit();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(repo.edited!.description, 'Compra corrigida');
      expect(repo.edited!.cardId, 'nu');
      expect(repo.payment, isNull);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        'fatura e caixa distinguem datas; pagamento vinculado $platform',
        (tester) async {
      await open(tester, platform);
      expect(find.text('Nubank · 10/2026'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.text('Compra parcelada com descrição longa'), 200);
      await tester.pumpAndSettle();
      expect(find.text('Compra parcelada com descrição longa'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Caixa / pagamentos'), -200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caixa / pagamentos'));
      await tester.pumpAndSettle();
      expect(find.text('Pago no mês'), findsOneWidget);
      await tester.tap(find.text('Competência / fatura'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Pagar fatura'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pagar fatura'));
      await tester.pumpAndSettle();
      reference.field(tester, 0).controller!.text = '500,00';
      await tester.tap(find.text('Registrar pagamento'));
      await tester.pumpAndSettle();
      expect(repo.payment!.$1, 'bill');
      expect(repo.payment!.$3, 50000);
      expect(tester.takeException(), isNull);
    });
  }
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('lista abre detalhes e extrato agrupa dias $platform',
        (tester) async {
      await open(tester, platform, detail: false);
      expect(find.text('Detalhes do cartão'), findsNothing);
      expect(find.text('Compra parcelada com descrição longa'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('card-open-nu')));
      await tester.pumpAndSettle();
      expect(find.text('Detalhes do cartão'), findsOneWidget);
      await tester.ensureVisible(find.text('Extrato'));
      await tester.tap(find.text('Extrato'));
      await tester.pumpAndSettle();
      final purchaseDay = find.byKey(
          ValueKey('card-statement-day-${cardDay(DateTime(2026, 9, 1))}'));
      final paymentDay = find.byKey(
          ValueKey('card-statement-day-${cardDay(DateTime(2026, 10, 2))}'));
      await tester.scrollUntilVisible(purchaseDay, 160);
      expect(purchaseDay, findsOneWidget);
      expect(paymentDay, findsOneWidget);
      expect(tester.getTopLeft(paymentDay).dy,
          lessThan(tester.getTopLeft(purchaseDay).dy));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('card-open-nu')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('balão na aba Cartões abre os três fluxos $platform',
        (tester) async {
      for (final action in [
        ('Receita', '/income?create=1'),
        ('Despesa', '/expenses?create=1'),
        ('Transferência', '/transfers?create=1')
      ]) {
        await open(tester, platform, detail: false);
        await tester
            .tap(find.byTooltip('Adicionar lançamento ou transferência'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action.$1));
        await tester.pumpAndSettle();
        expect(find.text(action.$2), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('Voltar Android do detalhe retorna aos cartões', (tester) async {
    await open(tester, TargetPlatform.android);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('card-open-nu')), findsOneWidget);
    expect(find.text('Detalhes do cartão'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cartões tolera fonte ampliada no Android', (tester) async {
    await open(tester, TargetPlatform.android, scale: 1.5);
    expect(tester.takeException(), isNull);
  });
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('prévia fatura cartões Android', (tester) async {
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
      await open(tester, TargetPlatform.android);
      await expectLater(find.byType(Scaffold).last,
          matchesGoldenFile('cards-mobile-preview.png'));
      await tester.ensureVisible(find.text('Extrato'));
      await tester.tap(find.text('Extrato'));
      await tester.pumpAndSettle();
      await expectLater(find.byType(Scaffold).last,
          matchesGoldenFile('card-statement-mobile-preview.png'));
      await open(tester, TargetPlatform.android, detail: false);
      await expectLater(find.byType(Scaffold).last,
          matchesGoldenFile('card-list-mobile-preview.png'));
      await open(tester, TargetPlatform.windows);
      await expectLater(find.byType(Scaffold).last,
          matchesGoldenFile('cards-desktop-preview.png'));
      expect(tester.takeException(), isNull);
    });
  }
}
