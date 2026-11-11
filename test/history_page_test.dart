import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/play_record.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/state/source_store.dart';
import 'package:cms_player/ui/pages/history_page.dart';
import 'package:cms_player/ui/widgets/vod_card.dart';

import 'helpers/fakes.dart';

/// 观看记录的多选删除。
///
/// 钉住：进入多选的两种入口、勾选增删、全选互切、确认弹窗、删除后的状态收敛，
/// 以及多选态下关掉滑动删除（两个删除入口同时存在容易误触）。
///
/// 两个测试约束：
///  * 页面上有无限动画（加载圈），不能用 `pumpAndSettle`；
///  * `JsonStore` 是真实文件读写，在 `testWidgets` 的 fake async 里不会完成，
///    所以数据一律在 `setUp` 里预置，动作触发的落盘用 [pumpUntilFound] 推进。
void main() {
  useIsolatedStores();

  late SettingsStore settings;
  late SourceStore sources;
  late HistoryStore history;
  final VodSource source = sourceOf('测试站');

  PlayRecord recordOf(int id) => PlayRecord(
        key: '${source.id}|$id',
        sourceId: source.id,
        sourceName: source.name,
        vodId: '$id',
        vodName: '影片$id',
        vodPic: '',
        lineIndex: 0,
        episodeIndex: 0,
        lineName: 'm3u8',
        episodeName: '第01集',
        positionMs: 30000,
        durationMs: 120000,
        updatedAt: DateTime(2026, 1, 1).add(Duration(minutes: id)),
      );

  setUp(() async {
    settings = SettingsStore();
    await settings.init();
    sources = SourceStore(settings);
    history = HistoryStore();
    await history.load();
    // 三条记录，id 越大越新（列表按 updatedAt 倒序：影片3 / 影片2 / 影片1）。
    for (int i = 1; i <= 3; i++) {
      await history.upsert(recordOf(i));
    }
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HistoryStore>.value(value: history),
          ChangeNotifierProvider<SourceStore>.value(value: sources),
        ],
        child: const MaterialApp(home: Scaffold(body: HistoryPage())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// 推进动画（弹窗、SnackBar）。
  Future<void> frames(WidgetTester tester) async {
    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// 轮询推进，直到 [finder] 出现。
  ///
  /// 删除动作内部的 `removeMany` 是一条真实文件 I/O 链，在 fake async 里只能
  /// 靠 `runAsync` 一次次给真实事件循环机会；而链尾的 `notifyListeners` 若晚于
  /// 最后一次 `pump`，界面就不会重建。与其猜需要几轮，不如等到目标出现为止。
  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int rounds = 60,
  }) async {
    for (int i = 0; i < rounds; i++) {
      if (finder.evaluate().isNotEmpty) {
        await tester.pump(const Duration(milliseconds: 100));
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder deleteInToolbar() => find.widgetWithText(FilledButton, '删除');

  Finder deleteInDialog() => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '删除'),
      );

  /// 进入多选并选中前 [count] 张卡片（列表顺序 = 新→旧）。
  Future<void> selectFirst(WidgetTester tester, int count) async {
    await tester.tap(find.text('多选'));
    await frames(tester);
    for (int i = 0; i < count; i++) {
      await tester.tap(find.byType(HistoryCard).at(i));
      await frames(tester);
    }
  }

  /// 点工具栏删除 → 确认 → 等到界面进入 [expectVisible] 描述的状态。
  Future<void> confirmDelete(
    WidgetTester tester,
    Finder expectVisible,
  ) async {
    await tester.tap(deleteInToolbar());
    await frames(tester);
    await tester.tap(deleteInDialog());
    await pumpUntilFound(tester, expectVisible);
  }

  testWidgets('默认不在多选态，工具条只显示计数与两个入口', (WidgetTester tester) async {
    await mount(tester);

    expect(find.text('共 3 条记录'), findsOneWidget);
    expect(find.text('多选'), findsOneWidget);
    expect(find.text('清空'), findsOneWidget);
    expect(find.text('全选'), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('点「多选」进入选择态，未选中时删除按钮禁用', (WidgetTester tester) async {
    await mount(tester);

    await tester.tap(find.text('多选'));
    await frames(tester);

    expect(find.text('请选择记录'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('共 3 条记录'), findsNothing);
    expect(tester.widget<FilledButton>(deleteInToolbar()).onPressed, isNull);
    // 三张卡片都是空心圆点，没有任何勾。
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('长按卡片直接进入多选并选中该条', (WidgetTester tester) async {
    await mount(tester);

    await tester.longPress(find.byType(HistoryCard).first);
    await frames(tester);

    expect(find.text('已选 1 条'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(tester.widget<FilledButton>(deleteInToolbar()).onPressed, isNotNull);
  });

  testWidgets('多选态下点击卡片切换选中，不会触发续播', (WidgetTester tester) async {
    await mount(tester);
    await tester.longPress(find.byType(HistoryCard).first);
    await frames(tester);

    await tester.tap(find.byType(HistoryCard).at(1));
    await frames(tester);
    expect(find.text('已选 2 条'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(2));

    await tester.tap(find.byType(HistoryCard).at(1));
    await frames(tester);
    expect(find.text('已选 1 条'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    // 没有导航发生，仍停在历史页。
    expect(find.byType(HistoryPage), findsOneWidget);
  });

  testWidgets('全选与取消全选互切', (WidgetTester tester) async {
    await mount(tester);
    await tester.tap(find.text('多选'));
    await frames(tester);

    await tester.tap(find.text('全选'));
    await frames(tester);
    expect(find.text('已选 3 条'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(3));
    expect(find.text('取消全选'), findsOneWidget);

    await tester.tap(find.text('取消全选'));
    await frames(tester);
    expect(find.text('请选择记录'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('删除选中项：确认后移除记录、提示条数并退出多选', (WidgetTester tester) async {
    await mount(tester);
    await selectFirst(tester, 2);
    expect(find.text('已选 2 条'), findsOneWidget);

    await tester.tap(deleteInToolbar());
    await frames(tester);
    expect(find.text('删除 2 条观看记录？'), findsOneWidget);

    await tester.tap(deleteInDialog());
    await pumpUntilFound(tester, find.text('共 1 条记录'));

    expect(history.records.length, 1);
    // 列表是新→旧：选中的前两张是影片3、影片2，剩下影片1。
    expect(history.records.single.vodName, '影片1');
    expect(find.byType(HistoryCard), findsOneWidget);
    expect(find.text('已删除 2 条记录'), findsOneWidget);
    // 已退出多选态，回到普通工具条。
    expect(find.text('共 1 条记录'), findsOneWidget);
    expect(find.text('全选'), findsNothing);
  });

  testWidgets('弹窗里取消不会删除，仍留在多选态', (WidgetTester tester) async {
    await mount(tester);
    await selectFirst(tester, 1);

    await tester.tap(deleteInToolbar());
    await frames(tester);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await frames(tester);

    expect(history.records.length, 3);
    expect(find.text('已选 1 条'), findsOneWidget);
    expect(find.byType(HistoryCard), findsNWidgets(3));
  });

  testWidgets('关闭按钮退出多选并清空选中', (WidgetTester tester) async {
    await mount(tester);
    await tester.tap(find.text('多选'));
    await frames(tester);
    await tester.tap(find.text('全选'));
    await frames(tester);
    expect(find.text('已选 3 条'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await frames(tester);

    expect(find.text('共 3 条记录'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);

    // 重新进入时没有残留选择。
    await tester.tap(find.text('多选'));
    await frames(tester);
    expect(find.text('请选择记录'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('多选态下禁用滑动删除', (WidgetTester tester) async {
    await mount(tester);
    await tester.longPress(find.byType(HistoryCard).first);
    await frames(tester);

    await tester.drag(find.byType(HistoryCard).at(0), const Offset(-400, 0));
    await frames(tester);

    expect(history.records.length, 3);
    expect(find.byType(HistoryCard), findsNWidgets(3));
  });

  testWidgets('记录被外部删除后，选中数跟着收敛', (WidgetTester tester) async {
    await mount(tester);
    await tester.tap(find.text('多选'));
    await frames(tester);
    await tester.tap(find.text('全选'));
    await frames(tester);
    expect(find.text('已选 3 条'), findsOneWidget);

    // 模拟同步把「影片1」删掉。
    await tester.runAsync(() => history.remove(recordOf(1).key));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('已选 2 条'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(2));
    expect(find.byType(HistoryCard), findsNWidgets(2));
  });

  testWidgets('全部删完后回到空状态', (WidgetTester tester) async {
    await mount(tester);
    await tester.tap(find.text('多选'));
    await frames(tester);
    await tester.tap(find.text('全选'));
    await frames(tester);
    await confirmDelete(tester, find.text('还没有观看记录'));

    expect(history.records, isEmpty);
    expect(find.text('还没有观看记录'), findsOneWidget);
    expect(find.byType(HistoryCard), findsNothing);
  });

  testWidgets('只剩一条时多选入口禁用', (WidgetTester tester) async {
    await mount(tester);
    // 删到只剩一条，再回到普通工具条看多选按钮的状态。
    await selectFirst(tester, 2);
    await confirmDelete(tester, find.text('共 1 条记录'));

    expect(history.records.length, 1);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '多选'))
          .onPressed,
      isNull,
    );
  });
}
