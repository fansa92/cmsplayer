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
  double _volumeBase = 0;
  double _brightnessBase = 0;
  double _volumeDelta = 0;
  double _brightnessDelta = 0;

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

  /// 音量步进，供键盘 / 滚轮使用。[deltaPercent] 为百分点，例如 `5` / `-5`。
  ///
  /// 与手势用的 [startVerticalGesture] 分开：手势是"绝对比例"（跟手），
  /// 键盘是"相对步进"，两者共用会互相覆盖。
  Future<void> stepVolume(double deltaPercent) async {
    final double v = (_volume + deltaPercent).clamp(0.0, 100.0);
    _volume = v;
    _emit();
    try {
      await _player.setVolume(v);
    } on Object {
      // 平台不支持时静默忽略。
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
    final int ms =
        (_position + delta).inMilliseconds.clamp(0, _duration.inMilliseconds);
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
        _volumeBase = await VolumeController.instance.getVolume();
        _volumeDelta = 0;
        _adjustingVolume = true;
      } else {
        _brightnessBase = await ScreenBrightness.instance.application;
        _brightnessDelta = 0;
        _adjustingBrightness = true;
      }
    } on Object catch (e) {
      AppLog.d('Player', 'vertical gesture unsupported: $e');
    }
    _emit();
  }

  Future<void> updateVerticalGesture(double delta) async {
    if (_adjustingVolume) {
      _volumeDelta = delta;
      final double v = (_volumeBase + delta).clamp(0.0, 1.0);
      try {
        await VolumeController.instance.setVolume(v);
      } on Object {
        // 平台不支持时静默忽略。
      }
      _emit();
    } else if (_adjustingBrightness) {
      _brightnessDelta = delta;
      final double b = (_brightnessBase + delta).clamp(0.0, 1.0);
      try {
        await ScreenBrightness.instance.setApplicationScreenBrightness(b);
      } on Object {
        // 平台不支持时静默忽略。
      }
      _emit();
    }
  }

  Future<void> endVerticalGesture() async {
    _adjustingVolume = false;
    _adjustingBrightness = false;
    _volumeDelta = 0;
    _brightnessDelta = 0;
    _emit();
  }

  bool get adjustingVolume => _adjustingVolume;
  bool get adjustingBrightness => _adjustingBrightness;
  double get gestureVolume => (_volumeBase + _volumeDelta).clamp(0.0, 1.0);
  double get gestureBrightness =>
      (_brightnessBase + _brightnessDelta).clamp(0.0, 1.0);

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
