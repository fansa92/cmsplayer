import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/utils/formatter.dart';
import '../../data/models/play_line.dart';
import 'player_controller.dart';

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

  PlayerController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _visible = true;
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
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

  void _show() {
    if (!mounted) return;
    setState(() => _visible = true);
    _scheduleHide();
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

  // ---------------------------------------------------------------- 构建

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 底层手势区：始终铺满。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              onDoubleTap: () {
                controller.togglePlay();
                _show();
              },
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onVerticalDragStart: _onVerticalDragStart,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
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
              tooltip: '锁定',
              color: Colors.white,
              icon: const Icon(Icons.lock_open),
              onPressed: () {
                controller.toggleLock();
                _scheduleHide();
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
