import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/utils/formatter.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/play_line.dart';
import 'player_controller.dart';
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

  final PlayerController controller;
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

  PlayerController get controller => widget.controller;

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
    await controller.stepVolume(delta);
    if (!mounted) return;
    _showOsd('音量 ${controller.volume.round()}%');
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

    switch (key) {
      case LogicalKeyboardKey.escape:
        // 有焦点就说明播放页在最上层，重复触发无副作用。
        _handleEscape();
        return KeyEventResult.handled;

      // 播放控制类按键不吃长按重复，否则按住空格会疯狂切换暂停。
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        if (!repeat) {
          controller.togglePlay();
          _show();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyF:
        if (!repeat) _toggleFullScreen();
        return KeyEventResult.handled;

      // 下面这些按键长按应当连续生效（按住方向键持续快进 / 调音量）。
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.keyJ:
        controller.seekBy(const Duration(seconds: -10));
        _showOsd('快退 10 秒');
        _show();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.keyL:
        controller.seekBy(const Duration(seconds: 10));
        _showOsd('快进 10 秒');
        _show();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowUp:
        _stepVolume(5);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowDown:
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
            // 底层手势区：始终铺满。锁定时全部回调置 null。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: locked ? null : () {
                _focusNode.requestFocus();
                _toggle();
              },
              onDoubleTap: locked ? null : () {
                controller.togglePlay();
                _show();
              },
              onHorizontalDragStart: locked ? null : _onHorizontalDragStart,
              onHorizontalDragUpdate: locked ? null : _onHorizontalDragUpdate,
              onHorizontalDragEnd: locked ? null : _onHorizontalDragEnd,
              onVerticalDragStart: locked ? null : _onVerticalDragStart,
              onVerticalDragUpdate: locked ? null : _onVerticalDragUpdate,
              onVerticalDragEnd: locked ? null : _onVerticalDragEnd,
              child: const SizedBox.expand(),
            ),

            if (controller.error != null && !controller.buffering)
              _ErrorPanel(
                message: controller.error!,
                onRetry: controller.retry,
              ),

            if (controller.locked)
              Center(
                child: IconButton(
                  tooltip: '解锁',
                  iconSize: 36,
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    padding: const EdgeInsets.all(16),
                  ),
                  onPressed: () {
                    controller.toggleLock();
                    _show();
                  },
                  icon: const Icon(Icons.lock),
                ),
              )
            else ...<Widget>[
              if (_visible) ...<Widget>[
                _buildTopBar(context),
                _buildCenter(context),
                _buildBottomBar(context),
              ],
              _buildGestureIndicator(context),
            ],
          ],
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 6,
          left: 8,
          right: 8,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Colors.black87, Colors.transparent],
          ),
        ),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: '返回',
              color: Colors.white,
              icon: const Icon(Icons.arrow_back),
              onPressed: widget.onBack,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    controller.task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (controller.task.subtitle.isNotEmpty)
                    Text(
                      controller.task.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            if (PlatformInfo.isMobile)
              IconButton(
                tooltip: isLandscape ? '切换到竖屏' : '横屏播放',
                color: Colors.white,
                icon: Icon(isLandscape
                    ? Icons.stay_current_portrait
                    : Icons.stay_current_landscape),
                onPressed: _toggleOrientation,
              ),
            if (PlatformInfo.isDesktop)
              IconButton(
                tooltip: _fullScreen ? '退出全屏 (Esc)' : '全屏 (F)',
                color: Colors.white,
                icon: Icon(
                  _fullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
                onPressed: _toggleFullScreen,
              ),
            IconButton(
              tooltip: '选集',
              color: Colors.white,
              icon: const Icon(Icons.playlist_play),
              onPressed: () {
                _showEpisodeSheet(context);
                _scheduleHide();
              },
            ),
            IconButton(
              tooltip: controller.locked ? '已锁定，点击解锁' : '锁定屏幕',
              color: Colors.white,
              icon: Icon(controller.locked ? Icons.lock : Icons.lock_open),
              onPressed: () {
                controller.toggleLock();
                _show();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenter(BuildContext context) {
    final bool showSpinner = controller.buffering || controller.starting;

    return Center(
      child: showSpinner
          ? const SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            )
          : IconButton(
              iconSize: 56,
              color: Colors.white,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black38,
                padding: const EdgeInsets.all(20),
              ),
              onPressed: () {
                controller.togglePlay();
                _show();
              },
              icon: Icon(
                controller.playing ? Icons.pause : Icons.play_arrow,
              ),
            ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Duration position = controller.position;
    final Duration duration = controller.duration;
    final double totalMs = duration.inMilliseconds.toDouble();
    final double value = totalMs <= 0
        ? 0
        : (controller.seeking ? controller.seekRatio : controller.positionRatio);

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
                      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
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
                      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: <Widget>[
                _PillButton(
                  label: '${controller.rate}x',
                  onTap: () {
                    _showRateSheet(context);
                    _scheduleHide();
                  },
                ),
                const SizedBox(width: 8),
                _PillButton(
                  label: controller.fitLabel,
                  onTap: () {
                    controller.cycleFit();
                    _scheduleHide();
                  },
                ),
                const Spacer(),
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

  Widget _buildGestureIndicator(BuildContext context) {
    if (controller.seeking) {
      return Center(
        child: _GlassBox(
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
      final double ratio = volume
          ? controller.gestureVolume
          : controller.gestureBrightness;
      return Center(
        child: _GlassBox(
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

    // 键盘操作的浮层提示（音量 / 快进步长）。
    if (_osd != null) {
      return Center(
        child: _GlassBox(
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

  // ---------------------------------------------------------------- 面板

  Future<void> _showRateSheet(BuildContext context) async {
    final double? result = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => SafeArea(
        child: Wrap(
          children: <Widget>[
            for (final double rate in K.playRates)
              ListTile(
                dense: true,
                leading: Icon(
                  rate == controller.rate ? Icons.check : Icons.speed,
                  size: 20,
                ),
                title: Text('${rate}x'),
                onTap: () => Navigator.of(ctx).pop(rate),
              ),
          ],
        ),
      ),
    );
    if (result != null) await controller.setRate(result);
  }

  Future<void> _showEpisodeSheet(BuildContext context) async {
    final List<PlayLine> lines = controller.task.item.playLines;
    if (lines.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.65,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  controller.task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              for (int li = 0; li < lines.length; li++) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                  child: Text(
                    lines[li].name,
                    style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                          color: Theme.of(ctx).colorScheme.primary,
                        ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (int ei = 0;
                          ei < lines[li].episodes.length;
                          ei++)
                        ActionChip(
                          label: Text(lines[li].episodes[ei].name),
                          avatar: (li == controller.task.lineIndex &&
                                  ei == controller.task.episodeIndex)
                              ? const Icon(Icons.play_arrow, size: 16)
                              : null,
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            controller.selectEpisode(li, ei);
                            _show();
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 子组件

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _GlassBox extends StatelessWidget {
  const _GlassBox({required this.child, this.width});

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, color: Colors.white, size: 34),
            const SizedBox(height: 12),
            const Text(
              '播放失败',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
