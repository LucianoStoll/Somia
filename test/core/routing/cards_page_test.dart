import 'dart:io';
import 'package:drift/native.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/filters/reference_month.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/accounts/domain/accounts_repository.dart';
import 'package:finapp/features/categories/domain/categories_repository.dart';
import 'package:finapp/features/categories/domain/category.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/domain/credit_card.dart';
import 'package:finapp/features/cards/presentation/cards_page.dart';
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
      {double scale = 1}) async {
    tester.view.physicalSize = platform == TargetPlatform.android
        ? const Size(390, 844)
        : const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark.copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: const CardsPage()));
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
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
      expect(tester.takeException(), isNull);
    });
  }
}
