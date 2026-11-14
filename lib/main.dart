import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/deep_link.dart';
import 'core/storage/app_dirs.dart';
import 'core/storage/settings_store.dart';

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

  runApp(CmsPlayerApp(settings: settings));
}
