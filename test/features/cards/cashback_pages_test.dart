import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/database/app_database.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/widgets/monetary_calculator.dart';
import 'package:finapp/features/accounts/data/sqlite_accounts_repository.dart';
import 'package:finapp/features/accounts/domain/accounts_repository.dart';
import 'package:finapp/features/categories/data/sqlite_categories_repository.dart';
import 'package:finapp/features/categories/domain/categories_repository.dart';
import 'package:finapp/features/cards/data/cards_repository.dart';
import 'package:finapp/features/cards/data/debit_cards_repository.dart';
import 'package:finapp/features/cards/data/cashback_repository.dart';
import 'package:finapp/features/cards/domain/cashback_calculator.dart';
import 'package:finapp/features/cards/presentation/cashback_page.dart';
import 'package:finapp/features/cards/presentation/debit_cards_page.dart';
import 'package:finapp/features/transactions/data/sqlite_transactions_repository.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';

void main() {
  late AppDatabase db;
  late CashbackRepository cashback;
  late DebitCardsRepository debit;
  late String cardId;
  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement(
        "INSERT INTO accounts(id,name,type,currency_code,initial_balance_minor,created_at,updated_at) VALUES('a','Conta corrente','checking','BRL',1000000,1,1),('b','Recebimento cashback','checking','BRL',0,1,1)");
    await db.customStatement(
        "INSERT INTO categories(id,name,type,created_at,updated_at) VALUES('income','Cashback','income',1,1),('expense','Devolução','expense',1,1)");
    debit = DebitCardsRepository(db);
    cashback = CashbackRepository(db);
    cardId = await debit.save(name: 'Binance Débito', accountId: 'a');
    await cashback.saveSettings(
        kind: 'debit',
        cardId: cardId,
        enabled: true,
        accountId: 'b',
        categoryId: 'income',
        returnCategoryId: 'expense',
        rule: CashbackRule(rateBasisPoints: 100));
    await SqliteTransactionsRepository(db).create(TransactionDraft(
        description: 'Compra no débito',
        type: TransactionType.expense,
        amountMinor: 100000,
        date: DateTime.now(),
        isEffective: true,
        accountId: 'a',
        debitCardId: cardId));
    getIt.registerSingleton<CardsRepository>(CardsRepository(db));
    getIt.registerSingleton<DebitCardsRepository>(debit);
    getIt.registerSingleton<CashbackRepository>(cashback);
    getIt.registerSingleton<AccountsRepository>(SqliteAccountsRepository(db));
    getIt.registerSingleton<CategoriesRepository>(
        SqliteCategoriesRepository(db));
  });
  tearDown(() async {
    await getIt.reset();
    await db.close();
  });
  Future<void> open(WidgetTester t, TargetPlatform platform, Widget page,
      {double scale = 1}) async {
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    t.view.physicalSize = platform == TargetPlatform.android
        ? const Size(390, 844)
        : const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark.copyWith(platform: platform),
        builder: (c, child) => MediaQuery(
            data:
                MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: page));
    await t.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('cashback confirmation, accepted difference and undo $platform',
        (t) async {
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await open(t, platform, CashbackPage(kind: 'debit', cardId: cardId));
      expect(find.text('Previsto: R\$ 10,00'), findsOneWidget);
      await t.ensureVisible(find.text('Confirmar'));
      await t.tap(find.text('Confirmar'));
      await t.pumpAndSettle();
      final form = find.byType(CashbackConfirmationForm);
      expect(form, findsOneWidget);
      t
          .widget<MonetaryCalculatorField>(find.descendant(
              of: form, matching: find.byType(MonetaryCalculatorField)))
          .controller
          .text = '8,00';
      await t.tap(find.descendant(of: form, matching: find.text('Confirmar')));
      await t.pumpAndSettle();
      expect(find.text('Recebido líquido: R\$ 8,00'), findsOneWidget);
      expect(find.text('Previsto: R\$ 0,00'), findsOneWidget);
      await t.ensureVisible(find.text('Desfazer'));
      await t.tap(find.text('Desfazer'));
      await t.pumpAndSettle();
      await t.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Desfazer')));
      await t.pumpAndSettle();
      expect(find.text('Previsto: R\$ 10,00'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
    testWidgets(
        'debit and cashback support enlarged text and settings $platform',
        (t) async {
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await open(t, platform, const DebitCardsPage(), scale: 2);
      expect(find.text('Binance Débito'), findsOneWidget);
      expect(t.takeException(), isNull);
      await open(t, platform, CashbackPage(kind: 'debit', cardId: cardId),
          scale: 2);
      expect(t.takeException(), isNull);
      await t.tap(find.byTooltip('Configurar cashback do cartão'));
      await t.pumpAndSettle();
      expect(find.byType(CashbackSettingsForm), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('debit and cashback previews', (t) async {
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
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
      for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
        final suffix =
            platform == TargetPlatform.android ? 'mobile' : 'desktop';
        await open(t, platform, const DebitCardsPage());
        await expectLater(find.byType(DebitCardsPage),
            matchesGoldenFile('debit-$suffix-preview.png'));
        await open(t, platform, CashbackPage(kind: 'debit', cardId: cardId));
        await expectLater(find.byType(CashbackPage),
            matchesGoldenFile('cashback-$suffix-preview.png'));
        await t.tap(find.byTooltip('Configurar cashback do cartão'));
        await t.pumpAndSettle();
        await expectLater(find.byType(CashbackSettingsForm),
            matchesGoldenFile('cashback-settings-$suffix-preview.png'));
        expect(t.takeException(), isNull);
      }
    });
  }
}
