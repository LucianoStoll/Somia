import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:finapp/core/preferences/interface_preferences.dart';

void main() {
  test('retém contas com saldo e blocos recolhidos após reabrir', () async {
    final directory = await Directory.systemTemp.createTemp('somia-interface-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/interface.json');
    final first = InterfacePreferences(file);
    await first.load();
    expect(first.read('summary.hideZeroAccounts'), isFalse);
    await Future.wait([
      first.write('summary.hideZeroAccounts', true),
      first.write('summary.collapsed.Saldo por conta', true),
    ]);
    final reopened = InterfacePreferences(file);
    await reopened.load();
    expect(reopened.read('summary.hideZeroAccounts'), isTrue);
    expect(reopened.read('summary.collapsed.Saldo por conta'), isTrue);
    await reopened.write('summary.hideZeroAccounts', false);
    final third = InterfacePreferences(file);
    await third.load();
    expect(third.read('summary.hideZeroAccounts'), isFalse);
    expect(third.read('summary.collapsed.Saldo por conta'), isTrue);
  });

  test('arquivo visual inválido volta ao padrão sem impedir abertura',
      () async {
    final directory = await Directory.systemTemp.createTemp('somia-interface-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/interface.json');
    await file.writeAsString('{incompleto');
    final preferences = InterfacePreferences(file);
    await preferences.load();
    expect(preferences.read('summary.hideZeroAccounts'), isFalse);
  });
}
