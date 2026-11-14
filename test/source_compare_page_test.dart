import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/source_store.dart';
import 'package:cms_player/ui/pages/source_compare_page.dart';

import 'helpers/fakes.dart';

/// 全源对比页：把各源的集数、线路与状态摆出来。
void main() {
  useIsolatedStores();

  final VodSource a = sourceOf('A 站', host: 'a.com');
  final VodSource b = sourceOf('B 站', host: 'b.com');

  String episodes(int id, int count) => List<String>.generate(
        count,
        (int i) => '第${i + 1}集\$https://a.com/$id/$i.m3u8',
      ).join('#');

  late SourceStore sources;

  setUp(() async {
    final SettingsStore settings = SettingsStore();
    await settings.init();
    sources = SourceStore(settings);
    await sources.add(a);
    await sources.add(b);

    useFakeApi(FakeHttpClient((RecordedRequest request) {
      final bool isA = request.url.host == 'a.com';
      final int count = isA ? 10 : 13;
      return fakeJson(vodPageJson(
        list: <Map<String, Object>>[
          vodJson(
            id: isA ? 1 : 2,
            name: '庆余年',
            year: '2019',
            playFrom: 'm3u8',
            playUrl: episodes(isA ? 1 : 2, count),
          ),
        ],
        total: 1,
      ));
    }));
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SourceStore>.value(value: sources),
        ],
        child: const MaterialApp(
          home: SourceComparePage(title: '庆余年', year: '2019'),
        ),
      ),
    );
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('列出各源集数并标出集数最多的源', (WidgetTester tester) async {
    await pumpPage(tester);

    expect(find.text('全源对比'), findsOneWidget);
    expect(find.text('庆余年'), findsOneWidget);
    expect(find.text('13 集'), findsOneWidget);
    expect(find.text('10 集'), findsOneWidget);
    expect(find.text('集数最多'), findsOneWidget);
    // 13 集的那一行排在前面。
    expect(find.text('B 站'), findsOneWidget);
    expect(find.text('A 站'), findsOneWidget);
    expect(find.text('打开「B 站」· 13 集'), findsOneWidget);
  });

  testWidgets('少于两个源时提示先添加资源站', (WidgetTester tester) async {
    // 删除会记墓碑并写盘；fake async 里真实 IO 不会完成，得放进真实异步域。
    await tester.runAsync(() => sources.remove(b.id));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SourceStore>.value(value: sources),
        ],
        child: const MaterialApp(
          home: SourceComparePage(title: '庆余年'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('至少需要两个启用的资源站'), findsOneWidget);
  });
}
