import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../core/utils/responsive.dart';

/// 桌面端窗口控制：全屏 + 迷你悬浮窗。
///
/// 播放页本身在移动端走沉浸式全屏（系统 UI 隐藏），但桌面端"全屏"指的是
/// **操作系统级的窗口全屏**，Flutter 没有内置 API，只能交给 `window_manager`。
///
/// 这里的每个方法在非桌面平台都是安全的空操作，调用方不必到处判平台。
class PlayerWindow {
  PlayerWindow._();

  /// 迷你窗状态。用 ValueNotifier 是因为状态层没有 ChangeNotifier 可挂，
  /// 而顶栏需要在进出迷你窗时重建。
  static final ValueNotifier<bool> mini = ValueNotifier<bool>(false);

  static bool get miniActive => mini.value;

  /// 进入迷你窗前记住的位置与尺寸，还原时用。
  static Rect? _restoreBounds;

  /// 测试用的平台替身：window_manager 走 MethodChannel，widget 测试里
  /// 没有宿主窗口。设置后优先于真实实现，生产环境始终为 null。
  @visibleForTesting
  static Future<bool> Function()? isFullScreenForTest;

  @visibleForTesting
  static Future<void> Function(bool value)? setFullScreenForTest;

  @visibleForTesting
  static Future<bool> Function()? toggleFullScreenForTest;

  @visibleForTesting
  static Future<void> Function(bool value)? setMiniForTest;

  static Future<void> _ensure() async {
    if (!PlatformInfo.isDesktop) return;
    await windowManager.ensureInitialized();
  }

  /// 当前窗口是否全屏。
  static Future<bool> isFullScreen() async {
    final Future<bool> Function()? test = isFullScreenForTest;
    if (test != null) return test();
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
    final Future<void> Function(bool)? test = setFullScreenForTest;
    if (test != null) return test(value);
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
    final Future<bool> Function()? test = toggleFullScreenForTest;
    if (test != null) return test();
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

  /// 进入 / 退出迷你悬浮窗。
  ///
  /// 迷你窗 = 置顶 + 缩小到固定尺寸，位置沿用当前窗口左上角，不抢焦点、
  /// 也不动任务栏——用户还要靠任务栏切回来。全屏状态下进入会先退出全屏。
  static Future<void> setMini(bool value) async {
    if (mini.value == value) return;
    final Future<void> Function(bool)? test = setMiniForTest;
    if (test != null) {
      await test(value);
      mini.value = value;
      return;
    }
    if (!PlatformInfo.isDesktop) return;
    try {
      await _ensure();
      if (value) {
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
        }
        final Rect bounds = await windowManager.getBounds();
        _restoreBounds = bounds;
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setBounds(
          Rect.fromLTWH(
            bounds.left,
            bounds.top,
            K.miniWindowWidth,
            K.miniWindowHeight,
          ),
        );
        mini.value = true;
        AppLog.d('PlayerWindow', 'mini on from $bounds');
      } else {
        await windowManager.setAlwaysOnTop(false);
        final Rect? restore = _restoreBounds;
        if (restore != null) await windowManager.setBounds(restore);
        _restoreBounds = null;
        mini.value = false;
        AppLog.d('PlayerWindow', 'mini off');
      }
    } on Object catch (e) {
      AppLog.d('PlayerWindow', 'setMini($value) failed: $e');
    }
  }

  /// 切换迷你窗，返回切换后的状态。
  static Future<bool> toggleMini() async {
    await setMini(!mini.value);
    return mini.value;
  }

  @visibleForTesting
  static void resetForTest() {
    isFullScreenForTest = null;
    setFullScreenForTest = null;
    toggleFullScreenForTest = null;
    setMiniForTest = null;
    _restoreBounds = null;
    mini.value = false;
  }
}
