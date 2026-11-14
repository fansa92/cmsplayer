import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/deep_link.dart';
import '../../core/utils/responsive.dart';
import 'app_shortcuts.dart';
import 'lazy_indexed_stack.dart';
import '../../data/models/vod_source.dart';
import '../../state/browse_store.dart';
import '../../state/favorites_store.dart';
import '../../state/home_store.dart';
import '../../state/search_store.dart';
import '../../state/source_store.dart';
import '../actions.dart';
import '../navigation.dart';
import '../pages/category_page.dart';
import '../pages/favorites_page.dart';
import '../pages/history_page.dart';
import '../pages/home_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';
import '../pages/source_page.dart';
import '../widgets/empty_state.dart';
import '../widgets/source_switcher.dart';

/// 主外壳：根据窗口宽度在「侧边导航栏」与「底部导航栏」之间切换。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<_Destination> _destinations = <_Destination>[
    _Destination('首页', Icons.home_outlined, Icons.home),
    _Destination('分类', Icons.grid_view_outlined, Icons.grid_view),
    _Destination('搜索', Icons.search_outlined, Icons.search),
    _Destination('收藏', Icons.favorite_outline, Icons.favorite),
    _Destination('历史', Icons.history_outlined, Icons.history),
  ];

  int _index = 0;

  /// 搜索框的焦点由外壳持有：快捷键可能在搜索页还没挂载时就要求聚焦。
  final FocusNode _searchFocus = FocusNode(debugLabel: 'shell-search');

  SourceStore? _watched;
  bool _attached = false;

  @override
  void initState() {
    super.initState();
    DeepLink.pendingImport.addListener(_consumeDeepLink);
    // 启动参数可能在外壳挂载前就解析好了，补一次首帧消费。
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeDeepLink());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSource();
  }

  void _syncSource() {
    final SourceStore store = context.read<SourceStore>();
    if (!identical(_watched, store)) {
      _watched?.removeListener(_onSourceChanged);
      _watched = store;
      store.addListener(_onSourceChanged);
    }
    _onSourceChanged();
  }

  void _onSourceChanged() {
    // 可能在 build 期间被触发，统一延后到帧结束，避免 notifyListeners 重入。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final VodSource? source = context.read<SourceStore>().active;
      if (source == null) return;
      final BrowseStore browse = context.read<BrowseStore>();
      if (_attached && browse.source?.id == source.id) return;
      _attached = true;
      browse.attach(source);
      context.read<HomeStore>().attach(source);
    });
  }

  /// 消费一次外部导入请求（`cmsplayer://import?url=…`）。
  void _consumeDeepLink() {
    final String? url = DeepLink.pendingImport.value;
    if (url == null || !mounted) return;
    DeepLink.pendingImport.value = null;
    unawaited(_importSources(url));
  }

  Future<void> _importSources(String url) async {
    try {
      final int added = await context.read<SourceStore>().importFromUrl(url);
      if (!mounted) return;
      AppActions.snack(
        context,
        added > 0 ? '已导入 $added 个资源站' : '这些资源站都已在列表里，没有新增',
      );
    } on Object catch (e) {
      if (!mounted) return;
      AppActions.snackError(context, e);
    }
  }

  @override
  void dispose() {
    DeepLink.pendingImport.removeListener(_consumeDeepLink);
    _watched?.removeListener(_onSourceChanged);
    _searchFocus.dispose();
    super.dispose();
  }

  void _select(int index) {
    setState(() => _index = index);
    if (index == 2) {
      context.read<SearchStore>().loadHistory();
    }
  }

  /// 快捷键「搜索」：切到搜索页并把光标放进输入框。
  ///
  /// 搜索页是懒挂载的，第一次切过去时节点还没进树，直接 requestFocus 不会
  /// 生效，所以放到这一帧结束之后再要焦点。
  void _focusSearch() {
    if (_index != 2) _select(2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
    });
  }

  Widget _pageFor(int index) => switch (index) {
        0 => const HomePage(),
        1 => const CategoryPage(),
        2 => SearchPage(focusNode: _searchFocus),
        3 => const FavoritesPage(),
        _ => const HistoryPage(),
      };

  /// 收藏页在导航里的序号。有更新时给它挂个角标。
  static const int _favoritesIndex = 3;

  Widget _navIcon(int index, IconData icon, int updated) {
    final Widget child = Icon(icon);
    if (index != _favoritesIndex || updated <= 0) return child;
    return Badge(label: Text('$updated'), child: child);
  }

  @override
  Widget build(BuildContext context) {
    final SourceStore sourceStore = context.watch<SourceStore>();
    final int updated = context.watch<FavoritesStore>().updatedCount;

    if (sourceStore.loading) {
      return const Scaffold(body: PageLoading(label: '正在加载资源站…'));
    }

    final VodSource? active = sourceStore.active;
    if (active == null) {
      return const SourcePage(asHome: true);
    }

    final bool useRail = context.useRail;

    final Widget body = LazyIndexedStack(
      index: _index,
      itemCount: _destinations.length,
      builder: _pageFor,
    );

    return AppShortcuts(
      tabCount: _destinations.length,
      onSelectTab: _select,
      onSearch: _focusSearch,
      child: ShellTabs(
        index: _index,
        select: _select,
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: useRail ? 16 : 12,
            title: SourceSwitcher(source: active),
            actions: <Widget>[
              IconButton(
                tooltip: '榜单',
                icon: const Icon(Icons.leaderboard_outlined),
                onPressed: () => AppRoutes.openRank(context),
              ),
              if (PlatformInfo.isDesktop)
                IconButton(
                  tooltip: '键盘快捷键 (?)',
                  icon: const Icon(Icons.keyboard_outlined),
                  onPressed: () => showShortcutHelp(context),
                ),
              IconButton(
                tooltip: '资源站管理',
                icon: const Icon(Icons.dns_outlined),
                onPressed: () => AppShellActions.openSourceManager(context),
              ),
              IconButton(
                tooltip: '设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: useRail
              ? Row(
                  children: <Widget>[
                    NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: _select,
                      extended: context.isExpanded,
                      minExtendedWidth: 132,
                      destinations: <NavigationRailDestination>[
                        for (int i = 0; i < _destinations.length; i++)
                          NavigationRailDestination(
                            icon: _navIcon(i, _destinations[i].icon, updated),
                            selectedIcon: _navIcon(
                              i,
                              _destinations[i].selectedIcon,
                              updated,
                            ),
                            label: Text(_destinations[i].label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1, thickness: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: useRail
              ? null
              : NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  destinations: <NavigationDestination>[
                    for (int i = 0; i < _destinations.length; i++)
                      NavigationDestination(
                        icon: _navIcon(i, _destinations[i].icon, updated),
                        selectedIcon: _navIcon(
                          i,
                          _destinations[i].selectedIcon,
                          updated,
                        ),
                        label: _destinations[i].label,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// 让壳内的页面能切换当前导航页。
///
/// 历史页是壳里 `IndexedStack` 的成员，没有路由可以 push ——
/// 只能由壳自己切页。首页「继续观看」横条上的「全部」按钮要走这条路，
/// 所以用这个 InheritedWidget 把切换能力递给子页面。
class ShellTabs extends InheritedWidget {
  const ShellTabs({
    super.key,
    required this.index,
    required this.select,
    required super.child,
  });

  /// 当前页序号，顺序与导航项一致。
  final int index;

  /// 切换到指定页。
  final void Function(int index) select;

  /// 历史页在导航里的序号。
  static const int historyIndex = 4;

  /// 取当前壳的页签控制器；不在壳里时返回 null。
  static ShellTabs? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellTabs>();

  @override
  bool updateShouldNotify(ShellTabs oldWidget) => oldWidget.index != index;
}

/// 从非 shell 页面复用的跳转入口。
class AppShellActions {
  AppShellActions._();

  static void openSourceManager(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SourcePage()),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
