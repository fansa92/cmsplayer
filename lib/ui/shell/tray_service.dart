import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../core/logger.dart';
import '../../core/utils/responsive.dart';
import '../../state/playback_bridge.dart';

/// 托盘菜单里的一项。
///
/// 与具体插件解耦：生产实现把它翻成 `MenuItem`，测试实现直接当数据看，
/// 断言菜单文字时不必去碰平台通道。
@immutable
class TrayEntry {
  const TrayEntry({required this.key, required this.label, this.enabled = true});

  /// 分隔线。
  const TrayEntry.separator()
      : key = '',
        label = '',
        enabled = true;

  final String key;
  final String label;
  final bool enabled;

  bool get isSeparator => key.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is TrayEntry &&
      other.key == key &&
      other.label == label &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(key, label, enabled);
}

/// 托盘后端。生产实现走 `tray_manager`，测试换成内存实现。
abstract class TrayAdapter {
  Future<void> install({
    required String iconPath,
    required bool template,
    required String toolTip,
    required List<TrayEntry> menu,
    required ValueChanged<String> onMenu,
    required VoidCallback onLeftClick,
    required VoidCallback onRightClick,
  });

  Future<void> updateMenu(List<TrayEntry> menu);

  Future<void> updateToolTip(String text);

  Future<void> dispose();
}

/// 系统托盘：常驻图标 + 播放控制菜单。
///
/// 菜单只有五项，但每一项都跟着播放状态变：
/// 没有播放器时播放 / 上一集 / 下一集全部置灰，正在播时「播放」变成「暂停」。
class TrayService {
  TrayService._();

  static TrayService instance = TrayService._();

  /// 测试注入点：给一个内存后端就不碰真实托盘。
  @visibleForTesting
  static TrayAdapter Function()? adapterFactory;

  TrayAdapter? _adapter;
  bool _ready = false;
  List<TrayEntry> _menu = const <TrayEntry>[];
  String _toolTip = '';

  Future<void> Function()? _onShow;
  Future<void> Function()? _onQuit;

  /// 托盘图标是否已经挂上。外壳据此决定关闭按钮是收托盘还是直接退出。
  bool get ready => _ready;

  /// 托盘图标路径。Windows 只认 .ico，其余平台读 png。
  static String get iconAsset => PlatformInfo.isWindows
      ? 'assets/icons/tray_icon.ico'
      : 'assets/icons/tray_icon.png';

  /// 在 runApp 之后调用。失败（例如 Linux 缺少 appindicator）不影响应用运行，
  /// 只是关闭按钮退化成系统默认行为。
  Future<void> start({
    required Future<void> Function() onShow,
    required Future<void> Function() onQuit,
  }) async {
    if (_ready || !PlatformInfo.isDesktop) return;
    _onShow = onShow;
    _onQuit = onQuit;

    final TrayAdapter adapter = adapterFactory?.call() ?? _TrayManagerAdapter();
    _adapter = adapter;
    try {
      await adapter.install(
        iconPath: iconAsset,
        template: false,
        toolTip: _toolTipText(),
        menu: _buildMenu(),
        onMenu: _handleMenu,
        onLeftClick: _showWindow,
        onRightClick: _noop,
      );
      _ready = true;
      _menu = _buildMenu();
      PlaybackBridge.active.addListener(_sync);
      PlaybackBridge.playing.addListener(_sync);
      PlaybackBridge.title.addListener(_sync);
      AppLog.d('TrayService', 'ready');
    } on Object catch (e) {
      _adapter = null;
      _ready = false;
      AppLog.d('TrayService', 'start failed: $e');
    }
  }

  List<TrayEntry> _buildMenu() {
    final bool hasPlayer = PlaybackBridge.active.value;
    final bool playing = PlaybackBridge.playing.value;
    return <TrayEntry>[
      const TrayEntry(key: 'show', label: '显示主窗口'),
      const TrayEntry.separator(),
      TrayEntry(
        key: 'toggle',
        label: playing ? '暂停' : '播放',
        enabled: hasPlayer,
      ),
      TrayEntry(key: 'prev', label: '上一集', enabled: hasPlayer),
      TrayEntry(key: 'next', label: '下一集', enabled: hasPlayer),
      const TrayEntry.separator(),
      const TrayEntry(key: 'quit', label: '退出'),
    ];
  }

