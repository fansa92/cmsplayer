import 'package:flutter/foundation.dart';

import '../../data/models/play_task.dart';

/// [PlayerControls] 对播放器状态层的依赖面。
///
/// 控制层本身只关心「读状态 + 发命令」，不需要知道底下是 media_kit 还是别的
/// 实现。抽成接口后，键盘映射、手势分发、自动隐藏这些纯交互逻辑就能在
/// widget 测试里用一个内存假体驱动，而不必初始化原生播放器插件。
///
/// 生产环境传入的一直是 [PlayerController]，行为没有任何变化。
abstract class PlayerControlsBinding implements Listenable {
  // ---------------------------------------------------------------- 状态
  PlayTask get task;
  Duration get position;
  Duration get duration;
  double get positionRatio;
  double get seekRatio;
  double get rate;
  double get gestureVolume;
  double get gestureBrightness;
  String get fitLabel;

  bool get playing;
  bool get buffering;
  bool get starting;
  bool get locked;
  bool get seeking;
  bool get adjustingVolume;
  bool get adjustingBrightness;

  String? get error;
  String? get fallbackTrying;
  String? get fallbackNotice;
  String? get resolutionLabel;
  String? get fpsLabel;
  String? get videoCodec;
  String? get videoDecoder;
  String? get pixelFormat;
  String? get audioCodec;
  String? get audioChannels;
  int? get audioSampleRate;

  // ---------------------------------------------------------------- 命令
  Future<void> togglePlay();
  Future<void> seek(Duration target);
  Future<void> seekBy(Duration delta);
  Future<void> setRate(double value);
  Future<double?> stepVolume(double deltaPercent);
  Future<void> cycleFit();
  void toggleLock();
  Future<void> next();
  Future<void> previous();
  Future<void> selectEpisode(int lineIndex, int episodeIndex);
  Future<void> retry();

  void startSeek();
  void updateSeek(Duration delta);
  void commitSeek();
  void cancelSeek();

  Future<void> startVerticalGesture({required bool isVolume});
  Future<void> updateVerticalGesture(double delta);
  Future<void> endVerticalGesture();
}
