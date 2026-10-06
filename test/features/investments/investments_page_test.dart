import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/widgets/movement_form_frame.dart';
import 'package:finapp/core/widgets/monetary_calculator.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/investments/domain/investment.dart';
import 'package:finapp/features/investments/presentation/investment_forms.dart';
import 'package:finapp/features/investments/presentation/investments_page.dart';

const bank = Account(
    id: 'bank',
    name: 'Conta corrente',
    type: AccountType.checking,
    currencyCode: 'BRL',
    initialBalanceMinor: 100000,
    currentBalanceMinor: 100000,
    projectedBalanceMinor: 100000,
    isArchived: false,
    includeInAnalytics: true);
const applicationAccount = Account(
    id: 'application',
    name: 'Reserva',
    type: AccountType.investment,
    currencyCode: 'BRL',
    initialBalanceMinor: 200000,
    currentBalanceMinor: 200000,
    projectedBalanceMinor: 200000,
    isArchived: false,
    includeInAnalytics: true,
    includeInBalance: false);
const item = Investment(
    id: 'cdb',
    name: 'CDB Reserva',
    kind: InvestmentKind.cdb,
    institution: 'Banco',
    notes: '',
    account: applicationAccount);

class _Repo implements InvestmentsRepository {
  InvestmentOverview overview =
      const InvestmentOverview([item], [bank, applicationAccount]);
  final saved = <InvestmentDraft>[];
  final changes = <int>[];
  bool failSave = false;
  @override
  Future<InvestmentOverview> load({DateTime? date}) async => overview;
  @override
  Future<void> save(InvestmentDraft draft, {String? id}) async {
    if (failSave)
      throw const FormatException(
          'Esta conta já está vinculada a uma aplicação.');
    saved.add(draft);
  }

  @override
  Future<void> transfer(String id,
      {required String otherAccountId,
      required bool deposit,
      required int amountMinor,
      required DateTime date}) async {
    changes.add(amountMinor);
  }

  @override
  Future<void> recordReturn(String id,
      {required int amountMinor, required DateTime date}) async {
    changes.add(amountMinor);
  }

  @override
  Future<void> reconcile(String id,
      {required int targetMinor,
      required int expectedBalanceMinor,
      required DateTime date}) async {
    changes.add(targetMinor);
  }

  @override
  Future<void> setArchived(String id, bool archived) async {}
}

Future<void> _open(WidgetTester tester, Widget form,
    {TargetPlatform platform = TargetPlatform.android,
    Size size = const Size(390, 844),
    double scale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark.copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                  onPressed: () => showMovementForm<bool>(context, (_) => form),
                  child: const Text('Abrir'))))));
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

Future<void> _fonts() async {
  if (!const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) return;
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
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('cadastro e calculadora ${platform.name}', (tester) async {
      await _fonts();
      final repo = _Repo();
      await _open(
          tester, InvestmentForm(repository: repo, overview: repo.overview),
          platform: platform,
          size: platform == TargetPlatform.android
              ? const Size(390, 844)
              : const Size(1000, 800));
      expect(find.byType(MonetaryCalculatorField), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'CDB Teste');
      if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
                'investment-form-${platform == TargetPlatform.android ? "mobile" : "desktop"}-preview.png'));
      }
      await tester.tap(find.text('Salvar aplicação'));
      await tester.pumpAndSettle();
      expect(repo.saved.single.name, 'CDB Teste');
      expect(repo.saved.single.kind, InvestmentKind.cdb);
      expect(tester.takeException(), isNull);
    });

    testWidgets('prévia da tela ${platform.name}', (tester) async {
      await _fonts();
      tester.view.physicalSize = platform == TargetPlatform.android
          ? const Size(390, 844)
          : const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      getIt.registerSingleton<InvestmentsRepository>(_Repo());
      addTearDown(() => getIt.reset());
      await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark.copyWith(platform: platform),
          home: const InvestmentsPage()));
      await tester.pumpAndSettle();
      expect(find.text('R\$ 2000,00'), findsNWidgets(2));
      expect(find.text('Total em contas (BRL): R\$ 3000,00'), findsOneWidget);
      expect(find.text('Aporte'), findsOneWidget);
      expect(find.text('Saldo do banco'), findsOneWidget);
      if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
        await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
                'investments-${platform == TargetPlatform.android ? "mobile" : "desktop"}-preview.png'));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('conta existente oculta saldo inicial e erro preserva formulário',
      (tester) async {
    final repo = _Repo()..failSave = true;
    await _open(
        tester, InvestmentForm(repository: repo, overview: repo.overview));
    await tester.enterText(find.byType(TextFormField).first, 'CDI Teste');
    final account = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(account);
    await tester.tap(account);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conta corrente').last);
    await tester.pumpAndSettle();
    expect(find.byType(MonetaryCalculatorField), findsNothing);
    await tester.tap(find.text('Salvar aplicação'));
    await tester.pumpAndSettle();
    expect(find.text('Esta conta já está vinculada a uma aplicação.'),
        findsOneWidget);
    expect(find.text('CDI Teste'), findsOneWidget);
    expect(repo.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelar conferência não grava; confirmar grava uma vez',
      (tester) async {
    final repo = _Repo();
    await _open(
        tester,
        InvestmentOperationForm(
            repository: repo,
            investment: item,
            accounts: repo.overview.accounts,
            action: InvestmentAction.balance));
    await tester.tap(find.text('Conferir ajuste'));
    await tester.pumpAndSettle();
    expect(find.text('Conferir saldo do banco'), findsOneWidget);
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(repo.changes, isEmpty);
    await tester.tap(find.text('Conferir ajuste'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar ajuste'));
    await tester.pumpAndSettle();
    expect(repo.changes, [200000]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aporte exige outra conta e cancelamento não grava',
      (tester) async {
    final repo = _Repo();
    await _open(
        tester,
        InvestmentOperationForm(
            repository: repo,
            investment: item,
            accounts: repo.overview.accounts,
            action: InvestmentAction.deposit));
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();
    expect(find.text('Selecione outra conta ativa em reais.'), findsOneWidget);
    expect(repo.changes, isEmpty);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
    expect(repo.changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('campos e salvar acessíveis em tela estreita com fonte ampliada',
      (tester) async {
    final repo = _Repo();
    await _open(
        tester, InvestmentForm(repository: repo, overview: repo.overview),
        size: const Size(320, 640), scale: 2);
    expect(find.text('Salvar aplicação').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.byType(TextFormField).last);
    await tester.pumpAndSettle();
    expect(find.text('Observações (opcional)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
