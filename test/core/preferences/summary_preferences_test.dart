import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/preferences/interface_preferences.dart';
import 'package:finapp/features/dashboard/presentation/widgets/dashboard_overview.dart';

void main() {
  testWidgets('resumo restaura contas com saldo e recolhimento ao remontar',
      (tester) async {
    final directory =
        await Directory.systemTemp.createTemp('summary-preferences-');
    final preferences = InterfacePreferences(File('${directory.path}/ui.json'));
    await preferences.load();
    await getIt.reset();
    getIt.registerSingleton<InterfacePreferences>(preferences);
    addTearDown(() async {
      await preferences.flush();
      await getIt.reset();
      await directory.delete(recursive: true);
    });
    Widget page() => const MaterialApp(
        home: Scaffold(body: SummaryAccounts(currencies: [])));
    await tester.pumpWidget(page());
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    await tester.tap(find.byTooltip('Recolher bloco'));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => preferences.flush());
    await tester.runAsync(() => preferences.load());
    await tester.pumpWidget(page());
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.tap(find.byTooltip('Expandir bloco'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
  });
}
