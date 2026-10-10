import 'package:window_manager/window_manager.dart';

import '../../core/logger.dart';
import '../../core/utils/responsive.dart';

/// 桌面端窗口全屏控制。
///
/// 播放页本身在移动端走沉浸式全屏（系统 UI 隐藏），但桌面端"全屏"指的是
/// **操作系统级的窗口全屏**，Flutter 没有内置 API，只能交给 `window_manager`。
///
/// 这里的每个方法在非桌面平台都是安全的空操作，调用方不必到处判平台。
class PlayerWindow {
  PlayerWindow._();

  static Future<void> _ensure() async {
    if (!PlatformInfo.isDesktop) return;
    await windowManager.ensureInitialized();
  }

  /// 当前窗口是否全屏。
  static Future<bool> isFullScreen() async {
    if (!PlatformInfo.isDesktop) return false;
    try {
      await _ensure();
      return await windowManager.isFullScreen();
    } on Object catch (e) {
      AppLog.d('PlayerWindow', 'isFullScreen failed: $e');
      return false;
    }
  }

  /// 设置窗口全屏。
  static Future<void> setFullScreen(bool value) async {
    if (!PlatformInfo.isDesktop) return;
    try {
      await _ensure();
      await windowManager.setFullScreen(value);
    } on Object catch (e) {
      AppLog.d('PlayerWindow', 'setFullScreen($value) failed: $e');
    }
  }

  /// 切换窗口全屏，返回切换后的状态。
  static Future<bool> toggleFullScreen() async {
    if (!PlatformInfo.isDesktop) return false;
    try {
      await _ensure();
      final bool next = !(await windowManager.isFullScreen());
      await windowManager.setFullScreen(next);
      return next;
    } on Object catch (e) {
      AppLog.d('PlayerWindow', 'toggleFullScreen failed: $e');
      return false;
    }
  }
}
