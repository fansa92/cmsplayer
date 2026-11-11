import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'package:cms_player/ui/player/player_environment.dart';

/// 可手动触发的一次性定时器。
///
/// [PlayerController] 的开播兜底与降级提示都用 Timer，测试里若挂真定时器，
/// 用例结束时会报 "A Timer is still pending"。换成这个类后既不会挂住，
/// 还能精确验证「20 秒后收起转圈」「4 秒后收起提示」这两条分支。
class FakeTimer implements Timer {
  FakeTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  bool _active = true;
  bool _fired = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _fired ? 1 : 0;

  @override
  void cancel() {
    _active = false;
  }

  /// 手动到点。已经取消或触发过的不再执行（与真 Timer 一致）。
  void fire() {
    if (!_active || _fired) return;
    _fired = true;
    _active = false;
    callback();
  }
}

/// 内存版 media_kit 播放内核。
///
/// `Player(platformPlayer: ...)` 是 media_kit 官方留的注入口，传入后构造
/// 过程完全不会创建 NativePlayer / 触碰 libmpv。这里通过父类暴露的
/// StreamController 手动推流，就能驱动 [PlayerController] 的全部状态绑定。
class FakePlatformPlayer extends PlatformPlayer {
  FakePlatformPlayer() : super(configuration: const PlayerConfiguration());

  /// 每次 open 拿到的地址。
  final List<String> opens = <String>[];
  final List<Duration> seeks = <Duration>[];
  final List<double> rates = <double>[];
  int playOrPauseCalls = 0;
  bool disposed = false;

  /// 让第 [openFailureAt] 次 open 抛异常（1 起算），用来测「打开即失败」。
  int? openFailureAt;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final String uri = (playable as Media).uri;
    opens.add(uri);
    if (openFailureAt == opens.length) {
      throw StateError('open failed: $uri');
    }
  }

  @override
  Future<void> setRate(double rate) async {
    rates.add(rate);
  }

  @override
  Future<void> seek(Duration duration) async {
    seeks.add(duration);
  }

  @override
  Future<void> playOrPause() async {
    playOrPauseCalls++;
  }

  @override
  // ignore: must_call_super
  Future<void> dispose() async {
    // 不关闭 controller：dispose 之后测试里偶尔还会推一条流做断言。
    // 这些 controller 随测试进程一起回收，不需要显式释放。
    disposed = true;
  }

  // ------------------------------------------------------------ 推流

  void emitPosition(Duration v) => positionController.add(v);
  void emitDuration(Duration v) => durationController.add(v);
  void emitPlaying(bool v) => playingController.add(v);
  void emitBuffering(bool v) => bufferingController.add(v);
  void emitCompleted(bool v) => completedController.add(v);
  void emitRate(double v) => rateController.add(v);
  void emitVolume(double v) => volumeController.add(v);
  void emitError(String v) => errorController.add(v);
  void emitWidth(int? v) => widthController.add(v);
  void emitHeight(int? v) => heightController.add(v);
  void emitTracks(Tracks v) => tracksController.add(v);
  void emitVideoParams(VideoParams v) => videoParamsController.add(v);
  void emitAudioParams(AudioParams v) => audioParamsController.add(v);
}

/// 一套完整的测试环境：内存播放内核 + 可控时钟 / 音量 / 亮度 / 定时器。
class FakePlayerRig {
  FakePlayerRig({DateTime? start}) : clock = start ?? DateTime(2026, 1, 1, 12);

  final FakePlatformPlayer platform = FakePlatformPlayer();

  DateTime clock;
  double systemVolume = 0.4;
  double brightness = 0.6;
  bool readVolumeThrows = false;
  bool writeVolumeThrows = false;
  bool readBrightnessThrows = false;
  int resetBrightnessCalls = 0;
  int disposedPlayers = 0;

  final List<double> volumeWrites = <double>[];
  final List<double> brightnessWrites = <double>[];
  final List<FakeTimer> timers = <FakeTimer>[];

  late final PlayerEnvironment environment = PlayerEnvironment(
    createPlayer: () => Player(platformPlayer: platform),
    readVolume: () async {
      if (readVolumeThrows) throw StateError('no volume plugin');
      return systemVolume;
    },
    writeVolume: (double v) async {
      if (writeVolumeThrows) throw StateError('no volume plugin');
      systemVolume = v;
      volumeWrites.add(v);
    },
    readBrightness: () async {
      if (readBrightnessThrows) throw StateError('no brightness plugin');
      return brightness;
    },
    writeBrightness: (double v) async {
      brightness = v;
      brightnessWrites.add(v);
    },
    resetBrightness: () async {
      resetBrightnessCalls++;
    },
    now: () => clock,
    createTimer: (Duration d, void Function() f) {
      final FakeTimer timer = FakeTimer(d, f);
      timers.add(timer);
      return timer;
    },
  );

  /// 推进微任务，让 broadcast stream 与 fire-and-forget 的异步流程落地。
  ///
  /// [PlayerController.dispose] 会 fire-and-forget 地写一次播放记录；真实
  /// 文件 I/O 不在微任务队列里，所以最后一轮要留出一点真实时间，否则
  /// `useIsolatedStores` 删临时目录时会撞上 Windows 的文件锁。
  Future<void> settle([int rounds = 8]) async {
    for (int i = 0; i < rounds; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  /// 先确保时长已落地，再推进度。
  ///
  /// duration 与 position 是两条独立的 broadcast stream，各自还套了一层
  /// distinct 变换；一次性连续 add 时，高负载下 position 可能先被处理，
  /// 于是 _maybeWriteHistory / _maybeAutoResume 会误判「还没有时长」。
  /// 真实播放器总是先探测到时长才开始报进度，这里显式复现这个顺序。
  Future<void> emitProgress(Duration duration, Duration position) async {
    platform.emitDuration(duration);
    await settle(4);
    platform.emitPosition(position);
    await settle(4);
  }

  /// 触发所有尚未取消的定时器。
  void fireTimers() {
    for (final FakeTimer t in List<FakeTimer>.of(timers)) {
      t.fire();
    }
  }

  /// 只触发指定时长的定时器（例如只到「降级提示」的 4 秒）。
  void fireTimersOf(Duration duration) {
    for (final FakeTimer t in List<FakeTimer>.of(timers)) {
      if (t.duration == duration) t.fire();
    }
  }
}
