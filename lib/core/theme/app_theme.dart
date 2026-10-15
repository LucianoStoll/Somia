import 'package:flutter/material.dart';

abstract final class SomiaColors {
  static const background = Color(0xFF141518);
  static const sidebar = Color(0xFF101216);
  static const surface = Color(0xFF202226);
  static const surfaceHigh = Color(0xFF292C32);
  static const outline = Color(0xFF34383F);
  static const muted = Color(0xFFADB0B8);
  static const blue = Color(0xFFA5BCD0);
  static const green = Color(0xFFA8C5B0);
  static const red = Color(0xFFD6A3A3);
  static const purple = Color(0xFFB8B3D9);
  static const yellow = Color(0xFFD8C49E);
}

abstract final class AppTheme {
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
            seedColor: SomiaColors.blue,
            brightness: Brightness.dark,
            surface: SomiaColors.surface)
        .copyWith(
      primary: SomiaColors.blue,
      onPrimary: SomiaColors.sidebar,
      onSurface: const Color(0xFFF3F6FA),
      outline: SomiaColors.outline,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: SomiaColors.background,
      canvasColor: SomiaColors.background,
      dividerColor: SomiaColors.outline,
      appBarTheme: const AppBarTheme(
          backgroundColor: SomiaColors.background,
          centerTitle: false,
          elevation: 0,
          titleTextStyle: TextStyle(
              color: Color(0xFFF3F6FA),
              fontSize: 20,
              fontWeight: FontWeight.w600)),
      cardTheme: CardThemeData(
          color: SomiaColors.surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: SomiaColors.outline, width: 0.7))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: SomiaColors.surfaceHigh,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: SomiaColors.outline, width: 0.7)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: SomiaColors.blue)),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: SomiaColors.outline))),
      popupMenuTheme: PopupMenuThemeData(
          color: SomiaColors.surfaceHigh,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: SomiaColors.blue,
          foregroundColor: SomiaColors.sidebar,
          elevation: 0),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: SomiaColors.blue,
          linearTrackColor: SomiaColors.surfaceHigh,
          linearMinHeight: 6,
          borderRadius: BorderRadius.all(Radius.circular(8))),
      tabBarTheme: TabBarThemeData(
          labelColor: SomiaColors.blue,
          unselectedLabelColor: SomiaColors.muted,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
              color: SomiaColors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12)),
          indicatorSize: TabBarIndicatorSize.tab),
      listTileTheme: const ListTileThemeData(
          iconColor: SomiaColors.muted,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2)),
    );
  }
}
