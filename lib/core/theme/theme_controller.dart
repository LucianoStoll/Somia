import 'package:flutter/material.dart';

import '../preferences/interface_preferences.dart';

/// Escolha de tema do usuário, guardada nas preferências locais da interface.
class ThemeController extends ChangeNotifier {
  ThemeController([this._preferences]) {
    final prefs = _preferences;
    if (prefs == null) return;
    if (prefs.read(_followSystemKey)) {
      _mode = ThemeMode.system;
    } else if (prefs.read(_lightKey)) {
      _mode = ThemeMode.light;
    }
  }

  static const _followSystemKey = 'theme.followSystem';
  static const _lightKey = 'theme.light';

  final InterfacePreferences? _preferences;

  // O Somia nasceu só com tema escuro; ele continua sendo o padrão.
  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = _preferences;
    if (prefs == null) return;
    await prefs.write(_followSystemKey, mode == ThemeMode.system);
    await prefs.write(_lightKey, mode == ThemeMode.light);
  }
}
