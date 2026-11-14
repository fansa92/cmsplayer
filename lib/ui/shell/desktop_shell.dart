import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../core/storage/settings_store.dart';
import '../../core/utils/responsive.dart';

/// 桌面窗口的生命周期：初始尺寸、位置记忆、收进托盘、真正退出。
///
/// 所有 window_manager 调用都集中在这里，测试环境（[enabled] 一直是 false）
/// 不会碰任何平台通道。
class DesktopShell {
  DesktopShell._();

  /// 窗口能力是否已经初始化成功。false 时外壳不会挂窗口监听，
  /// 关闭按钮也就保持系统默认行为（直接退出）。
  static bool enabled = false;

  static SettingsStore? _settings;

  /// 主窗口的初始尺寸与下限。下限比迷你窗宽得多，避免被拖成一条缝。
  static const Size initialSize = Size(1240, 800);
  static const Size minimumSize = Size(900, 600);

  /// 在 main 里、runApp 之前调用。
  static Future<void> init(SettingsStore settings) async {
    if (!PlatformInfo.isDesktop) return;
    try {
      await windowManager.ensureInitialized();
      _settings = settings;

      // 不 await：回调要等原生窗口就绪才跑，await 会把启动卡在这里。
      // 等它完成时 Flutter 通常已经画出第一帧，只是窗口还没显示，看不出来。
      unawaited(windowManager.waitUntilReadyToShow(
        const WindowOptions(
          size: initialSize,
          minimumSize: minimumSize,
          center: true,
          title: K.appNameCn,
          skipTaskbar: false,
        ),
        () async {
          try {
            final Rect? saved = settings.windowBounds;
            if (saved != null) {
              await windowManager.setBounds(saved);
            } else {
              await windowManager.center();
            }
            await windowManager.show();
            await windowManager.focus();
          } on Object catch (e) {
            AppLog.d('DesktopShell', 'show failed: $e');
          }
        },
      ));

      // 关闭按钮不再直接销毁窗口：由外壳决定收进托盘还是真退出。
      await windowManager.setPreventClose(true);
      enabled = true;
      AppLog.d('DesktopShell', 'ready, saved bounds=${settings.windowBounds}');
    } on Object catch (e) {
      AppLog.d('DesktopShell', 'init failed: $e');
    }
  }

  /// 记下当前窗口位置与尺寸。最小化 / 全屏状态下的 bounds 没有参考价值，
  /// 那两种情况下直接跳过，保留上一次的正常尺寸。
  static Future<void> saveBounds() async {
    final SettingsStore? settings = _settings;
    if (!enabled || settings == null) return;
    try {
      if (await windowManager.isMinimized()) return;
      if (await windowManager.isFullScreen()) return;
      await settings.setWindowBounds(await windowManager.getBounds());
    } on Object catch (e) {
      AppLog.d('DesktopShell', 'saveBounds failed: $e');
    }
  }

  /// 收进托盘：窗口隐藏，任务栏条目一起去掉，托盘还在。
  static Future<void> hide() async {
    if (!enabled) return;
    try {
      await saveBounds();
      await windowManager.hide();
    } on Object catch (e) {
      AppLog.d('DesktopShell', 'hide failed: $e');
    }
  }

  /// 从托盘叫回来：先 show 再 focus，只 show 的话窗口可能还在后台。
  static Future<void> show() async {
    if (!enabled) return;
    try {
      await windowManager.show();
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.focus();
    } on Object catch (e) {
      AppLog.d('DesktopShell', 'show failed: $e');
    }
  }

  /// 真正退出。托盘菜单与「关闭时不收托盘」都走这里。
  static Future<void> quit() async {
    if (!enabled) return;
    await saveBounds();
    try {
      await windowManager.destroy();
    } on Object catch (e) {
      AppLog.d('DesktopShell', 'destroy failed: $e');
    }
  }

  @visibleForTesting
  static void resetForTest() {
    enabled = false;
    _settings = null;
  }
}
