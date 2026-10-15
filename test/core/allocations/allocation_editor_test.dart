import 'dart:io';
import 'package:flutter/services.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/widgets/movement_form_frame.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/transactions/domain/financial_transaction.dart';
import 'package:finapp/features/transactions/presentation/transactions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/allocations/allocation_editor.dart';
import 'package:finapp/core/allocations/category_allocation.dart';
import 'package:finapp/features/categories/domain/category.dart';

void main() {
  const categories = [
    FinanceCategory(
        id: 'a',
        name: 'Mercado',
        type: CategoryType.expense,
        parentId: null,
        isArchived: false,
        iconKey: null,
        colorArgb: null),
    FinanceCategory(
        id: 'b',
        name: 'Casa',
        type: CategoryType.expense,
        parentId: null,
        isArchived: false,
        iconKey: null,
        colorArgb: null)
  ];
  testWidgets(
      'percentual conserva total, rejeita diferença e preserva estado em total alterado',
      (tester) async {
    final form = GlobalKey<FormState>();
    var total = 10001;
    late StateSetter change;
    List<CategoryAllocation> result = [];
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
          change = setState;
          return SingleChildScrollView(
              child: Form(
                  key: form,
                  child: AllocationEditor(
                      categories: categories,
                      type: 'expense',
                      total: total,
                      initial: const [
                        CategoryAllocation('a', 6001),
                        CategoryAllocation('b', 4000)
                      ],
                      onChanged: (v) => result = v)));
        }))));
    expect(form.currentState!.validate(), isTrue);
    await tester.tap(find.text('Por percentual'));
    await tester.pumpAndSettle();
    expect(result.fold(0, (s, p) => s + p.amountMinor), 10001);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, '50');
    await tester.pump();
    expect(form.currentState!.validate(), isFalse);
    await tester.enterText(fields.at(1), '50');
    await tester.pump();
    expect(form.currentState!.validate(), isTrue);
    expect(result.map((p) => p.amountMinor), [5001, 5000]);
    change(() => total = 20001);
    await tester.pump();
    expect(result.map((p) => p.amountMinor), [10001, 10000]);
    expect(tester.takeException(), isNull);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('formulário rateado salva partes no ${platform.name}',
        (tester) async {
      if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
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
      }
      tester.view.physicalSize = platform == TargetPlatform.android
          ? const Size(390, 844)
          : const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TransactionDraft? result;
      final item = FinancialTransaction(
          id: 't',
          description: 'Compra rateada',
          type: TransactionType.expense,
          amountMinor: 10001,
          date: DateTime(2026, 9, 1),
          isEffective: false,
          accountId: 'x',
          accountName: 'Banco',
          categoryId: null,
          categoryName: null,
          currencyCode: 'BRL',
          allocations: const [
            CategoryAllocation('a', 6001),
            CategoryAllocation('b', 4000)
          ]);
      const account = Account(
          id: 'x',
          name: 'Banco',
          type: AccountType.checking,
          currencyCode: 'BRL',
          initialBalanceMinor: 0,
          currentBalanceMinor: 0,
          projectedBalanceMinor: 0,
          isArchived: false,
          includeInAnalytics: true);
      await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark.copyWith(platform: platform),
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () async {
                        result = await showMovementForm<TransactionDraft>(
                            context,
                            (_) => TransactionForm(
                                accounts: const [account],
                                categories: categories,
                                item: item,
                                fixedType: TransactionType.expense));
                      },
                      child: const Text('Abrir'))))));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Dividir entre categorias'), findsOneWidget);
      expect(find.text('Por percentual'), findsOneWidget);
      if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
                'allocation-${platform == TargetPlatform.android ? "mobile" : "desktop"}-preview.png'));
      }
      await tester.tap(find.text('Salvar lançamento'));
      await tester.pumpAndSettle();
      expect(result!.categoryId, isNull);
      expect(result!.allocations.map((p) => p.amountMinor), [6001, 4000]);
      expect(tester.takeException(), isNull);
    });
  }
}
