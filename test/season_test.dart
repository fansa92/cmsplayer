import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/core/utils/season.dart';
import 'package:cms_player/data/models/play_line.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/app_state.dart';
import 'package:cms_player/state/favorites_store.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/ui/pages/detail_page.dart';

import 'helpers/fakes.dart';

/// 季度拆分：集名解析、分组规则、详情页的季筛选条。
void main() {
  useIsolatedStores();

  PlayEpisode ep(String name) => PlayEpisode(name: name, url: 'https://a.com/x');

  group('seasonOf 解析集名里的季度', () {
    test('常见写法都能取到序号', () {
      expect(seasonOf('第2季 第01集'), 2);
      expect(seasonOf('第二季 第01集'), 2);
      expect(seasonOf('S03E01'), 3);
      expect(seasonOf('第十二季'), 12);
      expect(seasonOf(' 第 1 季 第5集 '), 1);
    });

    test('单季剧的普通集名解析不出季度', () {
      expect(seasonOf('第01集'), isNull);
      expect(seasonOf('正片'), isNull);
      expect(seasonOf(''), isNull);
    });
  });

  group('groupBySeason 分组', () {
    test('两季以上才分组，且保持各自顺序', () {
      final List<SeasonGroup> groups = groupBySeason(<PlayEpisode>[
        ep('第1季 第1集'),
        ep('第1季 第2集'),
        ep('第2季 第1集'),
      ]);
      expect(groups.length, 2);
      expect(groups.first.season, 1);
      expect(groups.first.indices, <int>[0, 1]);
      expect(groups.last.label, '第 2 季');
      expect(groups.last.indices, <int>[2]);
    });

    test('只有一季时不分组，避免多出一排无意义的筛选条', () {
      expect(
        groupBySeason(<PlayEpisode>[ep('第1季 第1集'), ep('第1季 第2集')]),
        isEmpty,
      );
      expect(
        groupBySeason(<PlayEpisode>[ep('第01集'), ep('第02集')]),
        isEmpty,
      );
    });

    test('没写季的集数收进「其他」', () {
      final List<SeasonGroup> groups = groupBySeason(<PlayEpisode>[
        ep('第1季 第1集'),
        ep('第2季 第1集'),
        ep('花絮'),
      ]);
      expect(groups.length, 3);
      // 排序后「其他」(season 0) 排在前面；这里按序号找，不依赖顺序。
      final SeasonGroup other =
          groups.firstWhere((SeasonGroup g) => g.season == 0);
      expect(other.label, '其他');
      expect(other.indices, <int>[2]);
    });
  });

  group('详情页季度筛选', () {
    final VodSource source = sourceOf('测试站');
    late AppState app;

    setUp(() async {
      final SettingsStore settings = SettingsStore();
      await settings.init();
      app = AppState(settings);
    });

    VodItem multiSeason() => VodItem(
          id: 2,
          name: '多季剧',
          playFrom: 'm3u8',
          playUrl: List<String>.generate(
            6,
            (int i) =>
                '第${i ~/ 3 + 1}季 第${i % 3 + 1}集\$https://a.com/$i.m3u8',
          ).join('#'),
        );

    Widget host(VodItem item) => MultiProvider(
          providers: [
            ChangeNotifierProvider<FavoritesStore>.value(
              value: FavoritesStore(),
            ),
            ChangeNotifierProvider<HistoryStore>.value(value: HistoryStore()),
            ChangeNotifierProvider<AppState>.value(value: app),
          ],
          child: MaterialApp(home: DetailPage(item: item, source: source)),
        );

    testWidgets('多季剧出现季度筛选，切换后只留该季', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(host(multiSeason()));
      await tester.pumpAndSettle();

      expect(find.text('全部 6'), findsOneWidget);
      expect(find.text('第 1 季 (3)'), findsOneWidget);
      expect(find.text('第 2 季 (3)'), findsOneWidget);
      // 未筛选时两季的集都在。
      expect(find.text('第1季 第1集'), findsOneWidget);
      expect(find.text('第2季 第1集'), findsOneWidget);

      await tester.tap(find.text('第 2 季 (3)'));
      await tester.pumpAndSettle();

      expect(find.text('第1季 第1集'), findsNothing);
      expect(find.text('第2季 第1集'), findsOneWidget);
      expect(find.text('第2季 第3集'), findsOneWidget);

      await tester.tap(find.text('全部 6'));
      await tester.pumpAndSettle();
      expect(find.text('第1季 第1集'), findsOneWidget);
    });

    testWidgets('单季剧不显示季度筛选', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final VodItem single = VodItem(
        id: 3,
        name: '单季剧',
        playFrom: 'm3u8',
        playUrl: List<String>.generate(
          4,
          (int i) => '第${i + 1}集\$https://a.com/s$i.m3u8',
        ).join('#'),
      );
      await tester.pumpWidget(host(single));
      await tester.pumpAndSettle();

      expect(find.text('全部 4'), findsNothing);
      expect(find.text('第 1 季 (4)'), findsNothing);
      expect(find.text('第1集'), findsOneWidget);
    });
  });
}
