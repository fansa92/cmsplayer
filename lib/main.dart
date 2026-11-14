import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/deep_link.dart';
import 'core/storage/app_dirs.dart';
import 'core/storage/settings_store.dart';
import 'core/utils/responsive.dart';
import 'ui/shell/desktop_shell.dart';
import 'ui/shell/tray_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 命令行 / 协议唤起带来的导入请求：先记下，等外壳挂载后再处理。
  DeepLink.handleArgs(args);

  // media_kit 原生库必须在使用前初始化，且必须在 runApp 之前调用。
  MediaKit.ensureInitialized();

  // 锁定方向策略由播放页自行控制，这里只放开允许的方向集合。
  await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final SettingsStore settings = SettingsStore();
  await settings.init();
  await AppDirs.init();

  // 桌面窗口：先把尺寸 / 位置 / 防误关准备好，再挂界面。
  if (PlatformInfo.isDesktop) {
    await DesktopShell.init(settings);
  }

  runApp(CmsPlayerApp(settings: settings));

  // 托盘放在 runApp 之后：它不该挡启动，失败也只是少一个入口。
  if (PlatformInfo.isDesktop) {
    unawaited(TrayService.instance.start(
      onShow: DesktopShell.show,
      onQuit: DesktopShell.quit,
    ));
  }
}
