import 'package:flutter/material.dart';

/// 主题。深色为默认观感（与 CMSPlayer 一致），跟随系统可切换。
class AppTheme {
  AppTheme._();

  /// 品牌色：蓝紫。
  static const Color seed = Color(0xFF5B7CFA);

  static const Color darkBackground = Color(0xFF0B0D12);
  static const Color darkSurface = Color(0xFF141821);
  static const Color darkSurfaceVariant = Color(0xFF1C212C);

  /// 海报占位渐变。
  static const List<Color> posterPlaceholder = <Color>[
    Color(0xFF232A38),
    Color(0xFF161B25),
  ];

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    final bool isDark = brightness == Brightness.dark;

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      scaffoldBackgroundColor:
          isDark ? darkBackground : scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? darkBackground : scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? darkSurface : scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? darkSurface : scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        labelType: NavigationRailLabelType.all,
        groupAlignment: -0.9,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? darkSurface : scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        height: 64,
        labelTextStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? darkSurfaceVariant : scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline, width: 1.2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2A3140) : scheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: isDark ? Colors.white : scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? darkSurface : scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        iconColor: scheme.onSurfaceVariant,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white10 : scheme.outlineVariant,
        space: 1,
      ),
      sliderTheme: base.sliderTheme.copyWith(
        trackHeight: 3,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
    );
  }
}
