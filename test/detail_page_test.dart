import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/play_record.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/app_state.dart';
import 'package:cms_player/state/favorites_store.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/ui/pages/detail_page.dart';

import 'helpers/fakes.dart';

/// 详情页的选集区改成了 [SliverGrid] 懒构建，这里钉住三件事：
/// 大剧只建可见的按钮、滚动能到最后一集、宽屏两栏不塌。
void main() {
  useIsolatedStores();

  final VodSource source = sourceOf('测试站');

  late SettingsStore settings;
  late AppState app;

  setUp(() async {
    settings = SettingsStore();
    await settings.init();
    app = AppState(settings);
  });

  /// 生成 `lines` 条线路、每条 `episodes` 集的条目。
  VodItem makeItem({int episodes = 500, int lines = 1}) {
    final List<String> froms = <String>[];
    final List<String> urls = <String>[];
    for (int l = 0; l < lines; l++) {
      froms.add('m3u8_$l');
      urls.add(
        List<String>.generate(
          episodes,
          (int i) => 'L$l第${i + 1}集\$https://a.com/$l/$i.m3u8',
        ).join('#'),
      );
    }
    return VodItem(
      id: 1,
      name: '长剧',
      playFrom: froms.join(r'$$$'),
      playUrl: urls.join(r'$$$'),
    );
  }

  Widget host(VodItem item, {HistoryStore? history}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<FavoritesStore>.value(value: FavoritesStore()),
        ChangeNotifierProvider<HistoryStore>.value(
          value: history ?? HistoryStore(),
        ),
        ChangeNotifierProvider<AppState>.value(value: app),
      ],
      child: MaterialApp(
        home: DetailPage(item: item, source: source),
      ),
    );
  }

  /// 一条挂在「长剧」上的播放记录（vodId 与 [makeItem] 一致）。
  PlayRecord recordOf({
    int line = 0,
    int episode = 0,
    bool finished = false,
  }) {
    return PlayRecord(
      key: '${source.id}|1',
      sourceId: source.id,
      sourceName: source.name,
      vodId: '1',
      vodName: '长剧',
      lineIndex: line,
      episodeIndex: episode,
      lineName: 'm3u8_$line',
      episodeName: 'L$line第${episode + 1}集',
      positionMs: 60000,
      durationMs: 1800000,
      finished: finished,
      updatedAt: DateTime.now(),
    );
  }

  double scrollOffset(WidgetTester tester) => tester
      .widget<CustomScrollView>(find.byType(CustomScrollView))
      .controller!
      .offset;

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Finder episodeButtons() => find.descendant(
        of: find.byType(SliverGrid),
        matching: find.byType(FilledButton),
      );

  testWidgets('500 集只构建屏幕附近的按钮', (WidgetTester tester) async {
    setSize(tester, const Size(360, 800));
    await tester.pumpWidget(host(makeItem()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(episodeButtons(), findsWidgets);
    expect(
      tester.widgetList(episodeButtons()).length,
      lessThan(60),
      reason: '选集必须是懒构建，不能一次建出 500 个按钮',
    );
    // 第一集在视口里，最后一集还没建出来。
    expect(find.text('L0第1集'), findsOneWidget);
    expect(find.text('L0第500集'), findsNothing);
  });

  testWidgets('滚动到底能到最后一集', (WidgetTester tester) async {
    setSize(tester, const Size(360, 800));
    await tester.pumpWidget(host(makeItem(episodes: 200)));
    await tester.pumpAndSettle();

    final Finder scroll = find.byType(CustomScrollView);
    for (int i = 0; i < 60 && find.text('L0第200集').evaluate().isEmpty; i++) {
      await tester.drag(scroll, const Offset(0, -500));
      await tester.pump();
    }

    expect(find.text('L0第200集'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换线路后选集换成新线路的内容', (WidgetTester tester) async {
    setSize(tester, const Size(360, 900));
    await tester.pumpWidget(host(makeItem(episodes: 3, lines: 2)));
    await tester.pumpAndSettle();

    expect(find.text('L0第1集'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'm3u8_1 (3)'));
    await tester.pumpAndSettle();

    expect(find.text('L1第1集'), findsOneWidget);
    expect(find.text('L0第1集'), findsNothing);
  });

  testWidgets('反序设置让第一格变成最后一集', (WidgetTester tester) async {
    setSize(tester, const Size(360, 900));
    await settings.setEpisodeOrderReverse(true);
    await tester.pumpWidget(host(makeItem(episodes: 3)));
    await tester.pumpAndSettle();

    final Finder first = episodeButtons().first;
    expect(
      find.descendant(of: first, matching: find.text('L0第3集')),
      findsOneWidget,
    );
  });

  testWidgets('宽屏排成左右两栏', (WidgetTester tester) async {
    setSize(tester, const Size(1280, 900));
    await tester.pumpWidget(host(makeItem(episodes: 12)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 海报与「收藏」在左栏，标题在右栏。
    final double titleX = tester.getTopLeft(find.text('长剧')).dx;
    final double favoriteX = tester.getTopLeft(find.text('收藏')).dx;
    expect(favoriteX, lessThan(titleX));
  });

  testWidgets('窄屏 360 不溢出', (WidgetTester tester) async {
    setSize(tester, const Size(360, 780));
    await tester.pumpWidget(host(makeItem(episodes: 30, lines: 3)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  // ------------------------------------------------------------ 续播定位

  testWidgets('有播放记录时打开就滚到那一集', (WidgetTester tester) async {
    setSize(tester, const Size(360, 800));
    final HistoryStore history = HistoryStore();
    // 记录要落盘，真实磁盘 I/O 必须走 runAsync，否则会挂住。
    await tester.runAsync(() => history.upsert(recordOf(episode: 200)));

    await tester.pumpWidget(host(makeItem(), history: history));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(scrollOffset(tester), greaterThan(0), reason: '应该已经滚下去了');

    final Finder target = find.text('L0第201集');
    expect(target, findsOneWidget, reason: '续播的那一集应该被滚进懒加载范围');
    // 停在固定工具栏下方，而不是被压住或贴到屏幕顶上。
    expect(tester.getRect(target).top, inInclusiveRange(56, 200));
    expect(find.text('L0第1集'), findsNothing, reason: '页头已经被滚走');
  });

  testWidgets('记录在另一条线路时自动切到那条线路', (WidgetTester tester) async {
    setSize(tester, const Size(360, 900));
    final HistoryStore history = HistoryStore();
    await tester.runAsync(
      () => history.upsert(recordOf(line: 1, episode: 5)),
    );

    await tester.pumpWidget(
      host(makeItem(episodes: 10, lines: 2), history: history),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final ChoiceChip chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'm3u8_1 (10)'),
    );
    expect(chip.selected, isTrue, reason: '续播集在第二条线路上');
    expect(find.text('L1第6集'), findsOneWidget);
    expect(find.text('L0第6集'), findsNothing);
  });

  testWidgets('续播集在第一行时不滚动（别把简介顶走）', (WidgetTester tester) async {
    setSize(tester, const Size(360, 800));
    final HistoryStore history = HistoryStore();
    await tester.runAsync(() => history.upsert(recordOf(episode: 2)));

    await tester.pumpWidget(host(makeItem(), history: history));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(scrollOffset(tester), 0);
    expect(find.text('L0第3集'), findsOneWidget);
    expect(find.text('长剧'), findsOneWidget, reason: '标题还在原位');
  });

  testWidgets('反序时同样定位到正确的一集', (WidgetTester tester) async {
    setSize(tester, const Size(360, 800));
    await settings.setEpisodeOrderReverse(true);
    final HistoryStore history = HistoryStore();
    await tester.runAsync(() => history.upsert(recordOf(episode: 200)));

    await tester.pumpWidget(host(makeItem(), history: history));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(scrollOffset(tester), greaterThan(0));
    expect(find.text('L0第201集'), findsOneWidget);
  });

  testWidgets('用户自己滚动后不会被拉回续播位置', (WidgetTester tester) async {
    setSize(tester, const Size(360, 800));
    final HistoryStore history = HistoryStore();
    await tester.runAsync(() => history.upsert(recordOf(episode: 200)));

    await tester.pumpWidget(host(makeItem(), history: history));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final double afterAuto = scrollOffset(tester);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(scrollOffset(tester), lessThan(afterAuto));
  });

  testWidgets('宽屏两栏下也能正确定位（sliver 嵌套的偏移不能算错）', (WidgetTester tester) async {
    setSize(tester, const Size(1280, 900));
    final HistoryStore history = HistoryStore();
    await tester.runAsync(() => history.upsert(recordOf(episode: 200)));

    await tester.pumpWidget(host(makeItem(), history: history));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(scrollOffset(tester), greaterThan(0));

    final Finder target = find.text('L0第201集');
    expect(target, findsOneWidget);
    expect(tester.getRect(target).top, inInclusiveRange(56, 260));
  });
}
