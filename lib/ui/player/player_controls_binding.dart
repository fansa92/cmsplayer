import 'package:flutter/foundation.dart';

import '../../data/models/play_task.dart';

/// 一条可选音轨。
///
/// 刻意不直接暴露 media_kit 的 `AudioTrack`：控制层只需要「显示什么 + 选哪个」，
/// 把第三方类型挡在接口之外，widget 测试就不用为了构造一条音轨去碰 media_kit。
@immutable
class PlayerAudioTrack {
  const PlayerAudioTrack({
    required this.id,
    required this.label,
    this.codec = '',
  });

  final String id;

  /// 人可读的名字，已经包含序号 / 语言 / 标题里的可用信息。
  final String label;

  /// 原始编码短名（aac / ac-3 …），展示时再翻译。
  final String codec;
}

/// 一条可手动切换的跨源候选。
///
/// 与音轨同理，这里只暴露界面要用的三个字段，把 [SourceFallback] 那套
/// 定位信息留在状态层，弹层不需要知道线路下标是怎么算出来的。
@immutable
class PlayerSourceOption {
  const PlayerSourceOption({
    required this.id,
    required this.label,
    this.episodeLabel = '',
  });

  /// 资源站 id，切换时原样回传。
  final String id;

  /// 资源站名称。
  final String label;

  /// 匹配到的集（含线路名），用于说明「换过去是第几集」。
  final String episodeLabel;
}

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

  // ---------------------------------------------------------------- 音轨
  /// 可切换的音轨。只有一条时控制层不显示切换入口。
  List<PlayerAudioTrack> get audioTracks;

  /// 当前音轨 id，未知时为 null。
  String? get audioId;

  // ---------------------------------------------------------------- 换源
  /// 是否还有别的已启用资源站可换。只有一个源时控制层不显示入口。
  bool get canSwitchSource;

  /// 在其它资源站里找同一部片子的同一集。
  ///
  /// 可能比较慢（每站一次搜索），所以由弹层自己接住加载态。
  Future<List<PlayerSourceOption>> findAlternateSources();

  /// 切换到 [findAlternateSources] 返回的某个候选。
  Future<void> switchToSource(String sourceId);

  // ---------------------------------------------------------------- 定时关闭
  /// 定时关闭的剩余时长，没开定时为 null。
  Duration? get sleepRemaining;

  /// 是否设为「本集播完关」。
  bool get sleepAtEnd;

  // ---------------------------------------------------------------- 片头片尾
  /// 片头结束点（毫秒），0 表示没标记。
  int get introMs;

  /// 片尾开始点（毫秒），0 表示没标记。
  int get outroMs;

  /// 当前进度是否还在片头范围内。
  bool get inIntro;

  bool get autoSkipIntro;
  bool get autoSkipOutro;

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

  Future<void> selectAudioTrack(String id);

  /// 设定定时关闭。[null] 或零时长表示取消。
  Future<void> setSleepTimer(Duration? remaining);
  Future<void> setSleepAtEnd(bool value);

  /// 把当前进度记为片头结束点 / 片尾开始点。
  Future<void> markIntroAt(Duration position);
  Future<void> markOutroAt(Duration position);
  Future<void> clearSkipMarks();

  /// 立刻跳到片头结束点。
  Future<void> skipIntro();

  Future<void> setAutoSkipIntro(bool value);
  Future<void> setAutoSkipOutro(bool value);

  /// 长按临时倍速：按下提速，松开恢复。
  Future<void> startBurstRate();
  Future<void> endBurstRate();

  void startSeek();
  void updateSeek(Duration delta);
  void commitSeek();
  void cancelSeek();

  Future<void> startVerticalGesture({required bool isVolume});
  Future<void> updateVerticalGesture(double delta);
  Future<void> endVerticalGesture();
}
