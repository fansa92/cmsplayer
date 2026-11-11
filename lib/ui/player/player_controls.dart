import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/utils/formatter.dart';
import '../../core/utils/responsive.dart';
import 'player_chrome.dart';
import 'player_controls_binding.dart';
import 'player_sheets.dart';
import 'player_window.dart';

/// 播放器控制层。
///
/// 结构：底层是一个覆盖全屏的 [GestureDetector] 负责点击 / 双击 / 横向拖动进度 /
/// 纵向拖动音量与亮度；控制面板叠在上面，只占据上下两条，因此不会抢走手势。
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.controller,
    required this.onBack,
  });

  final PlayerControlsBinding controller;
  final VoidCallback onBack;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  Timer? _hideTimer;
  bool _visible = true;

  /// 键盘焦点。播放页内没有输入框，独占它不会打断任何输入。
  final FocusNode _focusNode = FocusNode(debugLabel: 'PlayerControls');

  /// 窗口是否全屏，只用于全屏按钮的图标与 Esc 判断（仅桌面有意义）。
  bool _fullScreen = false;

  /// 键盘操作的临时提示（音量、快进步长）。
  String? _osd;
  Timer? _osdTimer;

  /// 双击落点，用来判断点的是左 / 中 / 右哪个区域。
  Offset? _doubleTapPos;

  /// 是否正处于长按临时提速。
  bool _bursting = false;

  PlayerControlsBinding get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _visible = true;
    _scheduleHide();

    if (PlatformInfo.isDesktop) {
      PlayerWindow.isFullScreen().then((bool v) {
        if (mounted) setState(() => _fullScreen = v);
      });
    }

    // autofocus 在路由还没拿到焦点时可能落空，这里补一帧再请求一次。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _osdTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(K.controlsHideDelay, () {
      if (!mounted) return;
      if (controller.seeking ||
          controller.adjustingVolume ||
          controller.adjustingBrightness) {
        _scheduleHide();
        return;
      }
      setState(() => _visible = false);
    });
  }

  /// 显示控制栏并重置自动隐藏计时。
  ///
  /// [grabFocus] 只有在用户**点击画面**这类明确意图时才为 true：鼠标移动
  /// 不该把焦点从打开的选集面板手里抢走，而点击时抢回来才能保证快捷键可用
  /// （焦点已在此节点时该调用是空操作）。
  void _show({bool grabFocus = true}) {
    if (!mounted) return;
    if (grabFocus) _focusNode.requestFocus();
    // 鼠标移动会以很高的频率调到这里，已经可见时只重置定时器即可，
    // 无谓的 setState 会让整个控制层跟着指针抖动重建。
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  /// 键盘 / 手势操作后的浮层提示。
  void _showOsd(String text) {
    if (!mounted) return;
    _osdTimer?.cancel();
    setState(() => _osd = text);
    _osdTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _osd = null);
    });
  }

  Future<void> _stepVolume(double delta) async {
    final double? applied = await controller.stepVolume(delta);
    if (!mounted || applied == null) return;
    _showOsd('音量 ${applied.round()}%');
    _show();
  }

  void _toggle() {
    setState(() => _visible = !_visible);
    if (_visible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  // ---------------------------------------------------------------- 手势

  /// 双击分区：左右各 1/3 快退 / 快进，中间切播放。
  ///
  /// 竖屏下手持手机时拇指落在中间偏下，中间留给「暂停」最符合直觉；
  /// 想快进则要明确点到两侧，避免误触。
  void _onDoubleTap() {
    final double width = MediaQuery.sizeOf(context).width;
    if (width <= 0) return;
    final double dx = _doubleTapPos?.dx ?? width / 2;
    if (dx < width / 3) {
      controller.seekBy(-K.doubleTapStep);
      _showOsd('快退 ${K.doubleTapStep.inSeconds} 秒');
    } else if (dx > width * 2 / 3) {
      controller.seekBy(K.doubleTapStep);
      _showOsd('快进 ${K.doubleTapStep.inSeconds} 秒');
    } else {
      controller.togglePlay();
    }
    _show();
  }

  Future<void> _onLongPressStart(LongPressStartDetails details) async {
    await controller.startBurstRate();
    if (!mounted) return;
    setState(() => _bursting = true);
  }

  Future<void> _onLongPressEnd(LongPressEndDetails details) async {
    await controller.endBurstRate();
    if (!mounted) return;
    setState(() => _bursting = false);
    _show();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    controller.startSeek();
    _show();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final double width = MediaQuery.sizeOf(context).width;
    if (width <= 0) return;
    final double totalMs = controller.duration.inMilliseconds.toDouble();
    if (totalMs <= 0) return;
    final double deltaPx = details.primaryDelta ?? 0;
    controller.updateSeek(Duration(
      milliseconds: (deltaPx / width * totalMs).round(),
    ));
    _scheduleHide();
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    controller.commitSeek();
    _scheduleHide();
  }

  Future<void> _onVerticalDragStart(DragStartDetails details) async {
    final double width = MediaQuery.sizeOf(context).width;
    final bool isVolume = details.globalPosition.dx > width / 2;
    await controller.startVerticalGesture(isVolume: isVolume);
    _show();
  }

  Future<void> _onVerticalDragUpdate(DragUpdateDetails details) async {
    final double height = MediaQuery.sizeOf(context).height;
    if (height <= 0) return;
    final double delta = -(details.primaryDelta ?? 0) / height;
    await controller.updateVerticalGesture(delta);
    _scheduleHide();
  }

  Future<void> _onVerticalDragEnd(DragEndDetails details) async {
    await controller.endVerticalGesture();
    _scheduleHide();
  }

  // ---------------------------------------------------------------- 键盘

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // 只处理按下与长按重复；松开不处理，但也不放行，避免穿透到别处。
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final bool repeat = event is KeyRepeatEvent;
    final LogicalKeyboardKey key = event.logicalKey;

    // 锁定 = 禁止播放组件，键盘上的播放键一并吃掉。这里吞掉而不是放行，
    // 否则按键会穿透到播放页底下的列表上去。
    final bool locked = controller.locked;

    switch (key) {
      case LogicalKeyboardKey.escape:
        // 有焦点就说明播放页在最上层，重复触发无副作用。
        _handleEscape();
        return KeyEventResult.handled;

      // 播放控制类按键不吃长按重复，否则按住空格会疯狂切换暂停。
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        if (locked) return KeyEventResult.handled;
        if (!repeat) {
          controller.togglePlay();
          _show();
        }
        return KeyEventResult.handled;

      // F 只改窗口形态，不碰播放内容，锁定时照常可用。
      case LogicalKeyboardKey.keyF:
        if (!repeat) _toggleFullScreen();
        return KeyEventResult.handled;

      // 下面这些按键长按应当连续生效（按住方向键持续快进 / 调音量）。
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.keyJ:
        if (locked) return KeyEventResult.handled;
        controller.seekBy(const Duration(seconds: -10));
        _showOsd('快退 10 秒');
        _show();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.keyL:
        if (locked) return KeyEventResult.handled;
        controller.seekBy(const Duration(seconds: 10));
        _showOsd('快进 10 秒');
        _show();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowUp:
        if (locked) return KeyEventResult.handled;
        _stepVolume(5);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowDown:
        if (locked) return KeyEventResult.handled;
        _stepVolume(-5);
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }

  Future<void> _handleEscape() async {
    if (await PlayerWindow.isFullScreen()) {
      await PlayerWindow.setFullScreen(false);
      if (!mounted) return;
      setState(() => _fullScreen = false);
      _show();
      return;
    }
    widget.onBack();
  }

  Future<void> _toggleFullScreen() async {
    final bool next = await PlayerWindow.toggleFullScreen();
    if (!mounted) return;
    setState(() => _fullScreen = next);
    _show();
  }

  /// 移动端横竖屏切换；桌面窗口有自己的尺寸控制，用不上这个。
  ///
  /// 只声明目标方向，系统转过去后 `MediaQuery` 会随之变化，按钮图标自己翻转。
  /// 退出播放页时 `PlayerPage._exitPlaybackUi` 会把允许方向恢复成竖屏 + 横屏，
  /// 因此这里锁死的方向不会带出播放页。
  Future<void> _toggleOrientation() async {
    final bool toLandscape =
        MediaQuery.orientationOf(context) != Orientation.landscape;
    await SystemChrome.setPreferredOrientations(toLandscape
        ? const <DeviceOrientation>[
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : const <DeviceOrientation>[DeviceOrientation.portraitUp]);
    _show();
  }

  // ---------------------------------------------------------------- 构建

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      // translucent：不吞掉子节点的命中，自己也照样收到悬停事件。
      child: Listener(
        behavior: HitTestBehavior.translucent,
        // 悬停只做显示，不抢焦点：此时选集面板可能正开着。
        onPointerHover: PlatformInfo.isDesktop
            ? (PointerHoverEvent _) => _show(grabFocus: false)
            : null,
        child: _buildStack(context),
      ),
    );
  }

  Widget _buildStack(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        // 必须在 builder 内部取值：锁定状态变化时只有这里会重建。
        final bool locked = controller.locked;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 底层手势区：始终铺满。锁定时播放类手势全部置空。
            //
            // 单击是唯一保留的手势 —— 它只是唤出 / 收起控制栏，本身不改变播放。
            // 少了它，返回按钮一旦被收起就再也点不到，等于把人锁死在播放页里。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _focusNode.requestFocus();
                _toggle();
              },
              onDoubleTapDown:
                  locked ? null : (d) => _doubleTapPos = d.localPosition,
              onDoubleTap: locked ? null : _onDoubleTap,
              onLongPressStart: locked ? null : _onLongPressStart,
              onLongPressEnd: locked ? null : _onLongPressEnd,
              onHorizontalDragStart: locked ? null : _onHorizontalDragStart,
              onHorizontalDragUpdate: locked ? null : _onHorizontalDragUpdate,
              onHorizontalDragEnd: locked ? null : _onHorizontalDragEnd,
              onVerticalDragStart: locked ? null : _onVerticalDragStart,
              onVerticalDragUpdate: locked ? null : _onVerticalDragUpdate,
              onVerticalDragEnd: locked ? null : _onVerticalDragEnd,
              child: const SizedBox.expand(),
            ),

            if (controller.error != null && !controller.buffering)
              PlayerErrorPanel(
                message: controller.error!,
                onRetry: controller.retry,
              ),

            if (controller.fallbackTrying != null ||
                controller.fallbackNotice != null)
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.paddingOf(context).top + 56,
                child: Center(
                  child: PlayerFallbackBanner(
                    trying: controller.fallbackTrying,
                    notice: controller.fallbackNotice,
                  ),
                ),
              ),

            if (_visible) ...<Widget>[
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: PlayerTopBar(
                  title: controller.task.title,
                  subtitle: controller.task.subtitle,
                  locked: locked,
                  fullScreen: _fullScreen,
                  onBack: widget.onBack,
                  onToggleOrientation: _toggleOrientation,
                  onToggleFullScreen: _toggleFullScreen,
                  onInfo: () {
                    _openInfoSheet();
                    _scheduleHide();
                  },
                  onEpisodes: () {
                    _openEpisodeSheet();
                    _scheduleHide();
                  },
                ),
              ),
              if (!locked) ...<Widget>[
                PlayerCenterButton(
                  buffering: controller.buffering,
                  starting: controller.starting,
                  playing: controller.playing,
                  onTap: () {
                    controller.togglePlay();
                    _show();
                  },
                ),
                _buildBottomBar(context),
              ],
              Positioned(
                left: 4,
                top: 0,
                bottom: 0,
                child: Center(
                  child: PlayerLockButton(
                    locked: locked,
                    onTap: () {
                      controller.toggleLock();
                      _show();
                    },
                  ),
                ),
              ),
            ],
            // 片头里才出现的「跳过片头」。不随控制栏一起隐藏 —— 控制栏一收，
            // 这个入口就再也点不到了，而这恰恰是用户最想按的时候。
            if (controller.inIntro)
              Positioned(
                right: 16,
                bottom: ((_visible ? 96 : 20) +
                    MediaQuery.paddingOf(context).bottom),
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      controller.skipIntro();
                      _show();
                    },
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            '跳过片头',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.skip_next, size: 18, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            _buildGestureIndicator(context),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Duration position = controller.position;
    final Duration duration = controller.duration;
    final double totalMs = duration.inMilliseconds.toDouble();
    final double value = totalMs <= 0
        ? 0
        : (controller.seeking
            ? controller.seekRatio
            : controller.positionRatio);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 6,
          left: 8,
          right: 8,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: <Color>[Colors.black87, Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox(
                  width: 58,
                  child: Text(
                    formatDurationShort(position),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures()
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: value.clamp(0.0, 1.0),
                    onChanged: totalMs <= 0
                        ? null
                        : (double v) {
                            controller.seek(
                              Duration(milliseconds: (v * totalMs).round()),
                            );
                            _show();
                          },
                  ),
                ),
                SizedBox(
                  width: 58,
                  child: Text(
                    formatDurationShort(duration),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures()
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: <Widget>[
                // 窄屏（竖屏手机）放不下这么多个药丸，让它们横向滚动，
                // 而不是把上一集 / 下一集挤出去。
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        PlayerPillButton(
                          label: '${controller.rate}x',
                          onTap: () {
                            _openRateSheet();
                            _scheduleHide();
                          },
                        ),
                        const SizedBox(width: 8),
                        PlayerPillButton(
                          label: controller.fitLabel,
                          onTap: () {
                            controller.cycleFit();
                            _scheduleHide();
                          },
                        ),
                        if (controller.audioTracks.length > 1) ...<Widget>[
                          const SizedBox(width: 8),
                          PlayerPillButton(
                            label: '音轨',
                            icon: Icons.audiotrack,
                            tooltip: '切换音轨',
                            onTap: () {
                              _openTrackSheet();
                              _scheduleHide();
                            },
                          ),
                        ],
                        const SizedBox(width: 8),
                        PlayerPillButton(
                          label: _sleepLabel,
                          icon: Icons.bedtime_outlined,
                          active: controller.sleepRemaining != null ||
                              controller.sleepAtEnd,
                          tooltip: '定时关闭',
                          onTap: () {
                            _openSleepSheet();
                            _scheduleHide();
                          },
                        ),
                        const SizedBox(width: 8),
                        PlayerPillButton(
                          label: '片头尾',
                          icon: Icons.content_cut,
                          active:
                              controller.introMs > 0 || controller.outroMs > 0,
                          tooltip: '片头片尾标记',
                          onTap: () {
                            _openSkipSheet();
                            _scheduleHide();
                          },
                        ),
                        // 清晰度：纯信息，不做成按钮，点它不如点顶栏的"视频信息"。
                        if (controller.resolutionLabel != null) ...<Widget>[
                          const SizedBox(width: 8),
                          PlayerInfoChip(label: controller.resolutionLabel!),
                        ],
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
                if (controller.task.hasPrev)
                  IconButton(
                    tooltip: '上一集',
                    color: Colors.white,
                    icon: const Icon(Icons.skip_previous),
                    onPressed: () {
                      controller.previous();
                      _show();
                    },
                  ),
                if (controller.task.hasNext)
                  IconButton(
                    tooltip: '下一集',
                    color: Colors.white,
                    icon: const Icon(Icons.skip_next),
                    onPressed: () {
                      controller.next();
                      _show();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 弹层

  /// 定时药丸上显示的文字：开着倒计时就显示剩余，否则是「本集结束 / 定时」。
  String get _sleepLabel {
    final Duration? left = controller.sleepRemaining;
    if (left != null) return formatDurationShort(left);
    if (controller.sleepAtEnd) return '本集结束';
    return '定时';
  }

  void _openRateSheet() {
    showRateSheet(
      context,
      current: controller.rate,
      onPick: controller.setRate,
    );
  }

  void _openEpisodeSheet() {
    showEpisodeSheet(
      context,
      title: controller.task.title,
      lines: controller.task.item.playLines,
      lineIndex: controller.task.lineIndex,
      episodeIndex: controller.task.episodeIndex,
      onPick: (int line, int episode) {
        controller.selectEpisode(line, episode);
        _show();
      },
    );
  }

  void _openInfoSheet() {
    showInfoSheet(
      context,
      resolution: controller.resolutionLabel,
      fps: controller.fpsLabel,
      videoCodec: controller.videoCodec,
      videoDecoder: controller.videoDecoder,
      pixelFormat: controller.pixelFormat,
      audioCodec: controller.audioCodec,
      audioChannels: controller.audioChannels,
      audioSampleRate: controller.audioSampleRate,
    );
  }

  void _openTrackSheet() {
    showTrackSheet(context, controller);
  }

  void _openSleepSheet() {
    showSleepSheet(context, controller);
  }

  void _openSkipSheet() {
    showSkipSheet(context, controller);
  }

  Widget _buildGestureIndicator(BuildContext context) {
    if (controller.seeking) {
      return Center(
        child: PlayerGlassBox(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                formatDurationShort(controller.position),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '/ ${formatDurationShort(controller.duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (controller.adjustingVolume || controller.adjustingBrightness) {
      final bool volume = controller.adjustingVolume;
      final double ratio =
          volume ? controller.gestureVolume : controller.gestureBrightness;
      return Center(
        child: PlayerGlassBox(
          width: 120,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                volume
                    ? (ratio <= 0.01 ? Icons.volume_off : Icons.volume_up)
                    : Icons.brightness_6,
                color: Colors.white,
                size: 26,
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Colors.white24,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(ratio * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // 长按临时提速：一直显示到松手，不用 OSD 的 1.4 秒自动消失。
    if (_bursting) {
      return const Center(
        child: PlayerGlassBox(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.fast_forward, color: Colors.white, size: 20),
              SizedBox(width: 6),
              Text(
                '${K.burstRate}x 快放中',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 键盘操作的浮层提示（音量 / 快进步长）。
    if (_osd != null) {
      return Center(
        child: PlayerGlassBox(
          child: Text(
            _osd!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
