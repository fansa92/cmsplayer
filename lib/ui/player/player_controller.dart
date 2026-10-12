import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../core/utils/text_utils.dart';
import '../../data/models/play_line.dart';
import '../../data/models/play_record.dart';
import '../../data/models/play_task.dart';
import '../../state/app_state.dart';
import '../../state/history_store.dart';

/// 播放器状态与 media_kit 的桥接层。
///
/// 职责：
///  * 把 media_kit 的流式状态转成 [ChangeNotifier]，让控制栏用普通方式重建；
///  * 解析播放地址（直链 / 解析接口 / 相对地址补全）；
///  * 续播、自动下一集、播放记录节流写入；
///  * 手势过程中的音量 / 亮度 / 进度预览。
class PlayerController extends ChangeNotifier {
  PlayerController({
    required PlayTask task,
    required AppState app,
    required HistoryStore history,
  })  : _app = app,
        _history = history,
        _task = task {
    _player = Player();
    _videoController = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: app.hardwareDecode,
      ),
    );
    _rate = app.defaultRate;
    _bindStreams();
    _openCurrent();
  }

  final AppState _app;
  final HistoryStore _history;

  PlayTask _task;
  PlayTask get task => _task;

  late final Player _player;
  Player get player => _player;
  late final VideoController _videoController;
  VideoController get videoController => _videoController;

  final List<StreamSubscription<Object?>> _subs = <StreamSubscription<Object?>>[];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;
  String? _error;
  bool _starting = true;

  /// 兜底定时器：网络卡死时也要把控制栏放出来，避免无限转圈。
  Timer? _startupTimer;

  double _rate = 1.0;
  double _volume = 100.0;
  bool _locked = false;
  BoxFit _fit = BoxFit.contain;

  bool _seeking = false;
  Duration _seekTarget = Duration.zero;

  bool _adjustingVolume = false;
  bool _adjustingBrightness = false;

  /// 手势进行中的音量 / 亮度取值（0..1）。
  ///
  /// 每次事件都在**上一次的结果**上累加增量。`DragUpdateDetails.primaryDelta`
  /// 是相对上一帧的增量而非整段位移，若写成"起点 + 最后一下的增量"，
  /// 整段滑动就只有最后一帧的幅度生效，表现为拖满屏也几乎没反应。
  double _gestureVolume = 0;
  double _gestureBrightness = 0;

  /// 最近一次已知的**系统**音量（0..100），未知时为 -1。
  ///
  /// 手势与键盘调的是同一个东西（系统音量），共用这份缓存读数，
  /// 否则会出现"手势显示 70%、键盘显示 100%"两套互相矛盾的数字。
  double _systemVolume = -1;

  // 视频 / 音频的流信息，供"视频信息"面板展示。全部允许为 null：
  // mpv 要等文件真正打开并探测完才给得出，纯音频或者探测失败时这些字段
  // 一直是 null，面板里对应那几行直接不显示。
  int? _videoWidth;
  int? _videoHeight;
  double? _videoFps;
  String? _videoCodec;
  String? _videoDecoder;
  String? _pixelFormat;
  String? _audioCodec;
  String? _audioChannels;
  int? _audioSampleRate;

  bool _disposed = false;
  DateTime _lastHistoryWrite = DateTime.fromMillisecondsSinceEpoch(0);
  bool _resumeApplied = false;

  // ---------------------------------------------------------------- 状态

  Duration get position => _seeking ? _seekTarget : _position;
  Duration get rawPosition => _position;
  Duration get duration => _duration;
  bool get playing => _playing;
  bool get buffering => _buffering;
  bool get completed => _completed;
  String? get error => _error;
  bool get starting => _starting;
  double get rate => _rate;
  double get volume => _volume;
  bool get locked => _locked;
  BoxFit get fit => _fit;
  bool get seeking => _seeking;

  double get positionRatio {
    if (_duration.inMilliseconds <= 0) return 0;
    return (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
  }

  double get seekRatio {
    if (_duration.inMilliseconds <= 0) return 0;
    return (_seekTarget.inMilliseconds / _duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  String get fitLabel {
    switch (_fit) {
      case BoxFit.cover:
        return '裁剪';
      case BoxFit.fill:
        return '拉伸';
      default:
        return '适应';
    }
  }

  // ---------------------------------------------------------------- 流信息

  int? get videoWidth => _videoWidth;
  int? get videoHeight => _videoHeight;
  double? get videoFps => _videoFps;
  String? get videoCodec => _videoCodec;
  String? get videoDecoder => _videoDecoder;
  String? get pixelFormat => _pixelFormat;
  String? get audioCodec => _audioCodec;
  String? get audioChannels => _audioChannels;
  int? get audioSampleRate => _audioSampleRate;

  /// 清晰度，例如 `1920x1080`。
  ///
  /// 优先用 stream 的 width / height：那是解码后的实际尺寸；track 上那对
  /// demux-w / demux-h 是容器里标的标称值，遇到旋转 90 度的竖屏视频会和
  /// 实际显示的宽高对不上。
  String? get resolutionLabel {
    final int? w = _videoWidth;
    final int? h = _videoHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return '${w}x$h';
  }

  /// 帧率，去掉无意义的小数尾巴（23.976 保留，30.000 变成 30）。
  String? get fpsLabel {
    final double? fps = _videoFps;
    if (fps == null || fps <= 0) return null;
    return fps.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  /// 结束"正在准备"状态。
  ///
  /// [_starting] 只在 [_openCurrent] 里置 true，此前只有出错分支会把它置回
  /// false；播放一旦正常启动就再没人清理它。而控制层是
  /// `buffering || starting` 就渲染中央转圈、否则才渲染播放/暂停按钮，
  /// 所以这个字段卡住会造成两个现象：转圈永远不停、暂停按钮永远不出现。
  void _clearStarting(String reason) {
    if (!_starting) return;
    _starting = false;
    _startupTimer?.cancel();
    _startupTimer = null;
    AppLog.d('Player', 'starting cleared by $reason');
  }

  // ---------------------------------------------------------------- 绑定

  /// 清空上一集遗留的流信息。
  ///
  /// 不清的话，切换到一条没有视频轨的源时，面板会继续显示上一条片子的
  /// 分辨率和编码 —— 比干脆不显示更误导。
  void _resetStreamInfo() {
    _videoWidth = null;
    _videoHeight = null;
    _videoFps = null;
    _videoCodec = null;
    _videoDecoder = null;
    _pixelFormat = null;
    _audioCodec = null;
    _audioChannels = null;
    _audioSampleRate = null;
  }

  void _bindStreams() {
    _subs.add(_player.stream.position.listen((Duration p) {
      _position = p;
      _maybeAutoResume();
      _maybeWriteHistory();
      _emit();
    }));
    _subs.add(_player.stream.duration.listen((Duration d) {
      _duration = d;
      // 拿到时长说明媒体已加载完毕，"正在准备"到此为止。
      if (d > Duration.zero) _clearStarting('duration');
      _emit();
    }));
    _subs.add(_player.stream.playing.listen((bool p) {
      _playing = p;
      if (p) _clearStarting('playing');
      _emit();
    }));
    _subs.add(_player.stream.buffering.listen((bool b) {
      _buffering = b;
      _emit();
    }));
    _subs.add(_player.stream.completed.listen((bool c) {
      _completed = c;
      if (c) _onCompleted();
      _emit();
    }));
    _subs.add(_player.stream.rate.listen((double r) {
      _rate = r;
      _emit();
    }));
    _subs.add(_player.stream.volume.listen((double v) {
      _volume = v;
      _emit();
    }));
    _subs.add(_player.stream.error.listen((String e) {
      AppLog.e('Player', 'media error: $e');
      if (_disposed) return;
      _error = e.isEmpty ? '播放失败' : e;
      _starting = false;
      _emit();
    }));

    // 视频信息。这几个流只在文件打开、探测完成后各触发一次，
    // 切集时也会重新来一遍，所以不会造成控制栏跟着播放持续重建。
    _subs.add(_player.stream.width.listen((int? w) {
      _videoWidth = w;
      _emit();
    }));
    _subs.add(_player.stream.height.listen((int? h) {
      _videoHeight = h;
      _emit();
    }));
    // 注意：要用复数 tracks（本文件里可用的轨），不能用单数 track。
    // 单数 track 只有在显式调用过 setVideoTrack / setAudioTrack 后才会带上
    // codec 等属性，正常播放时它一直是空的 VideoTrack('auto', null, null)，
    // 结果就是面板里编码 / 音频格式那几行永远不显示。
    _subs.add(_player.stream.tracks.listen((Tracks ts) {
      final VideoTrack? v = _firstRealVideo(ts.video);
      final AudioTrack? a = _firstRealAudio(ts.audio);
      _videoFps = v?.fps ?? _videoFps;
      _videoCodec = v?.codec ?? _videoCodec;
      _videoDecoder = v?.decoder ?? _videoDecoder;
      _audioCodec = a?.codec ?? _audioCodec;
      _audioChannels = a?.channels ?? _channelsOf(a) ?? _audioChannels;
      _audioSampleRate = a?.samplerate ?? _audioSampleRate;
      _emit();
    }));
    _subs.add(_player.stream.videoParams.listen((VideoParams p) {
      _pixelFormat = p.pixelformat;
      _emit();
    }));
    // 音频参数兜底：有些流 track-list 里不带 demux-channels / demux-samplerate，
    // 但 audio-params 一定有（它是解码后的实际输出参数）。
    _subs.add(_player.stream.audioParams.listen((AudioParams p) {
      _audioChannels = _audioChannels ?? p.hrChannels ?? p.channels;
      _audioSampleRate = _audioSampleRate ?? p.sampleRate;
      _emit();
    }));
  }

  // ---------------- tracks 选轨辅助 ----------------
  //
  // 复数 tracks 的头两项固定是 'auto' / 'no' 两个占位轨（codec 为 null），
  // 真正的轨从下标 2 开始。挑第一条带 codec 的即可。

  static VideoTrack? _firstRealVideo(List<VideoTrack> list) {
    for (final VideoTrack t in list) {
      if (t.id == 'auto' || t.id == 'no') continue;
      if (t.codec != null && t.codec!.isNotEmpty) return t;
    }
    return null;
  }

  static AudioTrack? _firstRealAudio(List<AudioTrack> list) {
    for (final AudioTrack t in list) {
      if (t.id == 'auto' || t.id == 'no') continue;
      if (t.codec != null && t.codec!.isNotEmpty) return t;
    }
    return null;
  }

  /// 声道数兜底：demux-channels 缺失时用 demux-channel-count 拼一个可读串。
  static String? _channelsOf(AudioTrack? t) {
    final int? n = t?.channelscount;
    if (n == null || n <= 0) return null;
    return '$n';
  }

  // ---------------------------------------------------------------- 打开

  /// 解析出最终交给 libmpv 的地址。
  String? resolvePlayUrl(PlayEpisode episode) {
    final String raw = episode.url.trim();
    if (raw.isEmpty) return null;

    final String absolute = resolveUrl(raw, base: _task.source.api) ?? raw;
    if (isDirectPlayable(absolute)) return absolute;

    final String parse = _task.source.parseApi.trim();
    if (parse.isEmpty) return absolute;
    final String encoded = Uri.encodeComponent(absolute);
    return parse.contains('{url}')
        ? parse.replaceAll('{url}', encoded)
        : '$parse$encoded';
  }

  Future<void> _openCurrent() async {
    final PlayEpisode? episode = _task.episode;
    if (episode == null) {
      _error = '没有可播放的地址';
      _starting = false;
      _emit();
      return;
    }

    final String? url = resolvePlayUrl(episode);
    if (url == null) {
      _error = '该集没有有效的播放地址';
      _starting = false;
      _emit();
      return;
    }

    _error = null;
    _starting = true;
    _startupTimer?.cancel();
    _startupTimer = null;
    _completed = false;
    _resumeApplied = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _resetStreamInfo();
    _emit();

    AppLog.d('Player', 'open $url');
    try {
      await _player.open(
        Media(url, httpHeaders: _task.source.headers),
        play: true,
      );
      await _player.setRate(_rate);
      // 正常情况下 playing / duration 流会立刻清掉 _starting；
      // 这里再挂一道兜底，防止流不触发时控制栏被永久遮住。
      _startupTimer?.cancel();
      _startupTimer = Timer(K.startupTimeout, () {
        if (_starting) {
          _clearStarting('timeout');
          _emit();
        }
      });
    } on Object catch (e) {
      AppLog.e('Player', 'open failed: $e');
      if (_disposed) return;
      _error = '无法打开视频：$e';
      _starting = false;
      _emit();
    }
  }

  /// 首次拿到时长时应用续播位置。
  void _maybeAutoResume() {
    if (_resumeApplied || _disposed) return;
    if (!_app.resumePlayback) {
      _resumeApplied = true;
      return;
    }
    if (_duration.inMilliseconds <= 0) return;
    _resumeApplied = true;

    final PlayRecord? record = _history.byKey(_task.recordKey);
    if (record == null) return;
    if (record.lineIndex != _task.lineIndex ||
        record.episodeIndex != _task.episodeIndex) {
      return;
    }
    final int pos = record.positionMs;
    if (pos <= K.resumeSeekThreshold.inMilliseconds) return;
    if (record.durationMs > 0 &&
        pos / record.durationMs >= K.finishRatio) {
      return;
    }
    _player.seek(Duration(milliseconds: pos));
    AppLog.d('Player', 'resume at ${pos}ms');
  }

  void _onCompleted() {
    _writeHistory(force: true, finished: true);
    if (_app.autoNextEpisode && _task.hasNext) {
      next();
    }
  }

  // ---------------------------------------------------------------- 控制

  Future<void> togglePlay() => _player.playOrPause();

  Future<void> seek(Duration target) async {
    if (_duration.inMilliseconds <= 0) return;
    final int maxMs = _duration.inMilliseconds;
    final int ms = target.inMilliseconds.clamp(0, maxMs);
    await _player.seek(Duration(milliseconds: ms));
  }

  Future<void> seekBy(Duration delta) =>
      seek(_position + delta);

  Future<void> setRate(double value) async {
    _rate = value;
    _emit();
    await _player.setRate(value);
  }

  /// 音量步进，供键盘使用。[deltaPercent] 为百分点，例如 `5` / `-5`。
  ///
  /// 调的是**系统**音量，与手势 [startVerticalGesture] 同一条通路
  /// （`volume_controller` 在本项目支持的五个平台上都可用），
  /// 而不是 media_kit 的播放器音量 —— 后者会和手势读数对不上。
  ///
  /// 返回应用后的音量（0..100），平台不支持时返回 null，调用方据此不显示提示。
  Future<double?> stepVolume(double deltaPercent) async {
    try {
      final double base = _systemVolume >= 0
          ? _systemVolume / 100
          : await VolumeController.instance.getVolume();
      final double next = (base + deltaPercent / 100).clamp(0.0, 1.0);
      await VolumeController.instance.setVolume(next);
      _systemVolume = next * 100;
      _emit();
      return _systemVolume;
    } on Object catch (e) {
      AppLog.d('Player', 'stepVolume failed: $e');
      return null;
    }
  }

  Future<void> cycleFit() async {
    switch (_fit) {
      case BoxFit.contain:
        _fit = BoxFit.cover;
        break;
      case BoxFit.cover:
        _fit = BoxFit.fill;
        break;
      default:
        _fit = BoxFit.contain;
    }
    _emit();
  }

  void toggleLock() {
    _locked = !_locked;
    _emit();
  }

  Future<void> next() => _switchTo(_task.lineIndex, _task.episodeIndex + 1);

  Future<void> previous() => _switchTo(_task.lineIndex, _task.episodeIndex - 1);

  Future<void> selectEpisode(int lineIndex, int episodeIndex) =>
      _switchTo(lineIndex, episodeIndex);

  Future<void> _switchTo(int lineIndex, int episodeIndex) async {
    final List<PlayLine> lines = _task.item.playLines;
    if (lineIndex < 0 || lineIndex >= lines.length) return;
    final int count = lines[lineIndex].episodes.length;
    if (episodeIndex < 0 || episodeIndex >= count) return;

    _task = _task.copyWith(lineIndex: lineIndex, episodeIndex: episodeIndex);
    _emit();
    await _openCurrent();
  }

  Future<void> retry() => _openCurrent();

  // ---------------------------------------------------------------- 手势

  void startSeek() {
    _seeking = true;
    _seekTarget = _position;
    _emit();
  }

  void updateSeek(Duration delta) {
    if (!_seeking) return;
    if (_duration.inMilliseconds <= 0) return;
    // delta 是"相对上一帧"的增量，必须累加到上一次的目标上。
    // 之前写成 `_position + delta`，整段拖动只按最后一下的幅度生效，
    // 拖满屏进度条也几乎不动。
    final int ms = (_seekTarget + delta)
        .inMilliseconds
        .clamp(0, _duration.inMilliseconds);
    _seekTarget = Duration(milliseconds: ms);
    _emit();
  }

  void commitSeek() async {
    if (!_seeking) return;
    final Duration target = _seekTarget;
    _seeking = false;
    _emit();
    await seek(target);
  }

  void cancelSeek() {
    _seeking = false;
    _emit();
  }

  /// [isVolume] 为 true 表示调右侧音量，false 表示调左侧亮度。
  Future<void> startVerticalGesture({required bool isVolume}) async {
    if (_adjustingVolume || _adjustingBrightness) return;
    try {
      if (isVolume) {
        final double v = await VolumeController.instance.getVolume();
        _gestureVolume = v;
        _systemVolume = v * 100; // 与键盘步进共享读数
        _adjustingVolume = true;
      } else {
        _gestureBrightness = await ScreenBrightness.instance.application;
        _adjustingBrightness = true;
      }
    } on Object catch (e) {
      AppLog.d('Player', 'vertical gesture unsupported: $e');
    }
    _emit();
  }

  /// [delta] 是自上一帧以来的位移（归一化到 0..1），必须累加到当前值上。
  Future<void> updateVerticalGesture(double delta) async {
    if (_adjustingVolume) {
      _gestureVolume = (_gestureVolume + delta).clamp(0.0, 1.0);
      try {
        await VolumeController.instance.setVolume(_gestureVolume);
      } on Object {
        // 平台不支持时静默忽略。
      }
      _emit();
    } else if (_adjustingBrightness) {
      _gestureBrightness = (_gestureBrightness + delta).clamp(0.0, 1.0);
      try {
        await ScreenBrightness.instance.setApplicationScreenBrightness(
          _gestureBrightness,
        );
      } on Object {
        // 平台不支持时静默忽略。
      }
      _emit();
    }
  }

  Future<void> endVerticalGesture() async {
    _adjustingVolume = false;
    _adjustingBrightness = false;
    _emit();
  }

  bool get adjustingVolume => _adjustingVolume;
  bool get adjustingBrightness => _adjustingBrightness;
  double get gestureVolume => _gestureVolume;
  double get gestureBrightness => _gestureBrightness;

  /// 系统音量（0..100），-1 表示尚未读到过。
  double get systemVolume => _systemVolume;

  // ---------------------------------------------------------------- 历史

  void _maybeWriteHistory() {
    if (_disposed) return;
    if (_duration.inMilliseconds <=
        K.minResumeSource.inMilliseconds) {
      return;
    }
    final DateTime now = DateTime.now();
    if (now.difference(_lastHistoryWrite) < K.historyThrottle) return;
    _lastHistoryWrite = now;
    _writeHistory();
  }

  void _writeHistory({bool force = false, bool finished = false}) {
    if (_disposed && !force) return;
    final PlayEpisode? episode = _task.episode;
    final PlayLine? line = _task.line;
    if (episode == null || line == null) return;

    final int durationMs = _duration.inMilliseconds;
    final int positionMs = finished
        ? durationMs
        : _position.inMilliseconds;
    if (!force && durationMs <= 0) return;

    _history.upsert(
      PlayRecord(
        key: _task.recordKey,
        sourceId: _task.source.id,
        sourceName: _task.source.name,
        vodId: '${_task.item.id}',
        vodName: _task.item.name,
        vodPic: _task.item.pic,
        typeName: _task.item.typeName,
        lineIndex: _task.lineIndex,
        episodeIndex: _task.episodeIndex,
        lineName: line.name,
        episodeName: episode.name,
        positionMs: positionMs,
        durationMs: durationMs,
        finished:
            finished || (durationMs > 0 && positionMs / durationMs >= K.finishRatio),
        updatedAt: DateTime.now(),
      ),
    );
  }

  // ---------------------------------------------------------------- 释放

  Future<void> restoreBrightness() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } on Object {
      // 忽略。
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _startupTimer?.cancel();
    _startupTimer = null;
    for (final StreamSubscription<Object?> sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    _writeHistory(force: true);
    unawaited(_player.dispose());
    unawaited(restoreBrightness());
    super.dispose();
  }
}
