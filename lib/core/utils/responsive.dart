import 'dart:io' show Platform;

import 'package:flutter/material.dart';

/// 断点定义：与 Material 3 的窗口宽度分类保持一致。
class Breakpoints {
  Breakpoints._();

  /// 紧凑：手机竖屏，使用底部导航栏。
  static const double compact = 600;

  /// 中等：手机横屏 / 小平板，使用窄侧边栏。
  static const double medium = 900;

  /// 扩展：平板横屏 / 桌面，使用宽侧边栏 + 多列网格。
  static const double expanded = 1300;
}

/// 平台判断。本项目不支持 Web，因此可以放心使用 `dart:io`。
class PlatformInfo {
  PlatformInfo._();

  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  static bool get isWindows => Platform.isWindows;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isLinux => Platform.isLinux;
  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;

  static String get label {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return '未知平台';
  }
}

extension ResponsiveContext on BuildContext {
  Size get screen => MediaQuery.sizeOf(this);

  double get screenWidth => screen.width;

  /// 手机竖屏布局。
  bool get isCompact => screenWidth < Breakpoints.compact;

  /// 平板 / 小窗。
  bool get isMedium =>
      screenWidth >= Breakpoints.compact && screenWidth < Breakpoints.medium;

  /// 桌面 / 大平板。
  bool get isExpanded => screenWidth >= Breakpoints.medium;

  /// 是否使用侧边导航栏（否则用底部导航栏）。
  bool get useRail => screenWidth >= Breakpoints.compact;

  /// 海报网格列数。
  int get gridColumns {
    if (screenWidth >= Breakpoints.expanded) return 6;
    if (screenWidth >= Breakpoints.medium) return 5;
    if (screenWidth >= Breakpoints.compact) return 4;
    return 3;
  }

  /// 详情页左右两栏的阈值。
  bool get useDetailTwoPane => screenWidth >= Breakpoints.medium;

  /// 播放页是否为"影院模式"（桌面端用窗口，移动端全屏）。
  bool get useTheaterMode => !PlatformInfo.isDesktop;
}
