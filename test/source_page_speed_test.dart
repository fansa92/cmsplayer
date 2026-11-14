import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/source_health.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/source_health_store.dart';
import 'package:cms_player/state/source_store.dart';
import 'package:cms_player/ui/pages/source_page.dart';

import 'helpers/fakes.dart';

/// 资源站页的测速展示：延迟标签、上次测速时间、菜单入口。
void main() {
  useIsolatedStores();

  final VodSource slow = sourceOf('慢站', host: 'slow.com');
  final VodSource fast = sourceOf('快站', host: 'fast.com');

  late SourceStore sources;

  setUp(() async {
    final SettingsStore settings = SettingsStore();
    await settings.init();
    sources = SourceStore(settings);
    await sources.load();
    await sources.add(slow);
    await sources.add(fast);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SourceStore>.value(value: sources),
        ],
        child: const MaterialApp(home: SourcePage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('显示上次测速的延迟与时间', (WidgetTester tester) async {
    final DateTime at = DateTime.now().subtract(const Duration(minutes: 5));
    SourceHealthStore.instance.seedForTest(<SourceHealth>[
      SourceHealth(sourceId: fast.id, latencyMs: 120, checkedAt: at),
      SourceHealth(sourceId: slow.id, latencyMs: 1500, checkedAt: at),
    ]);

    await pumpPage(tester);

    expect(find.text('120 ms'), findsOneWidget);
    expect(find.text('1500 ms'), findsOneWidget);
    expect(find.textContaining('上次测速'), findsOneWidget);
  });

  testWidgets('更多菜单里有测速与按速度排序', (WidgetTester tester) async {
    await pumpPage(tester);

    await tester.tap(find.byTooltip('更多'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('测速全部源'), findsOneWidget);
    expect(find.text('按测速结果排序'), findsOneWidget);
  });
}
