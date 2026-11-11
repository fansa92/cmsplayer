import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
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

  /// 「连接正常」这类正向状态色。
  ///
  /// 不能直接用 `Colors.greenAccent`：它在浅色背景上对比度只有 1.4:1，
  /// 白底上几乎看不见。深色背景才用高亮绿，浅色背景用深绿（4.6:1）。
  static const Color successLight = Color(0xFF2E7D32);
  static const Color successDark = Color(0xFF69F0AE);

  static Color successOn(Brightness brightness) =>
      brightness == Brightness.dark ? successDark : successLight;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    // 配色注意：`ColorScheme.fromSeed` 给的 `outline` 在浅色下是 #767680，
    // 压在白底上只有 4.27:1，达不到正文所需 4.5:1。所以界面里的次要文字
    // 一律用 `onSurfaceVariant`，`outline` 只用于图标和描边。
    // test/theme_contrast_test.dart 会把这些比值钉住。
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    final bool isDark = brightness == Brightness.dark;

    // 桌面端用鼠标点，没必要给每个控件留 48dp 的触控靶；紧凑密度能让
    // 详情页的选集按钮、设置页的开关列表少占一截垂直空间。
    final bool desktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      visualDensity: desktop ? VisualDensity.compact : VisualDensity.standard,
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll<double>(8),
        radius: const Radius.circular(4),
        crossAxisMargin: 2,
        mainAxisMargin: 4,
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) {
            final bool active = states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.dragged);
            return scheme.onSurfaceVariant.withValues(
              alpha: active ? 0.65 : 0.3,
            );
          },
        ),
      ),
      tooltipTheme: TooltipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        waitDuration: const Duration(milliseconds: 400),
        textStyle: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white : scheme.onInverseSurface,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A3140) : scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? darkSurface : scheme.surface,
        modalBackgroundColor: isDark ? darkSurface : scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.25),
        selectionHandleColor: scheme.primary,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      scaffoldBackgroundColor: isDark ? darkBackground : scheme.surface,
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
        backgroundColor:
            isDark ? const Color(0xFF2A3140) : scheme.inverseSurface,
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
