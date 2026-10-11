import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/storage/settings_store.dart';
import 'core/theme/app_theme.dart';
import 'state/app_state.dart';
import 'state/browse_store.dart';
import 'state/favorites_store.dart';
import 'state/history_store.dart';
import 'state/search_store.dart';
import 'state/source_store.dart';
import 'state/sync_store.dart';
import 'ui/shell/app_shell.dart';

/// 应用根组件：负责依赖注入与主题切换。
class CmsPlayerApp extends StatefulWidget {
  const CmsPlayerApp({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<CmsPlayerApp> createState() => _CmsPlayerAppState();
}

class _CmsPlayerAppState extends State<CmsPlayerApp> {
  late final AppState _appState = AppState(widget.settings);
  late final SourceStore _sourceStore = SourceStore(widget.settings);
  late final BrowseStore _browseStore = BrowseStore();
  late final SearchStore _searchStore = SearchStore();
  late final FavoritesStore _favoritesStore = FavoritesStore();
  late final HistoryStore _historyStore = HistoryStore();

  /// 同步。依赖上面三个 Store —— [SyncStore] 的构造参数就是它们。
  ///
  /// `late final` 是惰性初始化的，首次访问时才构造，所以这里引用前面的
  /// 字段不会踩到初始化顺序问题。
  late final SyncStore _syncStore = SyncStore(
    widget.settings,
    _historyStore,
    _favoritesStore,
    _sourceStore,
  );

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _sourceStore.load();
    await _favoritesStore.load();
    await _historyStore.load();
    // 同步配置只是读几个字符串，不值得塞进上面的 await 链里拖慢启动；
    // 但要保证同步页第一次打开时它已经就绪。
    _syncStore.load();
  }

  @override
  void dispose() {
    _appState.dispose();
    _sourceStore.dispose();
    _browseStore.dispose();
    _searchStore.dispose();
    _favoritesStore.dispose();
    _historyStore.dispose();
    _syncStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: _appState),
        ChangeNotifierProvider<SourceStore>.value(value: _sourceStore),
        ChangeNotifierProvider<BrowseStore>.value(value: _browseStore),
        ChangeNotifierProvider<SearchStore>.value(value: _searchStore),
        ChangeNotifierProvider<FavoritesStore>.value(value: _favoritesStore),
        ChangeNotifierProvider<HistoryStore>.value(value: _historyStore),
        ChangeNotifierProvider<SyncStore>.value(value: _syncStore),
      ],
      child: Consumer<AppState>(
        builder: (BuildContext context, AppState app, _) {
          return MaterialApp(
            title: K.appNameCn,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: app.themeMode,
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
