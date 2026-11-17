import 'dart:io';
import 'dart:math' as math;

import 'package:finapp/core/preferences/interface_preferences.dart';
import 'package:finapp/core/theme/app_theme.dart';
import 'package:finapp/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryPreferences extends InterfacePreferences {
  _MemoryPreferences() : super(File('unused-theme-test.json'));
  final values = <String, bool>{};
  @override
  bool read(String key, {bool fallback = false}) => values[key] ?? fallback;
  @override
  Future<void> write(String key, bool value) async {
    values[key] = value;
  }
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('tema escuro continua sendo o padrão', () {
    expect(ThemeController(_MemoryPreferences()).mode, ThemeMode.dark);
    expect(ThemeController().mode, ThemeMode.dark);
  });

  test('escolha de tema é guardada e restaurada', () async {
    final preferences = _MemoryPreferences();
    final controller = ThemeController(preferences);
    var notified = 0;
    controller.addListener(() => notified++);

    await controller.setMode(ThemeMode.light);
    expect(ThemeController(preferences).mode, ThemeMode.light);

    await controller.setMode(ThemeMode.system);
    expect(ThemeController(preferences).mode, ThemeMode.system);

    await controller.setMode(ThemeMode.dark);
    expect(ThemeController(preferences).mode, ThemeMode.dark);
    expect(notified, 3);
  });

  test('textos e valores têm contraste mínimo de 4,5:1 nos dois temas', () {
    for (final t in [SomiaTokens.dark, SomiaTokens.light]) {
      for (final ground in [t.background, t.surface]) {
        for (final (name, color) in [
          ('ink', t.ink),
          ('muted', t.muted),
          ('accent', t.accent),
          ('income', t.income),
          ('expense', t.expense),
          ('transfer', t.transfer),
        ]) {
          expect(_contrast(color, ground), greaterThanOrEqualTo(4.5),
              reason: '$name em ${t.brightness.name}');
        }
      }
      expect(_contrast(t.onAccent, t.accent), greaterThanOrEqualTo(4.5),
          reason: 'onAccent em ${t.brightness.name}');
    }
  });

  test('temas expõem os tokens e a fonte do Somia', () {
    for (final theme in [AppTheme.dark, AppTheme.light]) {
      final tokens = theme.extension<SomiaTokens>();
      expect(tokens, isNotNull);
      expect(theme.colorScheme.primary, tokens!.accent);
      expect(theme.scaffoldBackgroundColor, tokens.background);
      expect(theme.textTheme.bodyMedium?.fontFamily, somiaFontFamily);
    }
  });
}
