import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/di/injection.dart';
import 'package:finapp/core/preferences/interface_preferences.dart';
import 'package:finapp/features/dashboard/presentation/widgets/dashboard_overview.dart';

class _MemoryPreferences extends InterfacePreferences {
  _MemoryPreferences() : super(File('unused-interface-test.json'));
  final values = <String, bool>{};
  @override
  bool read(String key, {bool fallback = false}) => values[key] ?? fallback;
  @override
  Future<void> write(String key, bool value) async {
    values[key] = value;
  }
}

void main() {
  testWidgets('resumo restaura contas com saldo e recolhimento ao remontar',
      (tester) async {
    final preferences = _MemoryPreferences();
    await getIt.reset();
    getIt.registerSingleton<InterfacePreferences>(preferences);
    addTearDown(() => getIt.reset());
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
    await tester.pumpWidget(page());
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.tap(find.byTooltip('Expandir bloco'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
  });
}
