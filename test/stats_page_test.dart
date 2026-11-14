import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cms_player/data/models/play_record.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/state/watch_stats_store.dart';
import 'package:cms_player/ui/pages/stats_page.dart';

import 'helpers/fakes.dart';

/// 观看统计页：概览数字、柱状图、片单与来源分布。
void main() {
  useIsolatedStores();

  final VodSource source = sourceOf('测试站');
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);

  late HistoryStore history;

  PlayRecord recordOf({
    required int id,
    required String name,
    required bool finished,
  }) =>
      PlayRecord(
        key: '${source.id}|$id',
        sourceId: source.id,
        sourceName: source.name,
        vodId: '$id',
        vodName: name,
        lineIndex: 0,
        episodeIndex: 0,
        lineName: 'm3u8',
        episodeName: '第01集',
        positionMs: finished ? 120000 : 30000,
        durationMs: 120000,
        finished: finished,
        updatedAt: DateTime(2026, 1, 1),
      );

  setUp(() async {
    history = HistoryStore();
    await history.load();
    await history.upsert(recordOf(id: 1, name: '庆余年', finished: false));
    await history.upsert(recordOf(id: 2, name: '繁花', finished: true));
  });

  Future<void> seed() async {
    await WatchStatsStore.instance.add(
      title: '庆余年',
      sourceId: source.id,
      sourceName: source.name,
      watched: const Duration(minutes: 60),
      at: today.add(const Duration(hours: 9)),
    );
    await WatchStatsStore.instance.add(
      title: '繁花',
      sourceId: source.id,
      sourceName: source.name,
      watched: const Duration(minutes: 30),
      at: today.subtract(const Duration(days: 1)).add(
            const Duration(hours: 21),
          ),
    );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    // 高一点的画布，让「追剧概况」也进入可视区（ListView 只建可见项）。
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HistoryStore>.value(value: history),
        ],
        child: const MaterialApp(home: StatsPage()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('概览、柱状图、片单与追剧概况都渲染出来', (WidgetTester tester) async {
    await tester.runAsync(seed);
    await pumpPage(tester);

    // 本周 1 小时 30 分（今天 60 + 昨天 30）。
    expect(find.text('本周观看'), findsOneWidget);
    expect(find.text('1 小时 30 分'), findsWidgets);
    expect(find.textContaining('今日 1 小时'), findsOneWidget);
    expect(find.text('近 14 天'), findsOneWidget);
    expect(find.textContaining('单日最多 1 小时'), findsOneWidget);

    expect(find.text('常看片单'), findsOneWidget);
    expect(find.text('庆余年'), findsOneWidget);
    expect(find.text('繁花'), findsOneWidget);

    expect(find.text('按来源'), findsOneWidget);
    // 常看片单的副标题与来源分布里都会出现源名。
    expect(find.text('测试站'), findsWidgets);

    expect(find.text('追剧概况'), findsOneWidget);
    expect(find.text('1 部'), findsNWidgets(2)); // 在追 1 部 / 已看完 1 部
  });

  testWidgets('没有数据时显示空态', (WidgetTester tester) async {
    await pumpPage(tester);

    expect(find.text('还没有观看时长'), findsOneWidget);
    expect(find.text('本周观看'), findsNothing);
  });
}
