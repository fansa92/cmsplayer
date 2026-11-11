import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import 'battery_badge.dart';

/// 播放器控制层的外观组件。
///
/// 这里所有颜色都是「白色 + 黑色半透明」，不跟随 App 主题 —— 背景是视频
/// 画面本身，深浅不可控，只有白字加暗色遮罩在任何画面上都能看清。
/// 组件的定位（`Positioned`）留在 [PlayerControls] 里：它的 Stack 结构由
/// 手势层决定，组件自己只管长什么样。
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.locked,
    required this.fullScreen,
    required this.onBack,
    required this.onToggleOrientation,
    required this.onToggleFullScreen,
    required this.onInfo,
    required this.onEpisodes,
  });

  final String title;
  final String subtitle;
  final bool locked;
  final bool fullScreen;
  final VoidCallback onBack;
  final VoidCallback onToggleOrientation;
  final VoidCallback onToggleFullScreen;
  final VoidCallback onInfo;
  final VoidCallback onEpisodes;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Container(
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
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
          ),
          // 电量是纯信息，锁定时照样显示 —— 看片最怕的就是突然没电。
          if (PlatformInfo.isMobile) const BatteryBadge(),
          if (PlatformInfo.isMobile && !locked)
            IconButton(
              tooltip: isLandscape ? '切换到竖屏' : '横屏播放',
              color: Colors.white,
              icon: Icon(isLandscape
                  ? Icons.stay_current_portrait
                  : Icons.stay_current_landscape),
              onPressed: onToggleOrientation,
            ),
          if (PlatformInfo.isDesktop)
            IconButton(
              tooltip: fullScreen ? '退出全屏 (Esc)' : '全屏 (F)',
              color: Colors.white,
              icon: Icon(fullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
              onPressed: locked ? null : onToggleFullScreen,
            ),
          if (!locked)
            IconButton(
              tooltip: '视频信息',
              color: Colors.white,
              icon: const Icon(Icons.info_outline),
              onPressed: onInfo,
            ),
          if (!locked)
            IconButton(
              tooltip: '选集',
              color: Colors.white,
              icon: const Icon(Icons.playlist_play),
              onPressed: onEpisodes,
            ),
        ],
      ),
    );
  }
}

/// 中央的播放/暂停按钮，缓冲时换成转圈。
class PlayerCenterButton extends StatelessWidget {
  const PlayerCenterButton({
    super.key,
    required this.buffering,
    required this.starting,
    required this.playing,
    required this.onTap,
  });

  final bool buffering;
  final bool starting;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (buffering || starting) {
      return const Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: Colors.white,
          ),
        ),
      );
    }

    return Center(
      child: IconButton(
        iconSize: 56,
        color: Colors.white,
        style: IconButton.styleFrom(
          backgroundColor: Colors.black38,
          padding: const EdgeInsets.all(20),
        ),
        onPressed: onTap,
        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}

/// 锁定按钮：屏幕最左侧、垂直居中。
///
/// 放最左是因为中央已经有播放键，而顶栏在手机上要留给标题、电量、横屏
/// 和选集；最左侧这条竖带平时空着，既好找也不会遮到画面主体。
class PlayerLockButton extends StatelessWidget {
  const PlayerLockButton({
    super.key,
    required this.locked,
    required this.onTap,
  });

  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: locked ? '已锁定播放控件，点击解锁' : '锁定播放控件',
      color: Colors.white,
      style: IconButton.styleFrom(backgroundColor: Colors.black26),
      icon: Icon(locked ? Icons.lock : Icons.lock_open),
      onPressed: onTap,
    );
  }
}

/// 降级提示条：「正在尝试备用地址…」/「已切换到 XX 源」。
///
/// 放在控制栏之外 —— 降级发生时控制栏可能已经自动隐藏，
/// 而用户正需要知道播放器在干什么。
class PlayerFallbackBanner extends StatelessWidget {
  const PlayerFallbackBanner({super.key, this.trying, this.notice});

  /// 非空表示正在尝试，带转圈。
  final String? trying;

  /// 非空表示已经切过去了。
  final String? notice;

  String? get _text => trying ?? notice;

  @override
  Widget build(BuildContext context) {
    final String? text = _text;
    if (text == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (trying != null)
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else
            const Icon(Icons.swap_horiz, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// 播放失败面板。
class PlayerErrorPanel extends StatelessWidget {
  const PlayerErrorPanel({
    super.key,
    required this.message,
    required this.onRetry,
  });

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

/// 玻璃质感的小药丸按钮（倍速、画面比例、音轨、定时）。
///
/// [icon] 非空时在文字前带一个小图标；[active] 用于「已经生效」的状态
/// （例如定时关闭已开），靠提高不透明度区分，不换颜色 —— 播放器里所有控件
/// 都是白字，突然蹦出一个彩色按钮会很跳。
class PlayerPillButton extends StatelessWidget {
  const PlayerPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.active = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget pill = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white38 : Colors.white24,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
    if (tooltip == null) return pill;
    return Tooltip(message: tooltip!, child: pill);
  }
}

/// 只读信息标签（清晰度）。
///
/// 长得像 [PlayerPillButton] 但不可点，所以不做成 InkWell —— 一个点不动的
/// 按钮比一段普通文字更让人困惑。
class PlayerInfoChip extends StatelessWidget {
  const PlayerInfoChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 半透明圆角浮层，用于进度 / 音量 / 亮度的手势提示。
class PlayerGlassBox extends StatelessWidget {
  const PlayerGlassBox({super.key, required this.child, this.width});

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
