import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/theme/app_theme.dart';

/// 主题对比度走查。
///
/// 用 WCAG 2.1 的相对亮度公式算真实比值，钉住深浅两套主题里
/// 「文字 / 背景」的组合。之前的实际问题是：`ColorScheme.fromSeed` 生成的
/// `outline`（浅色 #767680）压在白底上只有 4.27:1，而界面里好几处
/// 把它当正文颜色用（"内容来自…"、"导演"、源备注、同步说明）。
double _channel(double v) {
  final double s = v / 255.0;
  return s <= 0.03928
      ? s / 12.92
      : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double contrast(Color a, Color b) {
  double luminance(Color c) =>
      0.2126 * _channel(c.r * 255) +
      0.7152 * _channel(c.g * 255) +
      0.0722 * _channel(c.b * 255);
  final double la = luminance(a);
  final double lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final Brightness brightness in Brightness.values) {
    final ThemeData theme =
        brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light();
    final ColorScheme scheme = theme.colorScheme;
    final Color bg = theme.scaffoldBackgroundColor;
    final String label = brightness == Brightness.dark ? '深色' : '浅色';

    group('$label主题', () {
      void atLeast(Color fg, Color on, double min, String what) {
        final double ratio = contrast(fg, on);
        expect(
          ratio,
          greaterThanOrEqualTo(min),
          reason: '$what 的对比度是 ${ratio.toStringAsFixed(2)}:1，低于 $min:1',
        );
      }

      test('正文与背景', () {
        atLeast(scheme.onSurface, bg, 7, 'onSurface');
      });

      test('次要文字在三种底色上都够 4.5:1', () {
        atLeast(scheme.onSurfaceVariant, bg, 4.5, 'onSurfaceVariant / 页面底色');
        atLeast(
          scheme.onSurfaceVariant,
          scheme.surfaceContainerLow,
          4.5,
          'onSurfaceVariant / 卡片',
        );
        atLeast(
          scheme.onSurfaceVariant,
          scheme.surfaceContainerHighest,
          4.5,
          'onSurfaceVariant / 标签块',
        );
      });

      test('主色与错误色可读', () {
        atLeast(scheme.primary, bg, 4.5, 'primary');
        atLeast(scheme.onPrimary, scheme.primary, 4.5, 'onPrimary');
        atLeast(scheme.error, bg, 4.5, 'error');
        atLeast(
          scheme.onErrorContainer,
          scheme.errorContainer,
          4.5,
          'onErrorContainer',
        );
        atLeast(
          scheme.onTertiaryContainer,
          scheme.tertiaryContainer,
          4.5,
          'onTertiaryContainer',
        );
      });

      test('正向状态色可读', () {
        // 源管理页的「连接正常」：旧代码直接用 Colors.greenAccent，
        // 浅色底上只有 1.4:1。
        atLeast(AppTheme.successOn(brightness), bg, 4.5, 'success');
      });
    });
  }

  test('深色主题用的是自定义底色而不是 M3 默认 surface', () {
    final ThemeData dark = AppTheme.dark();
    expect(dark.scaffoldBackgroundColor, AppTheme.darkBackground);
    expect(dark.colorScheme.brightness, Brightness.dark);
    expect(dark.brightness, Brightness.dark);
  });

  test('两套主题都补齐了常用控件样式', () {
    for (final ThemeData t in <ThemeData>[AppTheme.dark(), AppTheme.light()]) {
      expect(t.tooltipTheme.decoration, isNotNull);
      expect(t.bottomSheetTheme.backgroundColor, isNotNull);
      expect(t.scrollbarTheme.thickness?.resolve(<WidgetState>{}), 8);
      expect(t.filledButtonTheme.style, isNotNull);
      expect(t.textButtonTheme.style, isNotNull);
      expect(t.outlinedButtonTheme.style, isNotNull);
    }
  });
}
