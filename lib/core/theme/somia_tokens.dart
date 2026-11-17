import 'package:flutter/material.dart';

/// Cores da identidade Somia (direção visual "Fluxo"), em versão escura e
/// clara. Telas novas devem ler as cores por `context.somia`; o tema
/// Material é derivado destes mesmos valores em `AppTheme`.
@immutable
class SomiaTokens extends ThemeExtension<SomiaTokens> {
  const SomiaTokens({
    required this.brightness,
    required this.background,
    required this.sidebar,
    required this.surface,
    required this.surfaceHigh,
    required this.outline,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.income,
    required this.expense,
    required this.pending,
    required this.transfer,
    required this.chartArea,
    required this.categories,
  });

  final Brightness brightness;

  /// Fundo das telas.
  final Color background;

  /// Menu lateral (Windows) e drawer.
  final Color sidebar;

  /// Superfície de blocos e campos.
  final Color surface;

  /// Superfície elevada: menus, diálogos, campos em foco.
  final Color surfaceHigh;

  /// Linhas divisórias e contornos.
  final Color outline;

  /// Texto principal.
  final Color ink;

  /// Texto secundário (contraste mínimo de 4,5:1 sobre o fundo).
  final Color muted;

  /// Destaque da marca: ação principal, previsão, item ativo.
  final Color accent;
  final Color onAccent;

  /// Entradas de dinheiro.
  final Color income;

  /// Saídas de dinheiro e alertas.
  final Color expense;

  /// Lançamentos a pagar ou a receber.
  final Color pending;

  /// Transferências entre contas.
  final Color transfer;

  /// Preenchimento sob a linha do gráfico de saldo.
  final Color chartArea;

  /// Cores de categorias e séries, na ordem de uso.
  final List<Color> categories;

  bool get isDark => brightness == Brightness.dark;

  static const dark = SomiaTokens(
    brightness: Brightness.dark,
    background: Color(0xFF0F1222),
    sidebar: Color(0xFF0B0E1B),
    surface: Color(0xFF191D33),
    surfaceHigh: Color(0xFF232842),
    outline: Color(0xFF2C3150),
    ink: Color(0xFFEEF0FA),
    muted: Color(0xFF9DA3C2),
    accent: Color(0xFFF2B45A),
    onAccent: Color(0xFF241703),
    income: Color(0xFF5FD0B5),
    expense: Color(0xFFFF8E7E),
    pending: Color(0xFFF2B45A),
    transfer: Color(0xFF8C9CFF),
    chartArea: Color(0x0FEEF0FA),
    categories: [
      Color(0xFF8C9CFF),
      Color(0xFFF2B45A),
      Color(0xFF5FD0B5),
      Color(0xFFFF8E7E),
      Color(0xFFC79BEB),
      Color(0xFF6FB7F0),
      Color(0xFFE6C86E),
      Color(0xFF6B7192),
    ],
  );

  static const light = SomiaTokens(
    brightness: Brightness.light,
    background: Color(0xFFF5F6FB),
    sidebar: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFFFFFFF),
    outline: Color(0xFFDDE0EE),
    ink: Color(0xFF161A2E),
    muted: Color(0xFF5B6180),
    accent: Color(0xFF94600C),
    onAccent: Color(0xFFFFFFFF),
    income: Color(0xFF0B7A60),
    expense: Color(0xFFB53D31),
    pending: Color(0xFF94600C),
    transfer: Color(0xFF4A5BD4),
    chartArea: Color(0x0D161A2E),
    categories: [
      Color(0xFF4A5BD4),
      Color(0xFFD99A2B),
      Color(0xFF169C7E),
      Color(0xFFD4594B),
      Color(0xFF8E4FB8),
      Color(0xFF2F86C9),
      Color(0xFFB59A2E),
      Color(0xFF8C92B0),
    ],
  );

  @override
  SomiaTokens copyWith({
    Brightness? brightness,
    Color? background,
    Color? sidebar,
    Color? surface,
    Color? surfaceHigh,
    Color? outline,
    Color? ink,
    Color? muted,
    Color? accent,
    Color? onAccent,
    Color? income,
    Color? expense,
    Color? pending,
    Color? transfer,
    Color? chartArea,
    List<Color>? categories,
  }) =>
      SomiaTokens(
        brightness: brightness ?? this.brightness,
        background: background ?? this.background,
        sidebar: sidebar ?? this.sidebar,
        surface: surface ?? this.surface,
        surfaceHigh: surfaceHigh ?? this.surfaceHigh,
        outline: outline ?? this.outline,
        ink: ink ?? this.ink,
        muted: muted ?? this.muted,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        income: income ?? this.income,
        expense: expense ?? this.expense,
        pending: pending ?? this.pending,
        transfer: transfer ?? this.transfer,
        chartArea: chartArea ?? this.chartArea,
        categories: categories ?? this.categories,
      );

  @override
  SomiaTokens lerp(SomiaTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return SomiaTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: c(background, other.background),
      sidebar: c(sidebar, other.sidebar),
      surface: c(surface, other.surface),
      surfaceHigh: c(surfaceHigh, other.surfaceHigh),
      outline: c(outline, other.outline),
      ink: c(ink, other.ink),
      muted: c(muted, other.muted),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      income: c(income, other.income),
      expense: c(expense, other.expense),
      pending: c(pending, other.pending),
      transfer: c(transfer, other.transfer),
      chartArea: c(chartArea, other.chartArea),
      categories: [
        for (var i = 0; i < categories.length; i++)
          i < other.categories.length
              ? c(categories[i], other.categories[i])
              : categories[i],
      ],
    );
  }
}

/// Escala de espaçamento: use estes valores em vez de números soltos.
abstract final class SomiaSpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Raios de canto, do menor (chips) ao maior (blocos).
abstract final class SomiaRadius {
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 22;
  static const double pill = 999;
}

/// Família tipográfica do aplicativo (empacotada em assets/fonts).
const somiaFontFamily = 'PlusJakartaSans';

extension SomiaThemeContext on BuildContext {
  SomiaTokens get somia =>
      Theme.of(this).extension<SomiaTokens>() ?? SomiaTokens.dark;
}
