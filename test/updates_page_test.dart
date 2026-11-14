import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/favorites_store.dart';
import 'package:cms_player/state/source_store.dart';
import 'package:cms_player/ui/pages/updates_page.dart';

import 'helpers/fakes.dart';

/// 追剧更新中心：只读 FavoritesStore 已经算好的更新结果，负责展示与已读。
void main() {
  useIsolatedStores();

  final VodSource source = sourceOf('主站');

  late FavoritesStore favorites;
  late SourceStore sources;

  String playUrl(int id, int episodes) => List<String>.generate(
        episodes,
        (int i) => '第${i + 1}集\$https://a.com/$id/$i.m3u8',
      ).join('#');

  setUp(() async {
    final SettingsStore settings = SettingsStore();
    await settings.init();
    sources = SourceStore(settings);
    favorites = FavoritesStore();
    await favorites.load();
  });

  /// 收藏一部 10 集的剧，再让接口说它已经 13 集。
  Future<void> seedUpdated() async {
    await favorites.toggle(
      source: source,
      item: VodItem(
        id: 1,
        name: '庆余年',
        playFrom: 'm3u8',
        playUrl: playUrl(1, 10),
      ),
    );
    final FakeHttpClient client = FakeHttpClient((RecordedRequest request) {
      final List<Map<String, Object>> list = <Map<String, Object>>[
        <String, Object>{
          'vod_id': 1,
          'vod_name': '庆余年',
          'vod_play_from': 'm3u8',
          'vod_play_url': playUrl(1, 13),
        },
      ];
      return fakeJson(vodPageJson(list: list, total: 1));
    });
    useFakeApi(client);
    await favorites.checkUpdates(sources: <VodSource>[source]);
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FavoritesStore>.value(value: favorites),
          ChangeNotifierProvider<SourceStore>.value(value: sources),
        ],
        child: const MaterialApp(home: UpdatesPage()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('列出集数变化与所属资源站', (WidgetTester tester) async {
    await tester.runAsync(seedUpdated);
    await pumpPage(tester);

    expect(find.text('1 部有更新'), findsOneWidget);
    expect(find.text('庆余年'), findsOneWidget);
    expect(find.text('10 → 13 集'), findsOneWidget);
    // 页面里的源名来自 SourceStore；这个用例没往 store 里塞源，只剩新增集数。
    expect(find.text('新增 3 集'), findsOneWidget);
  });

  testWidgets('没有更新时显示空态', (WidgetTester tester) async {
    await pumpPage(tester);

    expect(find.text('暂时没有新集'), findsOneWidget);
  });

  testWidgets('全部已读把更新计数清零', (WidgetTester tester) async {
    await tester.runAsync(seedUpdated);
    await pumpPage(tester);
    expect(favorites.updatedCount, 1);

    // 直接触发按钮回调，并在真实异步域里等落盘完成 —— tap 会落在假时钟里，
    // markSeen 的 await _save() 永远等不到真实 IO 回来。
    final TextButton button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '全部已读'),
    );
    await tester.runAsync(() async {
      button.onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
    await tester.pump();

    expect(favorites.updatedCount, 0);
    expect(find.text('暂时没有新集'), findsOneWidget);
  });
}
