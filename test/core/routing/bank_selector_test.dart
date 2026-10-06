import 'dart:io';

import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/features/accounts/domain/account.dart';
import 'package:finapp/features/accounts/domain/bank_institution.dart';
import 'package:finapp/features/accounts/presentation/account_identity.dart';
import 'package:finapp/features/accounts/presentation/accounts_page.dart';
import 'package:finapp/features/accounts/presentation/bank_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reference_form_test.dart' as forms;

void main() {
  test('busca ignora acentos e espaços e assets estão incluídos no app', () {
    expect(BankInstitution.search(' ITAU ').single.id, 'itau');
    expect(BankInstitution.search('banco inter').single.id, 'inter');
    expect(BankInstitution.search('inexistente'), isEmpty);
    expect(BankInstitution.find('ausente'), isNull);
    expect(BankInstitution.catalog.map((bank) => bank.id).toSet().length,
        BankInstitution.catalog.length);
    for (final bank in BankInstitution.catalog) {
      expect(File(bank.assetPath).existsSync(), isTrue, reason: bank.name);
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('selecionar, trocar, remover e cancelar instituição $platform',
        (tester) async {
      Object? result;
      await forms.open(tester, const AccountForm(),
          platform: platform,
          size: platform == TargetPlatform.android
              ? const Size(390, 844)
              : const Size(1280, 900),
          onResult: (value) => result = value);
      await tester.enterText(find.byType(TextFormField).first, 'Minha reserva');
      Future<void> choose(String query, String id) async {
        await tester.ensureVisible(find.text('Instituição'));
        await tester.tap(find.text('Instituição'));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.descendant(
                of: find.byType(BankSelector),
                matching: find.byType(TextField)),
            query);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('bank-$id')));
        await tester.pumpAndSettle();
      }

      await choose('itaU', 'itau');
      expect(find.text('Itaú'), findsOneWidget);
      expect(forms.field(tester, 0).controller!.text, 'Minha reserva');
      await tester.tap(find.text('Instituição'));
      await tester.pumpAndSettle();
      if (platform == TargetPlatform.android) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.text('Cancelar').last);
      }
      await tester.pumpAndSettle();
      expect(find.text('Itaú'), findsOneWidget);
      expect(find.text('Descartar alterações?'), findsNothing);
      await choose('nu', 'nubank');
      await tester.tap(find.text('Instituição'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sem instituição / ícone padrão'));
      await tester.pumpAndSettle();
      expect(find.text('Ícone padrão'), findsOneWidget);
      await choose('sicredi', 'sicredi');
      await tester.tap(find.text('Salvar conta'));
      await tester.pumpAndSettle();
      final draft = result as AccountDraft;
      expect(draft.institutionId, 'sicredi');
      expect(draft.name, 'Minha reserva');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'editar instituição integra confirmação de descarte e preserva original',
      (tester) async {
    const account = Account(
        id: 'a',
        name: 'Reserva',
        type: AccountType.savings,
        currencyCode: 'BRL',
        initialBalanceMinor: 1000,
        currentBalanceMinor: 1000,
        projectedBalanceMinor: 1000,
        isArchived: false,
        includeInAnalytics: true,
        institutionId: 'itau');
    await forms.open(tester, const AccountForm(account: account));
    expect(find.text('Itaú'), findsOneWidget);
    await tester.tap(find.text('Instituição'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bank-bradesco')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsOneWidget);
    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(find.text('Bradesco'), findsOneWidget);
  });

  testWidgets(
      'logos locais legíveis em tamanhos pequenos e fallback para ausentes',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
            body: Column(children: [
          for (final bank in BankInstitution.catalog)
            Row(children: [
              for (final size in [24.0, 28.0, 40.0])
                AccountAvatar(institutionId: bank.id, size: size)
            ]),
          const AccountAvatar(institutionId: 'ausente', type: AccountType.cash),
        ]))));
    await tester.pumpAndSettle();
    expect(
        find.byType(Image), findsNWidgets(BankInstitution.catalog.length * 3));
    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  if (const bool.fromEnvironment('SOMIA_RENDER_PREVIEW')) {
    testWidgets('renderiza catálogo offline no tema escuro', (tester) async {
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
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.android),
          home: const BankSelector(selected: 'sicredi')));
      await tester.pumpAndSettle();
      await expectLater(
          find.byType(Scaffold), matchesGoldenFile('banks-mobile-preview.png'));
    });
  }
}
