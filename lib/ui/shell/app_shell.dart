import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/responsive.dart';
import '../../data/models/vod_source.dart';
import '../../state/browse_store.dart';
import '../../state/search_store.dart';
import '../../state/source_store.dart';
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
  SourceStore? _watched;
  bool _attached = false;

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
    });
  }

  @override
  void dispose() {
    _watched?.removeListener(_onSourceChanged);
    super.dispose();
  }

  void _select(int index) {
    setState(() => _index = index);
    if (index == 2) {
      context.read<SearchStore>().loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SourceStore sourceStore = context.watch<SourceStore>();

    if (sourceStore.loading) {
      return const Scaffold(body: PageLoading(label: '正在加载资源站…'));
    }

    final VodSource? active = sourceStore.active;
    if (active == null) {
      return const SourcePage(asHome: true);
    }

    final bool useRail = context.useRail;

    final IndexedStack body = IndexedStack(
      index: _index,
      children: const <Widget>[
        HomePage(),
        CategoryPage(),
        SearchPage(),
        FavoritesPage(),
        HistoryPage(),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: useRail ? 16 : 12,
        title: SourceSwitcher(source: active),
        actions: <Widget>[
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
                    for (final _Destination d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
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
                for (final _Destination d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            ),
    );
  }
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
