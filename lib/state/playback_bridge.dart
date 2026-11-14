import 'package:flutter/foundation.dart';

import '../data/models/play_task.dart';
import '../ui/player/player_controls_binding.dart';

/// 当前播放器的全局把手。
///
/// 托盘菜单、系统媒体键这类「播放器之外」的入口需要一个办法去控制播放，
/// 但它们都不在播放页的 widget 树里，拿不到那个 [PlayerController]。
/// 播放页开播时挂上来、退出时摘掉，桥接层再把播放状态转成几个
/// [ValueNotifier]，托盘就能据此刷新菜单文字。
class PlaybackBridge {
  PlaybackBridge._();

  static PlayerControlsBinding? _controls;
  static ChangeNotifier? _notifier;

  /// 有没有正在播放的页面（决定托盘菜单里的播放项能不能点）。
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// 是否正在播放（决定菜单显示「播放」还是「暂停」）。
  static final ValueNotifier<bool> playing = ValueNotifier<bool>(false);

  /// 当前影片标题，托盘悬浮提示用。
  static final ValueNotifier<String> title = ValueNotifier<String>('');

  static bool get hasPlayer => _controls != null;

  /// 播放页挂载时调用。重复挂同一个实例是安全的。
  static void attach(PlayerControlsBinding controls) {
    if (identical(_controls, controls)) return;
    detach();
    _controls = controls;
    if (controls is ChangeNotifier) {
      final ChangeNotifier notifier = controls as ChangeNotifier;
      notifier.addListener(_pull);
      _notifier = notifier;
    }
    _pull();
  }

  /// 播放页销毁时调用。传 [controls] 时只摘掉自己，避免后挂的先摘光。
  static void detach([PlayerControlsBinding? controls]) {
    if (controls != null && !identical(_controls, controls)) return;
    _notifier?.removeListener(_pull);
    _notifier = null;
    _controls = null;
    active.value = false;
    playing.value = false;
    title.value = '';
  }

  static Future<void> togglePlay() async {
    await _controls?.togglePlay();
  }

  static Future<void> next() async {
    await _controls?.next();
  }

  static Future<void> previous() async {
    await _controls?.previous();
  }

  /// 把一个播放任务说成人话：`繁花 · 第 03 集`。
  static String describe(PlayTask task) {
    final String episode = task.episode?.name.trim() ?? '';
    return episode.isEmpty ? task.title : '${task.title} · $episode';
  }

  static void _pull() {
    final PlayerControlsBinding? controls = _controls;
    if (controls == null) return;
    active.value = true;
    playing.value = controls.playing;
    title.value = describe(controls.task);
  }

  @visibleForTesting
  static void resetForTest() {
    detach();
  }
}
