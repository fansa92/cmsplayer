import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/app_state.dart';
import 'package:cms_player/state/browse_store.dart';
import 'package:cms_player/state/favorites_store.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/state/home_store.dart';
import 'package:cms_player/state/search_store.dart';
import 'package:cms_player/state/source_store.dart';
import 'package:cms_player/ui/pages/favorites_page.dart';
import 'package:cms_player/ui/pages/search_page.dart';
import 'package:cms_player/ui/shell/app_shell.dart';

import 'helpers/fakes.dart';

/// 外壳层：快捷键真的能切页，而不只是回调被调用。
void main() {
  useIsolatedStores();

  /// 首页的骨架屏是无限动画，`pumpAndSettle` 永远等不到静止帧；
  /// 这里手动推帧，既让异步任务落地又不等动画。
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await settle(tester);
  }

  testWidgets(
    'Ctrl+F 从首页切到搜索页，Ctrl+4 切到收藏页',
    (WidgetTester tester) async {
      // 资源站读写要走真实磁盘，必须放在 runAsync 里，
      // 否则 fake async 区里等不到 I/O 完成。
      final (SettingsStore, SourceStore) stores =
          (await tester.runAsync(() async {
        final SettingsStore settings = SettingsStore();
        await settings.init();
        final SourceStore sources = SourceStore(settings);
        await sources.load();
        final VodSource source = sourceOf('测试站');
        await sources.add(source);
        await sources.setActive(source);
        return (settings, sources);
      }))!;
      final SettingsStore settings = stores.$1;
      final SourceStore sources = stores.$2;

      useFakeApi(
        FakeHttpClient(
          (RecordedRequest req) => fakeJson(
            vodPageJson(
              classes: <Map<String, Object>>[
                <String, Object>{'type_id': 1, 'type_name': '电影'},
              ],
            ),
          ),
        ),
      );

      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: AppState(settings)),
            ChangeNotifierProvider<SourceStore>.value(value: sources),
            ChangeNotifierProvider<BrowseStore>.value(value: BrowseStore()),
            ChangeNotifierProvider<HomeStore>.value(value: HomeStore()),
            ChangeNotifierProvider<SearchStore>.value(value: SearchStore()),
            ChangeNotifierProvider<FavoritesStore>.value(
              value: FavoritesStore(),
            ),
            ChangeNotifierProvider<HistoryStore>.value(value: HistoryStore()),
          ],
          child: const MaterialApp(home: AppShell()),
        ),
      );
      await settle(tester);

      expect(find.byType(SearchPage), findsNothing, reason: '搜索页是懒挂载的');

      await press(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyF,
      );

      expect(find.byType(SearchPage), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        isTrue,
        reason: '快捷键应该把光标放进搜索框',
      );

      await press(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.digit4,
      );

      expect(find.byType(FavoritesPage), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
