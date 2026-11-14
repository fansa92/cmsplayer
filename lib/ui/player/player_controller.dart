import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../core/storage/show_marks_store.dart';
import '../../core/utils/encoding.dart';
import '../../core/utils/text_utils.dart';
import '../../data/models/play_line.dart';
import '../../data/models/play_record.dart';
import '../../data/models/play_task.dart';
import '../../data/models/vod_source.dart';
import '../../data/repository/fallback_repository.dart';
import '../../state/app_state.dart';
import '../../state/history_store.dart';
import '../../state/source_store.dart';
import '../../state/watch_stats_store.dart';
import 'player_controls_binding.dart';
import 'player_environment.dart';

/// 播放器状态与 media_kit 的桥接层。
///
/// 职责：
///  * 把 media_kit 的流式状态转成 [ChangeNotifier]，让控制栏用普通方式重建；
///  * 解析播放地址（直链 / 解析接口 / 相对地址补全）；
///  * 续播、自动下一集、播放记录节流写入；
///  * 手势过程中的音量 / 亮度 / 进度预览。
class PlayerController extends ChangeNotifier implements PlayerControlsBinding {
  PlayerController({
    required PlayTask task,
    required AppState app,
    required HistoryStore history,
    required SourceStore sources,
  })  : _app = app,
        _history = history,
        _sources = sources,
        _task = task {
    _player = environment.createPlayer();
    // 先看上次用的倍速与画面比例：用户调过一次就该沿用，
    // 「默认倍速」只是没记过时的起点。
    _rate = app.lastRate > 0 ? app.lastRate : app.defaultRate;
    _fit = _fitFromCode(app.lastFit);
    // 标记是同步读的，先让存储开始加载；真到了还没有的时候回落到播放记录。
    unawaited(ShowMarksStore.instance.ensureLoaded());
    _bindStreams();
    _openCurrent();
  }

  /// 外部依赖（播放内核 / 系统音量·亮度 / 时钟 / 一次性定时器）。
  ///
  /// 生产环境永远是 [PlayerEnvironment.production]；单元测试整体换成内存
  /// 实现，就能在不加载 libmpv、不触碰平台通道的前提下驱动整条状态机。
  /// 用 [resetEnvironmentForTest] 还原。
  @visibleForTesting
  static PlayerEnvironment environment = PlayerEnvironment.production();

  @visibleForTesting
  static void resetEnvironmentForTest() {
    environment = PlayerEnvironment.production();
  }

  final AppState _app;
  final HistoryStore _history;

  /// 资源站列表。跨源降级时要从这里找别的源。
  final SourceStore _sources;

  PlayTask _task;
  @override
  PlayTask get task => _task;

  late final Player _player;
  Player get player => _player;

