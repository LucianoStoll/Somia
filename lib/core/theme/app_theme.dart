import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'somia_tokens.dart';

export 'somia_tokens.dart';

/// Ponte para o código anterior aos tokens: cada nome devolve a cor
/// equivalente do tema ativo (claro ou escuro).
///
/// Código novo deve usar `context.somia`. As telas migram para os tokens
/// à medida que forem redesenhadas; depois disso esta classe sai.
// ignore_for_file: unnecessary_getters_setters
abstract final class SomiaColors {
  static SomiaTokens _active = SomiaTokens.dark;

  /// Tema em uso. Atualizado por `FinApp` antes de cada construção.
  static SomiaTokens get active => _active;
  static set active(SomiaTokens value) => _active = value;

  static Color get background => _active.background;
  static Color get sidebar => _active.sidebar;
  static Color get surface => _active.surface;
  static Color get surfaceHigh => _active.surfaceHigh;
  static Color get outline => _active.outline;
  static Color get muted => _active.muted;

  /// Antes azul acinzentado; agora o destaque da marca.
  static Color get blue => _active.accent;
  static Color get green => _active.income;
  static Color get red => _active.expense;
  static Color get purple => _active.transfer;
  static Color get yellow => _active.pending;
}

abstract final class AppTheme {
  static ThemeData get dark => build(SomiaTokens.dark);
  static ThemeData get light => build(SomiaTokens.light);

  static ThemeData build(SomiaTokens t) {
    final scheme = ColorScheme.fromSeed(
      seedColor: t.accent,
      brightness: t.brightness,
    ).copyWith(
      primary: t.accent,
      onPrimary: t.onAccent,
      secondary: t.transfer,
      surface: t.surface,
      onSurface: t.ink,
      onSurfaceVariant: t.muted,
      surfaceContainerLowest: t.background,
      surfaceContainerLow: t.surface,
      surfaceContainer: t.surface,
      surfaceContainerHigh: t.surfaceHigh,
      surfaceContainerHighest: t.surfaceHigh,
      outline: t.outline,
      outlineVariant: t.outline,
      error: t.expense,
    );
    // O textTheme guardado no ThemeData segue o formato que o Flutter espera
    // (cores e tamanhos, inherit: true); a geometria é acrescentada por
    // Theme.of. Estilos de botões, animados entre estados e temas, são
    // completos (inherit: false), como os padrões do Material.
    final typography = Typography.material2021(platform: defaultTargetPlatform);
    final text = _textTheme(t.isDark ? typography.white : typography.black, t);
    TextStyle button(double size, FontWeight weight) =>
        typography.englishLike.labelLarge!.copyWith(
            fontFamily: somiaFontFamily,
            fontSize: size,
            fontWeight: weight,
            letterSpacing: 0);
    final base = ThemeData(
      useMaterial3: true,
      brightness: t.brightness,
      colorScheme: scheme,
      typography: typography,
      textTheme: text,
      fontFamily: somiaFontFamily,
      extensions: [t],
    );
    return base.copyWith(
      scaffoldBackgroundColor: t.background,
      canvasColor: t.background,
      dividerColor: t.outline,
      dividerTheme: DividerThemeData(color: t.outline, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: t.background,
        foregroundColor: t.ink,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text.headlineSmall,
      ),
      cardTheme: CardThemeData(
        color: t.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SomiaRadius.lg),
          side: t.isDark
              ? BorderSide.none
              : BorderSide(color: t.outline, width: 0.7),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: t.sidebar,
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: t.sidebar,
        indicatorColor: t.accent.withValues(alpha: 0.16),
        selectedIconTheme: IconThemeData(color: t.accent),
        unselectedIconTheme: IconThemeData(color: t.muted),
        selectedLabelTextStyle: text.labelLarge
            ?.copyWith(color: t.ink, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: text.labelLarge?.copyWith(color: t.muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.isDark ? t.surfaceHigh : t.surface,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: SomiaSpace.lg, vertical: SomiaSpace.md),
        labelStyle: TextStyle(color: t.muted),
        hintStyle: TextStyle(color: t.muted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SomiaRadius.sm),
          borderSide: BorderSide(color: t.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SomiaRadius.sm),
          borderSide: BorderSide(color: t.accent, width: 1.5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SomiaRadius.sm),
          borderSide: BorderSide(color: t.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          minimumSize: const Size(64, 44),
          shape: const StadiumBorder(),
          textStyle: button(15, FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.ink,
          minimumSize: const Size(64, 40),
          side: BorderSide(color: t.outline),
          shape: const StadiumBorder(),
          textStyle: button(14, FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.accent,
          textStyle: button(14, FontWeight.w700),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll(BorderSide(color: t.outline)),
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? t.ink : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? t.background : t.ink),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: t.ink,
        checkmarkColor: t.background,
        showCheckmark: false,
        side: BorderSide(color: t.outline),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          fontFamily: somiaFontFamily,
          fontSize: 14,
          color: WidgetStateColor.resolveWith(
              (s) => s.contains(WidgetState.selected) ? t.background : t.ink),
          fontWeight: FontWeight.w600,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SomiaRadius.sm)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SomiaRadius.lg)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(SomiaRadius.lg))),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: t.background),
        actionTextColor: t.isDark ? t.onAccent : t.accent,
        behavior: SnackBarBehavior.floating,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SomiaRadius.md)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        linearTrackColor: t.outline,
        linearMinHeight: 6,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: t.ink,
        unselectedLabelColor: t.muted,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: t.accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(SomiaRadius.sm),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: t.muted,
        textColor: t.ink,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: SomiaSpace.lg, vertical: SomiaSpace.xxs),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.onAccent : t.muted),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.accent : t.outline),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }

  /// Escala tipográfica única do app. Valores monetários usam algarismos
  /// tabulares para alinhar em colunas.
  static TextTheme _textTheme(TextTheme base, SomiaTokens t) {
    const tabular = [FontFeature.tabularFigures()];
    TextStyle? s(TextStyle? style, double size, FontWeight weight,
            {double spacing = 0, Color? color, double? height}) =>
        style?.copyWith(
          fontFamily: somiaFontFamily,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
          height: height,
          color: color ?? t.ink,
          fontFeatures: tabular,
        );
    return base.copyWith(
      // Valor principal da tela (saldo, valor do lançamento).
      displaySmall:
          s(base.displaySmall, 34, FontWeight.w800, spacing: -1, height: 1.1),
      headlineMedium: s(base.headlineMedium, 26, FontWeight.w800,
          spacing: -0.5, height: 1.15),
      // Título da tela.
      headlineSmall: s(base.headlineSmall, 22, FontWeight.w800,
          spacing: -0.4, height: 1.2),
      titleLarge: s(base.titleLarge, 20, FontWeight.w700, height: 1.25),
      // Título de seção.
      titleMedium: s(base.titleMedium, 17, FontWeight.w700, height: 1.3),
      titleSmall: s(base.titleSmall, 15, FontWeight.w600, height: 1.3),
      bodyLarge: s(base.bodyLarge, 16, FontWeight.w400, height: 1.45),
      bodyMedium: s(base.bodyMedium, 15, FontWeight.w400, height: 1.45),
      bodySmall:
          s(base.bodySmall, 13, FontWeight.w400, color: t.muted, height: 1.4),
      labelLarge: s(base.labelLarge, 14, FontWeight.w600),
      labelMedium: s(base.labelMedium, 13, FontWeight.w600, color: t.muted),
      labelSmall: s(base.labelSmall, 12, FontWeight.w600, color: t.muted),
    );
  }
}