  String _toolTipText() {
    final String title = PlaybackBridge.title.value;
    if (title.isEmpty) return 'CMSPlayer';
    return title.length > 48 ? 'CMSPlayer · ${title.substring(0, 48)}…' : 'CMSPlayer · $title';
  }

  void _sync() {
    if (!_ready) return;
    final List<TrayEntry> menu = _buildMenu();
    if (!_sameMenu(menu, _menu)) {
      _menu = menu;
      unawaited(_adapter?.updateMenu(menu) ?? Future<void>.value());
    }
    final String tip = _toolTipText();
    if (tip != _toolTip) {
      // 首次同步时 _toolTip 还是空的：install 已经设过一次，这里只是对齐缓存。
      _toolTip = tip;
      unawaited(_adapter?.updateToolTip(tip) ?? Future<void>.value());
    }
  }

  static bool _sameMenu(List<TrayEntry> a, List<TrayEntry> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _handleMenu(String key) {
    AppLog.d('TrayService', 'menu: $key');
    switch (key) {
      case 'show':
        unawaited(_showWindow());
        break;
      case 'toggle':
        unawaited(PlaybackBridge.togglePlay());
        break;
      case 'prev':
        unawaited(PlaybackBridge.previous());
        break;
      case 'next':
        unawaited(PlaybackBridge.next());
        break;
      case 'quit':
        unawaited(_quit());
        break;
    }
  }

  Future<void> _showWindow() async {
    await _onShow?.call();
  }

  Future<void> _quit() async {
    await dispose();
    await _onQuit?.call();
  }

  Future<void> _noop() async {}

  /// 拆掉托盘图标并解绑监听。退出前调用，也用于测试收尾。
  Future<void> dispose() async {
    if (_ready) {
      PlaybackBridge.active.removeListener(_sync);
      PlaybackBridge.playing.removeListener(_sync);
      PlaybackBridge.title.removeListener(_sync);
    }
    _ready = false;
    _menu = const <TrayEntry>[];
    _toolTip = '';
    final TrayAdapter? adapter = _adapter;
    _adapter = null;
    try {
      await adapter?.dispose();
    } on Object catch (e) {
      AppLog.d('TrayService', 'dispose failed: $e');
    }
  }

  @visibleForTesting
  static Future<void> resetForTest() async {
    await instance.dispose();
    instance = TrayService._();
    adapterFactory = null;
  }
}

/// 真实实现：把 [TrayEntry] 翻成 `tray_manager` 的菜单。
class _TrayManagerAdapter with TrayListener implements TrayAdapter {
  ValueChanged<String>? _onMenu;
  VoidCallback? _onLeft;
  VoidCallback? _onRight;
  bool _installed = false;

  @override
  Future<void> install({
    required String iconPath,
    required bool template,
    required String toolTip,
    required List<TrayEntry> menu,
    required ValueChanged<String> onMenu,
    required VoidCallback onLeftClick,
    required VoidCallback onRightClick,
  }) async {
    _onMenu = onMenu;
    _onLeft = onLeftClick;
    _onRight = onRightClick;
    trayManager.addListener(this);
    _installed = true;
    await trayManager.setIcon(iconPath, isTemplate: template, iconSize: 18);
    await trayManager.setToolTip(toolTip);
    await trayManager.setContextMenu(_build(menu));
  }

  Menu _build(List<TrayEntry> entries) {
    return Menu(
      items: <MenuItem>[
        for (final TrayEntry e in entries)
          if (e.isSeparator)
            MenuItem.separator()
          else
            MenuItem(
              key: e.key,
              label: e.label,
              disabled: !e.enabled,
              onClick: (MenuItem item) => _onMenu?.call(e.key),
            ),
      ],
    );
  }

  @override
  Future<void> updateMenu(List<TrayEntry> menu) async {
    await trayManager.setContextMenu(_build(menu));
  }

  @override
  Future<void> updateToolTip(String text) async {
    await trayManager.setToolTip(text);
  }

  @override
  Future<void> dispose() async {
    if (_installed) trayManager.removeListener(this);
    _installed = false;
    await trayManager.destroy();
  }

  @override
  void onTrayIconMouseDown() => _onLeft?.call();

  @override
  void onTrayIconRightMouseDown() => _onRight?.call();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final String? key = menuItem.key;
    if (key != null) _onMenu?.call(key);
  }
}