  /// 视频输出只在 UI 真正取用时才创建。
  ///
  /// [VideoController] 的构造会注册 post-frame 回调并初始化原生纹理，纯逻辑
  /// 测试（以及无画面的场景）根本不需要它。改成懒创建后，播放状态机可以
  /// 完全独立于 media_kit_video 运行，生产侧唯一变化只是创建时机从构造
  /// 推迟到首次读取 —— 而首次读取本来就在播放页 build 里，效果相同。
  VideoController? _videoController;
  VideoController get videoController => _videoController ??= VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: _app.hardwareDecode,
        ),
      );

  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];

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

  /// 上一条进度事件的毫秒数。观看统计要的是「两次事件之间真的播了多久」，
  /// 所以必须留着上一跳做差。
  int _lastTickMs = 0;

  /// 还没有写进统计的观看毫秒数。攒够一段才落盘。
  int _pendingWatchMs = 0;

  // ---------------------------------------------------------------- 音轨

  /// 可切换的音轨（已剔除 media_kit 的 auto / no 占位轨）。
  List<PlayerAudioTrack> _audioTracks = const <PlayerAudioTrack>[];

  /// id → 原始轨，切换时要用它调 `setAudioTrack`。
  final Map<String, AudioTrack> _audioById = <String, AudioTrack>{};

  String? _audioId;

  // ---------------------------------------------------------------- 字幕

  /// 可切换的字幕轨。内嵌轨用 `sub:<mpv id>` 作 key，外挂字幕固定 `ext`。
  List<PlayerSubtitleTrack> _subtitleTracks = const <PlayerSubtitleTrack>[];

  final Map<String, SubtitleTrack> _subtitleById = <String, SubtitleTrack>{};

  /// 当前字幕 id，`no` 表示关闭。
  String _subtitleId = 'no';

  /// 最近一次从容器里拿到的原始字幕轨，外挂字幕重建列表时要用。
  List<SubtitleTrack> _rawSubtitleTracks = const <SubtitleTrack>[];

  /// 用户加载的外挂字幕。切集时 media_kit 会清掉轨，需要重新挂上去。
  SubtitleTrack? _externalSubtitle;
  String? _externalSubtitleLabel;

  /// 长按临时倍速前的倍速，null 表示当前没有处于临时提速。
  double? _burstFrom;

  // ---------------------------------------------------------------- 定时关闭

  /// 定时关闭的到点时刻。null 表示没开。
  DateTime? _sleepAt;

  /// 倒计时用的每秒一跳的定时器（每跳重新挂下一个）。
  Timer? _sleepTick;

  /// 「本集播完再关」。
  bool _sleepAtEnd = false;

  // ---------------------------------------------------------------- 片头片尾

  int _introMs = 0;
  int _outroMs = 0;

  /// 本集是否已经处理过片头 / 片尾（避免反复 seek 或反复跳集）。
  bool _introHandled = false;
  bool _outroHandled = false;

  // ---------------------------------------------------------------- 降级

  /// 同源降级链：备用地址 + 其它线路里的同一集。
  List<UrlFallback> _fallbackChain = const <UrlFallback>[];

  /// 降级链当前走到第几个。
  int _fallbackIndex = -1;

  /// 已经失败过的源。跨源降级时排除掉，避免绕回同一个源形成死循环。
  final Set<String> _triedSourceIds = <String>{};

  /// 已经跨源切换过几次。
  int _crossSourceCount = 0;

  /// 是否正在跑降级流程。防止两条流程互相抢降级链的位置。
  bool _recovering = false;

  /// 「正在尝试…」提示。
  String? _fallbackTrying;

  /// 「已切换到…」提示，几秒后自动消失。
  String? _fallbackNotice;

  Timer? _noticeTimer;

  /// 正在尝试降级时的提示文案。
  @override
  String? get fallbackTrying => _fallbackTrying;

  /// 降级成功后的提示文案。
  @override
  String? get fallbackNotice => _fallbackNotice;

  // ---------------------------------------------------------------- 手动换源

  /// 手动换源的候选缓存：源 id → 跨源定位结果。
  ///
  /// 弹层只把 id 传回来，这里再取回完整的线路 / 集下标，避免让 UI 层持有
  /// [SourceFallback] 这种带整部影片详情的对象。
  final Map<String, SourceFallback> _alternates =
      <String, SourceFallback>{};

  @override
  bool get canSwitchSource =>
      _sources.enabledSources.any((VodSource s) => s.id != _task.source.id);

  /// 在其它已启用的资源站里找同一部片子的同一集。
  ///
  /// 复用自动降级的跨源搜索：匹配条件（片名 + 年代 + 同名集）已经收得很紧，
  /// 手动换源同样不能把用户带到另一部片子上。
  @override
  Future<List<PlayerSourceOption>> findAlternateSources() async {
    _alternates.clear();
    final List<VodSource> candidates = _sources.enabledSources
        .where((VodSource s) => s.id != _task.source.id)
        .toList();
    if (candidates.isEmpty) return const <PlayerSourceOption>[];

    final List<SourceFallback> found =
        await FallbackResolver.crossSource(_task, candidates);
    if (_disposed) return const <PlayerSourceOption>[];

    final List<PlayerSourceOption> options = <PlayerSourceOption>[];
    for (final SourceFallback target in found) {
      _alternates[target.source.id] = target;
      options.add(PlayerSourceOption(
        id: target.source.id,
        label: target.label,
        episodeLabel: _episodeLabel(target),
      ));
    }
    return options;
  }

  /// 候选里的集说明：`线路名 · 第 01 集`。
  static String _episodeLabel(SourceFallback target) {
    final PlayLine? line = target.item.playLines.length > target.lineIndex
        ? target.item.playLines[target.lineIndex]
        : null;
    if (line == null) return '';
    final String name = target.episodeIndex < line.episodes.length
        ? line.episodes[target.episodeIndex].name.trim()
        : '';
    if (name.isEmpty) return line.name;
    return '${line.name} · $name';
  }

  /// 手动切到某个候选源。打开失败时照常走降级链，不会卡在一个黑屏上。
  @override
  Future<void> switchToSource(String sourceId) async {
    final SourceFallback? target = _alternates[sourceId];
    if (target == null) return;
    if (target.source.id == _task.source.id) return;
    // 手动换源不计入自动降级的次数上限：那是对"自动乱切"的限制。
    _crossSourceCount = 0;
    _triedSourceIds.clear();
    final bool opened = await _applyFallback(target);
    if (!opened) {
      await _handleFailure('无法打开视频（${target.label}）');
    }
  }

  // ---------------------------------------------------------------- 状态

  @override
  Duration get position => _seeking ? _seekTarget : _position;
  Duration get rawPosition => _position;
  @override
  Duration get duration => _duration;
  @override
  bool get playing => _playing;
  @override
  bool get buffering => _buffering;
  bool get completed => _completed;
  @override
  String? get error => _error;
  @override
  bool get starting => _starting;
  @override
  double get rate => _rate;
  double get volume => _volume;
  @override
  bool get locked => _locked;
  BoxFit get fit => _fit;
  @override
  bool get seeking => _seeking;

  @override
  double get positionRatio {
    if (_duration.inMilliseconds <= 0) return 0;
    return (_position.inMilliseconds / _duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  @override
  double get seekRatio {
    if (_duration.inMilliseconds <= 0) return 0;
    return (_seekTarget.inMilliseconds / _duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  /// 画面比例的持久化编码。
  static String _fitCode(BoxFit fit) => switch (fit) {
        BoxFit.cover => 'cover',
        BoxFit.fill => 'fill',
        _ => 'contain',
      };

  static BoxFit _fitFromCode(String code) => switch (code) {
        'cover' => BoxFit.cover,
        'fill' => BoxFit.fill,
        _ => BoxFit.contain,
      };

  @override
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
  @override
  String? get videoCodec => _videoCodec;
  @override
  String? get videoDecoder => _videoDecoder;
  @override
  String? get pixelFormat => _pixelFormat;
  @override
  String? get audioCodec => _audioCodec;
  @override
  String? get audioChannels => _audioChannels;
  @override
  int? get audioSampleRate => _audioSampleRate;

  /// 清晰度，例如 `1920x1080`。
  ///
  /// 优先用 stream 的 width / height：那是解码后的实际尺寸；track 上那对
  /// demux-w / demux-h 是容器里标的标称值，遇到旋转 90 度的竖屏视频会和
  /// 实际显示的宽高对不上。
  @override
  String? get resolutionLabel {
    final int? w = _videoWidth;
    final int? h = _videoHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return '${w}x$h';
  }

  /// 帧率，去掉无意义的小数尾巴（23.976 保留，30.000 变成 30）。
  @override
  String? get fpsLabel {
    final double? fps = _videoFps;
    if (fps == null || fps <= 0) return null;
    return fps.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  // -------------------------------------------------- 音轨 / 定时 / 片头片尾

  @override
  List<PlayerAudioTrack> get audioTracks => _audioTracks;

  @override
  String? get audioId => _audioId;

  @override
  Duration? get sleepRemaining {
    final DateTime? at = _sleepAt;
    if (at == null) return null;
    final Duration left = at.difference(environment.now());
    return left.isNegative ? Duration.zero : left;
  }

  @override
  bool get sleepAtEnd => _sleepAtEnd;

  @override
  int get introMs => _introMs;

  @override
  int get outroMs => _outroMs;

  @override
  bool get inIntro => _introMs > 0 && _position.inMilliseconds < _introMs;

  @override
  bool get autoSkipIntro => _app.autoSkipIntro;

  @override
  bool get autoSkipOutro => _app.autoSkipOutro;

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
      // 续播优先于片头：续播已经把人带到很远的地方时，不该再回头跳片头。
      if (!_maybeAutoResume()) _maybeSkipIntro();
      _maybeSkipOutro();
      _maybeWriteHistory();
      _trackWatchTime(p);
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
      // 不立刻报错：先沿降级链试一遍（备用地址 → 其它线路 → 换源），
      // 都试过了才把错误面板亮出来。
      unawaited(_handleFailure(e.isEmpty ? '播放失败' : e));
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
      final List<AudioTrack> audio = _realAudioTracks(ts.audio);
      final VideoTrack? v = _firstRealVideo(ts.video);
      final AudioTrack? a = audio.isEmpty ? null : audio.first;
      _videoFps = v?.fps ?? _videoFps;
      _videoCodec = v?.codec ?? _videoCodec;
      _videoDecoder = v?.decoder ?? _videoDecoder;
      _audioCodec = a?.codec ?? _audioCodec;
      _audioChannels = a?.channels ?? _channelsOf(a) ?? _audioChannels;
      _audioSampleRate = a?.samplerate ?? _audioSampleRate;
      _syncAudioTracks(audio);
      _syncSubtitleTracks(ts.subtitle);
      _emit();
    }));
    // 当前生效的轨。用户切换音轨、或者播放器自己挑了一条之后都会推一次，
    // 用它保持「弹层里打勾的那条」和实际播放的一致。
    _subs.add(_player.stream.track.listen((Track t) {
      final AudioTrack a = t.audio;
      bool changed = false;
      if (a.id != 'auto' && a.id != 'no' && _audioId != a.id) {
        _audioId = a.id;
        changed = true;
      }
      // 字幕：media_kit 会自己挑一条默认字幕，界面上要同步过去。
      final SubtitleTrack s = t.subtitle;
      if (s.data) {
        if (_subtitleId != 'ext') {
          _subtitleId = 'ext';
          changed = true;
        }
      } else if (s.id == 'no') {
        if (_subtitleId != 'no') {
          _subtitleId = 'no';
          changed = true;
        }
      } else if (s.id != 'auto' && !s.uri) {
        final String key = 'sub:${s.id}';
        if (_subtitleById.containsKey(key) && _subtitleId != key) {
          _subtitleId = key;
          changed = true;
        }
      }
      if (changed) _emit();
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

  /// 真正可用于切换的音轨。
  ///
  /// 和 [_firstRealVideo] 不同，这里不要求带 codec —— 用户能切就行；只是
  /// 占位的 `auto` / `no` 必须剔掉，否则弹层里会多出两个假选项。
  static List<AudioTrack> _realAudioTracks(List<AudioTrack> list) => list
      .where((AudioTrack t) => t.id != 'auto' && t.id != 'no')
      .toList(growable: false);

  /// 音轨显示名：优先用容器里的标题，其次语言，都没有就按序号。
  static String _audioLabel(AudioTrack t, int index) {
    final String title = (t.title ?? '').trim();
    if (title.isNotEmpty) return title;
    final String lang = (t.language ?? '').trim();
    if (lang.isNotEmpty) return lang;
    return '音轨 ${index + 1}';
  }

  void _syncAudioTracks(List<AudioTrack> audio) {
    _audioById
      ..clear()
      ..addEntries(
        audio.map((AudioTrack t) => MapEntry<String, AudioTrack>(t.id, t)),
      );
    _audioTracks = <PlayerAudioTrack>[
      for (int i = 0; i < audio.length; i++)
        PlayerAudioTrack(
          id: audio[i].id,
          label: _audioLabel(audio[i], i),
          codec: audio[i].codec ?? '',
        ),
    ];
    // 选中的那条可能随着切集消失了，落回第一条真实轨。
    if (_audioId != null && !_audioById.containsKey(_audioId)) _audioId = null;
    _audioId ??= audio.isEmpty ? null : audio.first.id;
  }

  /// 声道数兜底：demux-channels 缺失时用 demux-channel-count 拼一个可读串。
  static String? _channelsOf(AudioTrack? t) {
    final int? n = t?.channelscount;
    if (n == null || n <= 0) return null;
    return '$n';
  }

  // ---------------------------------------------------------------- 字幕

  @override
  List<PlayerSubtitleTrack> get subtitleTracks => _subtitleTracks;

  @override
  String get subtitleId => _subtitleId;

  @override
  bool get subtitleActive => _subtitleId != 'no';

  /// 字幕显示名：标题 → 语言 → 序号。
  static String _subtitleLabel(SubtitleTrack t, int index) {
    final String title = (t.title ?? '').trim();
    if (title.isNotEmpty) return title;
    final String lang = (t.language ?? '').trim();
    if (lang.isNotEmpty) return lang;
    return '字幕 ${index + 1}';
  }

  void _syncSubtitleTracks(List<SubtitleTrack> raw) {
    _rawSubtitleTracks = raw;
    _subtitleById.clear();
    final List<PlayerSubtitleTrack> list = <PlayerSubtitleTrack>[];
    for (int i = 0; i < raw.length; i++) {
      final SubtitleTrack t = raw[i];
      // auto / no 是占位轨；外挂轨单独由 _externalSubtitle 维护，不重复列。
      if (t.id == 'auto' || t.id == 'no' || t.uri || t.data) continue;
      final String key = 'sub:${t.id}';
      _subtitleById[key] = t;
      list.add(PlayerSubtitleTrack(
        id: key,
        label: _subtitleLabel(t, i),
        language: t.language ?? '',
        codec: t.codec ?? '',
      ));
    }
    final SubtitleTrack? ext = _externalSubtitle;
    if (ext != null) {
      _subtitleById['ext'] = ext;
      list.add(PlayerSubtitleTrack(
        id: 'ext',
        label: _externalSubtitleLabel ?? '外挂字幕',
        external: true,
      ));
    }
    _subtitleTracks = list;
    // 选中的轨可能随着切集消失了，落回「关闭」。
    if (_subtitleId != 'no' && !_subtitleById.containsKey(_subtitleId)) {
      _subtitleId = 'no';
    }
  }

  @override
  Future<void> selectSubtitleTrack(String id) async {
    if (id == _subtitleId) return;
    if (id == 'no') {
      _subtitleId = 'no';
      _emit();
      try {
        await _player.setSubtitleTrack(SubtitleTrack.no());
      } on Object catch (e) {
        AppLog.e('Player', 'disable subtitle failed: $e');
      }
      return;
    }
    final SubtitleTrack? track = _subtitleById[id];
    if (track == null) return;
    _subtitleId = id;
    _emit();
    try {
      await _player.setSubtitleTrack(track);
    } on Object catch (e) {
      AppLog.e('Player', 'setSubtitleTrack failed: $e');
    }
  }

  @override
  Future<bool> loadSubtitleUrl(String url) async {
    final String text = url.trim();
    if (text.isEmpty) return false;
    final Uri? uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) {
      _setNotice('字幕链接不完整');
      return false;
    }
    try {
      final List<int> bytes = await environment.fetchBytes(uri);
      final String decoded = ResponseDecoder.decode(bytes);
      final String label =
          uri.pathSegments.isEmpty ? '外挂字幕' : uri.pathSegments.last;
      return await _adoptExternalSubtitle(decoded, label: label);
    } on Object catch (e) {
      AppLog.e('Player', 'load subtitle url failed: $e');
      _setNotice('字幕加载失败');
      return false;
    }
  }

  @override
  Future<bool> loadSubtitlePath(String path) async {
    final String text = path.trim();
    if (text.isEmpty) return false;
    try {
      final List<int> bytes = await environment.readFileBytes(text);
      final String decoded = ResponseDecoder.decode(bytes);
      final String label = text.split(RegExp(r'[\\/]')).last;
      return await _adoptExternalSubtitle(decoded, label: label);
    } on Object catch (e) {
      AppLog.e('Player', 'load subtitle file failed: $e');
      _setNotice('找不到这个字幕文件');
      return false;
    }
  }

  /// 粗略判断是不是字幕文本。mpv 对格式不对的文件只报一个错，
  /// 不如加载前先拦住，提示也更准确。
  static bool _looksLikeSubtitle(String text) {
    if (text.trim().isEmpty) return false;
    final String lower = text.toLowerCase();
    return text.contains('-->') ||
        lower.contains('webvtt') ||
        lower.contains('[script info]') ||
        lower.contains('dialogue:');
  }

  Future<bool> _adoptExternalSubtitle(
    String text, {
    required String label,
  }) async {
    if (!_looksLikeSubtitle(text)) {
      _setNotice('这不是可识别的字幕文件');
      return false;
    }
    final String name = label.trim().isEmpty ? '外挂字幕' : label.trim();
    final SubtitleTrack track = SubtitleTrack.data(text, title: name);
    _externalSubtitle = track;
    _externalSubtitleLabel = name;
    _subtitleId = 'ext';
    _syncSubtitleTracks(_rawSubtitleTracks);
    _emit();
    try {
      await _player.setSubtitleTrack(track);
    } on Object catch (e) {
      AppLog.e('Player', 'apply external subtitle failed: $e');
      _setNotice('字幕加载失败');
      return false;
    }
    _setNotice('已加载字幕：$name');
    return true;
  }

  /// 切集后 media_kit 会丢掉外挂轨，这里重新挂一次。
  Future<void> _reapplyExternalSubtitle() async {
    final SubtitleTrack? track = _externalSubtitle;
    if (track == null) return;
    try {
      await _player.setSubtitleTrack(track);
      _subtitleId = 'ext';
    } on Object catch (e) {
      AppLog.d('Player', 'reapply subtitle failed: $e');
    }
  }

  // ---------------------------------------------------------------- 打开

  /// 把原始地址解析成最终交给 libmpv 的地址。
  ///
  /// 相对地址按接口地址补全；不是直链时按源的「解析接口」拼接。
  String? resolveRawUrl(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) return null;

    final String absolute = resolveUrl(text, base: _task.source.api) ?? text;
    if (isDirectPlayable(absolute)) return absolute;

    final String parse = _task.source.parseApi.trim();
    if (parse.isEmpty) return absolute;
    final String encoded = Uri.encodeComponent(absolute);
    return parse.contains('{url}')
        ? parse.replaceAll('{url}', encoded)
        : '$parse$encoded';
  }

  /// 解析当前集的播放地址。
  String? resolvePlayUrl(PlayEpisode episode) => resolveRawUrl(episode.url);

  /// 打开当前任务，并重建降级链。
  Future<void> _openCurrent() async {
    _fallbackChain = FallbackResolver.sameSource(_task);
    _fallbackIndex = -1;
    _loadSkipMarks();

    final PlayEpisode? episode = _task.episode;
    if (episode == null) {
      _error = '没有可播放的地址';
      _starting = false;
      _emit();
      return;
    }

    final String? url = resolveRawUrl(episode.url);
    if (url == null) {
      _error = '该集没有有效的播放地址';
      _starting = false;
      _emit();
      return;
    }

    final bool opened = await _openUrl(url);
    if (!opened) {
      // 打开时直接抛了异常：降级链照样走一遍。
      await _handleFailure(_error ?? '无法打开视频');
    }
  }

  /// 打开一个地址。返回 false 表示 `open` 阶段直接抛了异常。
  Future<bool> _openUrl(String url) async {
    _error = null;
    _starting = true;
    _startupTimer?.cancel();
    _startupTimer = null;
    _completed = false;
    _resumeApplied = false;
    _introHandled = false;
    _outroHandled = false;
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
      // 外挂字幕不随 open 保留，重新挂上去（没有就什么都不做）。
      await _reapplyExternalSubtitle();
      // 正常情况下 playing / duration 流会立刻清掉 _starting；
      // 这里再挂一道兜底，防止流不触发时控制栏被永久遮住。
      _startupTimer?.cancel();
      _startupTimer = environment.createTimer(K.startupTimeout, () {
        if (_starting) {
          _clearStarting('timeout');
          _emit();
        }
      });
      return true;
    } on Object catch (e) {
      AppLog.e('Player', 'open failed: $e');
      if (_disposed) return false;
      _error = '无法打开视频：$e';
      _starting = false;
      _emit();
      return false;
    }
  }

  // ---------------------------------------------------------------- 降级

  /// 播放失败后的降级处理。
  ///
  /// 依次尝试：同源备用地址 → 同源其它线路 → 跨源同名影片。
  /// 全部试完仍然失败，才把错误显示给用户。
  ///
  /// [_recovering] 保证同一时刻只有一条降级流程在跑：`_openUrl` 失败时
  /// 也会走这里，不加锁的话两条流程会互相抢降级链的位置。
  Future<void> _handleFailure(String message) async {
    if (_disposed || _recovering) return;
    _recovering = true;
    try {
      String lastError = message;
      while (true) {
        final FallbackTarget? next = await _nextFallback();
        if (next == null) {
          _fallbackTrying = null;
          _error = lastError;
          _starting = false;
          _emit();
          return;
        }
        final bool opened = await _applyFallback(next);
        if (opened) {
          // 打开成功，等后续的 error 流；没再报错就算救回来了。
          _fallbackTrying = null;
          _emit();
          return;
        }
        lastError = '无法打开视频（${next.label}）';
      }
    } finally {
      _recovering = false;
    }
  }

  /// 取下一个降级候选。没有了返回 null。
  Future<FallbackTarget?> _nextFallback() async {
    // 1) 同源：备用地址 + 其它线路里的同一集。
    if (_fallbackIndex + 1 < _fallbackChain.length) {
      _fallbackIndex++;
      final UrlFallback target = _fallbackChain[_fallbackIndex];
      _fallbackTrying = '正在尝试${target.label}';
      _emit();
      return target;
    }

    // 2) 跨源：到别的资源站里找同名影片。
    if (_crossSourceCount >= K.maxCrossSourceFallbacks) return null;
    final List<VodSource> candidates = _sources.enabledSources
        .where(
          (VodSource s) =>
              s.id != _task.source.id && !_triedSourceIds.contains(s.id),
        )
        .toList();
    if (candidates.isEmpty) return null;

    _fallbackTrying = '正在查找其它资源站…';
    _emit();
    final List<SourceFallback> found =
        await FallbackResolver.crossSource(_task, candidates);
    if (found.isEmpty) return null;

    _crossSourceCount++;
    _triedSourceIds.add(_task.source.id);
    return found.first;
  }

  /// 应用一个降级候选并打开。返回 false 表示打开失败。
  Future<bool> _applyFallback(FallbackTarget target) async {
    if (target is SourceFallback) {
      _task = _task.copyWith(
        source: target.source,
        item: target.item,
        lineIndex: target.lineIndex,
        episodeIndex: target.episodeIndex,
      );
      // 新源有自己的线路与备用地址，同源降级链要按新源重建。
      _fallbackChain = FallbackResolver.sameSource(_task);
      _fallbackIndex = -1;
      _setNotice('已切换到「${target.label}」');
      _emit();
    }

    final String? url = resolveRawUrl(target.url);
    if (url == null) return false;
    return _openUrl(url);
  }

  /// 设置一次性提示，几秒后自动消失。
  void _setNotice(String text) {
    _fallbackNotice = text;
    _noticeTimer?.cancel();
    _noticeTimer = environment.createTimer(K.fallbackNoticeDuration, () {
      if (_disposed) return;
      _fallbackNotice = null;
      _emit();
    });
    _emit();
  }

  /// 首次拿到时长时应用续播位置。
  ///
  /// 返回是否真的跳转过 —— 调用方据此决定还要不要走「跳过片头」，否则两个
  /// seek 会打架，最后生效的反而是片头那个。
  bool _maybeAutoResume() {
    if (_resumeApplied || _disposed) return false;
    if (!_app.resumePlayback) {
      _resumeApplied = true;
      return false;
    }
    if (_duration.inMilliseconds <= 0) return false;
    _resumeApplied = true;

    final PlayRecord? record = _history.byKey(_task.recordKey);
    if (record == null) return false;
    if (record.lineIndex != _task.lineIndex ||
        record.episodeIndex != _task.episodeIndex) {
      return false;
    }
    final int pos = record.positionMs;
    if (pos <= K.resumeSeekThreshold.inMilliseconds) return false;
    if (record.durationMs > 0 && pos / record.durationMs >= K.finishRatio) {
      return false;
    }
    _player.seek(Duration(milliseconds: pos));
    AppLog.d('Player', 'resume at ${pos}ms');
    return true;
  }

  /// 开播后跳过一次片头。只做一次，用户自己拖回片头不会被反复弹出去。
  void _maybeSkipIntro() {
    if (_introHandled || _disposed) return;
    if (_introMs <= 0 || !_app.autoSkipIntro) {
      _introHandled = true;
      return;
    }
    // 等时长落地：没有时长时 position 还不可信，跳过去也可能被 mpv 忽略。
    if (_duration.inMilliseconds <= 0) return;
    if (!_resumeApplied) return;
    _introHandled = true;
    if (_position.inMilliseconds >= _introMs) return;
    unawaited(_player.seek(Duration(milliseconds: _introMs)));
    _setNotice('已跳过片头');
  }

  /// 播到片尾标记时直接进下一集。
  void _maybeSkipOutro() {
    if (_outroHandled || _disposed) return;
    if (_outroMs <= 0 || !_app.autoSkipOutro || !_task.hasNext) {
      _outroHandled = true;
      return;
    }
    if (_position.inMilliseconds < _outroMs) return;
    _outroHandled = true;
    _setNotice('已跳过片尾');
    unawaited(next());
  }

  void _loadSkipMarks() {
    // 优先用按片名存的那份：同一部片换了资源站也认。
    final ShowSkipMarks? saved =
        ShowMarksStore.instance.find(_task.item.name);
    if (saved != null) {
      _introMs = saved.introMs;
      _outroMs = saved.outroMs;
      return;
    }
    final PlayRecord? r = _history.byKey(_task.recordKey);
    _introMs = r?.introMs ?? 0;
    _outroMs = r?.outroMs ?? 0;
  }

  void _onCompleted() {
    _writeHistory(force: true, finished: true);
    // 「本集播完关」优先于自动连播：用户要的是停下来，不是继续放。
    if (_sleepAtEnd) {
      _sleepAtEnd = false;
      _setNotice('本集已播完，定时关闭');
      _emit();
      return;
    }
    if (_app.autoNextEpisode && _task.hasNext) {
      next();
    }
  }

  // ---------------------------------------------------------------- 控制

  @override
  Future<void> togglePlay() => _player.playOrPause();

  @override
  Future<void> seek(Duration target) async {
    if (_duration.inMilliseconds <= 0) return;
    final int maxMs = _duration.inMilliseconds;
    final int ms = target.inMilliseconds.clamp(0, maxMs);
    await _player.seek(Duration(milliseconds: ms));
  }

  @override
  Future<void> seekBy(Duration delta) => seek(_position + delta);

  @override
  Future<void> setRate(double value) async {
    _rate = value;
    // 记下来，下次开播直接沿用；不 await，避免拖慢按钮反馈。
    unawaited(_app.setLastRate(value));
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
  @override
  Future<double?> stepVolume(double deltaPercent) async {
    try {
      final double base = _systemVolume >= 0
          ? _systemVolume / 100
          : await environment.readVolume();
      final double next = (base + deltaPercent / 100).clamp(0.0, 1.0);
      await environment.writeVolume(next);
      _systemVolume = next * 100;
      _emit();
      return _systemVolume;
    } on Object catch (e) {
      AppLog.d('Player', 'stepVolume failed: $e');
      return null;
    }
  }

  @override
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
    unawaited(_app.setLastFit(_fitCode(_fit)));
    _emit();
  }

  @override
  void toggleLock() {
    _locked = !_locked;
    _emit();
  }

  @override
  Future<void> next() => _switchTo(_task.lineIndex, _task.episodeIndex + 1);

  @override
  Future<void> previous() => _switchTo(_task.lineIndex, _task.episodeIndex - 1);

  @override
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

  /// 手动重试。清掉降级状态，从头再走一遍。
  @override
  Future<void> retry() async {
    _triedSourceIds.clear();
    _crossSourceCount = 0;
    _fallbackNotice = null;
    _fallbackTrying = null;
    await _openCurrent();
  }

  // ---------------------------------------------------------------- 音轨

  @override
  Future<void> selectAudioTrack(String id) async {
    final AudioTrack? track = _audioById[id];
    if (track == null || _audioId == id) return;
    _audioId = id;
    _emit();
    try {
      await _player.setAudioTrack(track);
    } on Object catch (e) {
      AppLog.e('Player', 'setAudioTrack failed: $e');
    }
  }

  /// 长按临时提速。松手由 [endBurstRate] 还原。
  ///
  /// 只在当前倍速低于目标倍速时才生效：用户本来就用 3 倍速看着，长按反而
  /// 降速到 2 倍会很怪。
  @override
  Future<void> startBurstRate() async {
    if (_burstFrom != null) return;
    if (_rate >= K.burstRate) return;
    _burstFrom = _rate;
    _emit();
    try {
      await _player.setRate(K.burstRate);
    } on Object catch (e) {
      AppLog.e('Player', 'burst rate failed: $e');
    }
  }

  @override
  Future<void> endBurstRate() async {
    final double? from = _burstFrom;
    if (from == null) return;
    _burstFrom = null;
    _emit();
    try {
      await _player.setRate(from);
    } on Object catch (e) {
      AppLog.e('Player', 'restore rate failed: $e');
    }
  }

  // ---------------------------------------------------------------- 定时关闭

  @override
  Future<void> setSleepTimer(Duration? remaining) async {
    _sleepTick?.cancel();
    _sleepTick = null;
    _sleepAtEnd = false;
    if (remaining == null || remaining <= Duration.zero) {
      _sleepAt = null;
      _emit();
      return;
    }
    _sleepAt = environment.now().add(remaining);
    _scheduleSleepTick();
    _emit();
  }

  @override
  Future<void> setSleepAtEnd(bool value) async {
    _sleepTick?.cancel();
    _sleepTick = null;
    _sleepAt = null;
    _sleepAtEnd = value;
    _emit();
  }

  /// 每秒一跳，只为把剩余时间推给界面；每一跳再挂下一跳。
  void _scheduleSleepTick() {
    _sleepTick = environment.createTimer(const Duration(seconds: 1), () {
      if (_disposed) return;
      final Duration? left = sleepRemaining;
      if (left == null) return;
      if (left <= Duration.zero) {
        _sleepTick = null;
        _sleepAt = null;
        unawaited(_player.pause());
        _setNotice('定时关闭已生效，已暂停播放');
        _emit();
        return;
      }
      _emit();
      _scheduleSleepTick();
    });
  }

  // ---------------------------------------------------------------- 片头片尾

  @override
  Future<void> markIntroAt(Duration position) async {
    _introMs = position.inMilliseconds;
    // 片头标到了片尾之后，说明有一个标错了，清掉旧的片尾。
    if (_outroMs > 0 && _outroMs <= _introMs) _outroMs = 0;
    _introHandled = true;
    await _persistSkipMarks();
    _emit();
  }

  @override
  Future<void> markOutroAt(Duration position) async {
    _outroMs = position.inMilliseconds;
    if (_introMs > 0 && _outroMs <= _introMs) _introMs = 0;
    _outroHandled = false;
    await _persistSkipMarks();
    _emit();
  }

  @override
  Future<void> clearSkipMarks() async {
    _introMs = 0;
    _outroMs = 0;
    await _persistSkipMarks();
    _emit();
  }

  @override
  Future<void> skipIntro() async {
    if (_introMs <= 0) return;
    _introHandled = true;
    await seek(Duration(milliseconds: _introMs));
  }

  @override
  Future<void> setAutoSkipIntro(bool value) async {
    await _app.setAutoSkipIntro(value);
    // 打开开关时重置：正卡在片头里也要能立刻跳过去。
    if (value) _introHandled = false;
    _emit();
  }

  @override
  Future<void> setAutoSkipOutro(bool value) async {
    await _app.setAutoSkipOutro(value);
    if (value) _outroHandled = false;
    _emit();
  }

  Future<void> _persistSkipMarks() async {
    // 片名级存储：换源 / 清历史都还在。用户关掉「记住」就只写播放记录。
    if (_app.rememberSkipMarks) {
      try {
        if (_introMs <= 0 && _outroMs <= 0) {
          await ShowMarksStore.instance.clear(_task.item.name);
        } else {
          await ShowMarksStore.instance.save(
            _task.item.name,
            introMs: _introMs,
            outroMs: _outroMs,
          );
        }
      } on Object catch (e) {
        AppLog.d('Player', 'save show marks failed: $e');
      }
    }
    final PlayRecord? existing = _history.byKey(_task.recordKey);
    if (existing != null) {
      await _history.upsert(
        existing.copyWith(introMs: _introMs, outroMs: _outroMs),
      );
      return;
    }
    // 还没播够 20 秒、历史里根本没有这条记录：补写一条，带上标记。
    _writeHistory(force: true);
  }

  // ---------------------------------------------------------------- 手势

  @override
  void startSeek() {
    _seeking = true;
    _seekTarget = _position;
    _emit();
  }

  @override
  void updateSeek(Duration delta) {
    if (!_seeking) return;
    if (_duration.inMilliseconds <= 0) return;
    // delta 是"相对上一帧"的增量，必须累加到上一次的目标上。
    // 之前写成 `_position + delta`，整段拖动只按最后一下的幅度生效，
    // 拖满屏进度条也几乎不动。
    final int ms =
        (_seekTarget + delta).inMilliseconds.clamp(0, _duration.inMilliseconds);
    _seekTarget = Duration(milliseconds: ms);
    _emit();
  }

  @override
  void commitSeek() async {
    if (!_seeking) return;
    final Duration target = _seekTarget;
    _seeking = false;
    _emit();
    await seek(target);
  }

  @override
  void cancelSeek() {
    _seeking = false;
    _emit();
  }

  /// [isVolume] 为 true 表示调右侧音量，false 表示调左侧亮度。
  @override
  Future<void> startVerticalGesture({required bool isVolume}) async {
    if (_adjustingVolume || _adjustingBrightness) return;
    try {
      if (isVolume) {
        final double v = await environment.readVolume();
        _gestureVolume = v;
        _systemVolume = v * 100; // 与键盘步进共享读数
        _adjustingVolume = true;
      } else {
        _gestureBrightness = await environment.readBrightness();
        _adjustingBrightness = true;
      }
    } on Object catch (e) {
      AppLog.d('Player', 'vertical gesture unsupported: $e');
    }
    _emit();
  }

  /// [delta] 是自上一帧以来的位移（归一化到 0..1），必须累加到当前值上。
  @override
  Future<void> updateVerticalGesture(double delta) async {
    if (_adjustingVolume) {
      _gestureVolume = (_gestureVolume + delta).clamp(0.0, 1.0);
      try {
        await environment.writeVolume(_gestureVolume);
      } on Object {
        // 平台不支持时静默忽略。
      }
      _emit();
    } else if (_adjustingBrightness) {
      _gestureBrightness = (_gestureBrightness + delta).clamp(0.0, 1.0);
      try {
        await environment.writeBrightness(_gestureBrightness);
      } on Object {
        // 平台不支持时静默忽略。
      }
      _emit();
    }
  }

  @override
  Future<void> endVerticalGesture() async {
    _adjustingVolume = false;
    _adjustingBrightness = false;
    _emit();
  }

  @override
  bool get adjustingVolume => _adjustingVolume;
  @override
  bool get adjustingBrightness => _adjustingBrightness;
  @override
  double get gestureVolume => _gestureVolume;
  @override
  double get gestureBrightness => _gestureBrightness;

  /// 系统音量（0..100），-1 表示尚未读到过。
  double get systemVolume => _systemVolume;

  // ---------------------------------------------------------------- 历史

  void _maybeWriteHistory() {
    if (_disposed) return;
    if (_duration.inMilliseconds <= K.minResumeSource.inMilliseconds) {
      return;
    }
    final DateTime now = environment.now();
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
    final int positionMs = finished ? durationMs : _position.inMilliseconds;
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
        finished: finished ||
            (durationMs > 0 && positionMs / durationMs >= K.finishRatio),
        introMs: _introMs,
        outroMs: _outroMs,
        updatedAt: environment.now(),
      ),
    );
  }

  // ---------------------------------------------------------------- 观看统计

  /// 累计真实播放时长。
  ///
  /// 只看进度流两次事件之间的**正向小增量**：
  ///  * 拖进度条 / 自动跳片头片尾会产生大跳变（超过 [K.watchMaxTickJumpMs]），
  ///    跳过的那段没看过，不算；
  ///  * 往回拖（增量为负）只是重置基准，也不扣时间；
  ///  * 暂停时进度不动，本来就不会有增量。
  ///
  /// 攒够 [K.watchFlushMs] 才交给 [WatchStatsStore]，避免每秒写盘。
  void _trackWatchTime(Duration position) {
    final int ms = position.inMilliseconds;
    final int last = _lastTickMs;
    _lastTickMs = ms;
    if (!_playing || last <= 0 || ms <= last) return;
    final int delta = ms - last;
    if (delta > K.watchMaxTickJumpMs) return;
    _pendingWatchMs += delta;
    if (_pendingWatchMs >= K.watchFlushMs) _commitWatchTime();
  }

  /// 把攒下的观看时长写进统计；[force] 用于退出时兜底。
  void _commitWatchTime({bool force = false}) {
    final int ms = _pendingWatchMs;
    // 退出时不足 5 秒的零头不值得写一行；正常播放中由阈值控制。
    if (ms <= 0 || (force && ms < 5000)) return;
    _pendingWatchMs = 0;
    unawaited(WatchStatsStore.instance.add(
      title: _task.item.name,
      sourceId: _task.source.id,
      sourceName: _task.source.name,
      watched: Duration(milliseconds: ms),
    ));
  }

  // ---------------------------------------------------------------- 释放

  Future<void> restoreBrightness() async {
    try {
      await environment.resetBrightness();
    } on Object {
      // 忽略。
    }
  }

  @override
  void dispose() {
    // 页面在退出过程中可能重复触发 dispose（例如播放器页被 pop 两次，或
    // 外层 rebuild 时又走了一遍销毁）。ChangeNotifier 二次 dispose 会在
    // debug 下断言，且会重复写历史，所以这里显式做幂等。
    if (_disposed) return;
    _disposed = true;
    _startupTimer?.cancel();
    _startupTimer = null;
    _noticeTimer?.cancel();
    _noticeTimer = null;
    _sleepTick?.cancel();
    _sleepTick = null;
    for (final StreamSubscription<Object?> sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    _writeHistory(force: true);
    _commitWatchTime(force: true);
    unawaited(_player.dispose());
    unawaited(restoreBrightness());
    super.dispose();
  }
}
