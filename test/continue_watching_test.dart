import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/play_record.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/state/source_store.dart';
import 'package:cms_player/ui/pages/home_page.dart';
import 'package:cms_player/ui/shell/app_shell.dart';

void main() {
  testWidgets('有未看完的记录时渲染横条', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(tester, <PlayRecord>[
        _record('庆余年', progress: 0.4, finished: false),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('继续观看'), findsOneWidget);
    expect(find.text('庆余年'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已看完的记录不占位置', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(tester, <PlayRecord>[
        _record('看完了的', progress: 1, finished: true),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('继续观看'), findsNothing);
    expect(find.text('看完了的'), findsNothing);
  });

  testWidgets('没有任何记录时不渲染横条', (WidgetTester tester) async {
    await tester.pumpWidget(_host(tester, const <PlayRecord>[]));
    await tester.pumpAndSettle();

    expect(find.text('继续观看'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('「全部」按钮切到历史页', (WidgetTester tester) async {
    int selected = -1;
    await tester.pumpWidget(
      _host(
        tester,
        <PlayRecord>[_record('庆余年', progress: 0.4, finished: false)],
        onSelect: (int index) => selected = index,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    expect(selected, ShellTabs.historyIndex);
  });

  testWidgets('窄屏与宽屏都不溢出', (WidgetTester tester) async {
    for (final Size size in <Size>[
      const Size(360, 640),
      const Size(1280, 900),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(tester, <PlayRecord>[
          _record('庆余年第二季', progress: 0.4, finished: false),
          _record('三体', progress: 0.8, finished: false),
        ]),
      );
      await tester.pumpAndSettle();

      // overflow 会在 debug 模式下抛异常，这里显式断言没有。
      expect(tester.takeException(), isNull);
      expect(find.text('继续观看'), findsOneWidget);
    }
  });
}

/// 把横条放进一个带壳页签的最小宿主里。
Widget _host(
  WidgetTester tester,
  List<PlayRecord> records, {
  void Function(int index)? onSelect,
}) {
  final SettingsStore settings = SettingsStore();
  final SourceStore sources = SourceStore(settings);
  final HistoryStore history = HistoryStore();

  // 直接塞进 store 的内存列表，走的是它自己的公开 API。
  for (final PlayRecord record in records) {
    history.upsert(record);
  }

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<HistoryStore>.value(value: history),
      ChangeNotifierProvider<SourceStore>.value(value: sources),
    ],
    child: MaterialApp(
      home: ShellTabs(
        index: 0,
        select: onSelect ?? (int _) {},
        child: const Scaffold(
          body: SingleChildScrollView(
            child: ContinueWatchingStrip(),
          ),
        ),
      ),
    ),
  );
}

PlayRecord _record(
  String name, {
  required double progress,
  required bool finished,
}) {
  return PlayRecord(
    key: 'source|${name.hashCode}',
    sourceId: 'source',
    sourceName: '测试站',
    vodId: '${name.hashCode}',
    vodName: name,
    vodPic: '',
    lineIndex: 0,
    episodeIndex: 0,
    lineName: '线路1',
    episodeName: '第01集',
    positionMs: (progress * 1000).round(),
    durationMs: 1000,
    finished: finished,
    updatedAt: DateTime.now(),
  );
}
