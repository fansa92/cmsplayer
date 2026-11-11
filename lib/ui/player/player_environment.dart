import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

/// [PlayerController] 与「外部世界」之间的一层薄封装。
///
/// 状态机本身（降级链、续播、自动下一集、进度节流、手势累加）是纯 Dart
/// 逻辑，但要验证它就得能控制四样东西：media_kit 的播放内核、系统音量 /
/// 亮度、当前时间、以及一次性定时器。把它们集中在这里后，单元测试只要
/// 换掉这一个 [PlayerController.environment]，就能在内存里驱动整条状态机，
/// 完全不必初始化 libmpv 或触碰任何平台通道。
///
/// 生产环境始终使用 [PlayerEnvironment.production]，行为与改造前一致。
class PlayerEnvironment {
  PlayerEnvironment({
    required this.createPlayer,
    required this.readVolume,
    required this.writeVolume,
    required this.readBrightness,
    required this.writeBrightness,
    required this.resetBrightness,
    required this.now,
    required this.createTimer,
  });

  /// 创建播放内核。生产是 `Player()`；测试用
  /// `Player(platformPlayer: FakePlatformPlayer())` —— 这是 media_kit 自己
  /// 暴露的注入口，构造时不会创建任何原生播放器。
  final Player Function() createPlayer;

  /// 系统音量（0..1）。
  final Future<double> Function() readVolume;
  final Future<void> Function(double value) writeVolume;

  /// 应用亮度（0..1）。
  final Future<double> Function() readBrightness;
  final Future<void> Function(double value) writeBrightness;
  final Future<void> Function() resetBrightness;

  /// 当前时间。测试里用可控时钟推进，才能覆盖「8 秒节流」这类分支。
  final DateTime Function() now;

  /// 一次性定时器。测试里换成可手动触发的假定时器，避免 pending Timer。
  final Timer Function(Duration duration, void Function() callback) createTimer;

  /// 生产实现：全部走真实插件。
  static PlayerEnvironment production() => PlayerEnvironment(
        createPlayer: () => Player(),
        readVolume: () => VolumeController.instance.getVolume(),
        writeVolume: (double v) => VolumeController.instance.setVolume(v),
        readBrightness: () => ScreenBrightness.instance.application,
        writeBrightness: (double v) =>
            ScreenBrightness.instance.setApplicationScreenBrightness(v),
        resetBrightness: () =>
            ScreenBrightness.instance.resetApplicationScreenBrightness(),
        now: () => DateTime.now(),
        createTimer: (Duration d, void Function() f) => Timer(d, f),
      );
}
