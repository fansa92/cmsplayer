import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/state/rank_store.dart';
import 'package:cms_player/state/source_store.dart';
import 'package:cms_player/ui/pages/rank_page.dart';

import 'helpers/fakes.dart';

/// 榜单页：排序切换、空态与正常渲染。
void main() {
  useIsolatedStores();

  late RankStore rank;
  late SourceStore sources;

  /// 按 `by` 参数返回不同片名，方便断言「点哪个就按哪个排」。
  FakeHttpClient rankClient({bool empty = false}) =>
      FakeHttpClient((RecordedRequest r) {
        final String by = r.url.queryParameters['by'] ?? '';
        return fakeJson(vodPageJson(
          total: empty ? 0 : 2,
          list: empty
              ? <Map<String, Object>>[]
              : <Map<String, Object>>[
                  vodJson(
                    id: 1,
                    name: '$by片一',
                    playFrom: 'm3u8',
                    playUrl: r'第1集$https://a.com/1.m3u8',
                  ),
                  vodJson(
                    id: 2,
                    name: '$by片二',
                    playFrom: 'm3u8',
                    playUrl: r'第1集$https://a.com/2.m3u8',
                  ),
                ],
        ));
      });

  /// 手动推几帧。
  ///
  /// 不能用 `pumpAndSettle`：加载态里的骨架屏挂着 `repeat()` 的动画控制器，
  /// 永远等不到「没有待处理帧」的时刻（见 poster_skeleton.dart 的注释）。
  Future<void> pumpFrames(WidgetTester tester, {int frames = 8}) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> mount(WidgetTester tester, FakeHttpClient client) async {
    useFakeApi(client);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // SourceStore.add 会真的写盘。widget 测试的坐标系里挂着 fake async，
    // 真实文件 I/O 的 Future 永远不会完成，所以这一段必须放进 runAsync。
    final SettingsStore settings = SettingsStore();
    await tester.runAsync(() async {
      await settings.init();
      sources = SourceStore(settings);
      await sources.add(sourceOf('测试站'));
    });
    rank = RankStore();
    final HistoryStore history = HistoryStore();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SourceStore>.value(value: sources),
          ChangeNotifierProvider<HistoryStore>.value(value: history),
          ChangeNotifierProvider<RankStore>.value(value: rank),
        ],
        child: const MaterialApp(home: RankPage()),
      ),
    );
    await pumpFrames(tester);
  }

  tearDown(() {
    rank.dispose();
    sources.dispose();
  });

  testWidgets('打开就按最多播放拉一页并渲染网格', (WidgetTester tester) async {
    final FakeHttpClient client = rankClient();
    await mount(tester, client);

    expect(find.text('榜单'), findsOneWidget);
    expect(find.text('最多播放'), findsOneWidget);
    expect(find.text('最高评分'), findsOneWidget);
    expect(find.text('最新更新'), findsOneWidget);
    expect(find.text('hits片一'), findsOneWidget);
    expect(find.textContaining('测试站 · 最多播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点另一个排序会按新参数重拉', (WidgetTester tester) async {
    final FakeHttpClient client = rankClient();
    await mount(tester, client);

    await tester.tap(find.text('最高评分'));
    await pumpFrames(tester);

    expect(client.last.url.queryParameters['by'], 'score');
    expect(find.text('score片一'), findsOneWidget);
    expect(find.text('hits片一'), findsNothing);
  });

  testWidgets('没有内容时给出空态与重新加载', (WidgetTester tester) async {
    final FakeHttpClient client = rankClient(empty: true);
    await mount(tester, client);

    expect(find.text('这个榜单暂时是空的'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
