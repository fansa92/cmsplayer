import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/app_state.dart';
import 'package:cms_player/state/favorites_store.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/ui/pages/detail_page.dart';
import 'package:cms_player/ui/pages/keyword_page.dart';

import 'helpers/fakes.dart';

/// 详情页的两个"入口"能力：
///
///  * 相似推荐 —— 同分类再拉一页，失败静默、不显示空壳；
///  * 演员 / 导演 / 分类可点 —— 点开落到 [KeywordPage]，不走全局 SearchStore。
void main() {
  useIsolatedStores();

  final VodSource source = sourceOf('测试站');

  late SettingsStore settings;
  late AppState app;
  late FakeHttpClient client;

  setUp(() async {
    settings = SettingsStore();
    await settings.init();
    app = AppState(settings);
  });

  /// 只有 `t=5`（动作片）有内容，用来验证推荐位确实按分类查。
  void serveSimilar() {
    client = FakeHttpClient((RecordedRequest request) {
      final String typeId = request.url.queryParameters['t'] ?? '';
      if (typeId == '5') {
        return fakeJson(
          vodPageJson(
            list: <Map<String, Object>>[
              vodJson(id: 1, name: '本片'),
              vodJson(id: 2, name: '邻居甲'),
              vodJson(id: 3, name: '邻居乙'),
            ],
            total: 3,
          ),
        );
      }
      return fakeJson(vodPageJson(list: <Map<String, Object>>[]));
    });
    useFakeApi(client);
  }

  VodItem itemWithType({String actor = '', String director = ''}) => VodItem(
        id: 1,
        name: '本片',
        typeId: 5,
        typeName: '动作片',
        actor: actor,
        director: director,
        playFrom: 'm3u8',
        playUrl: r'第1集$https://a.com/1.m3u8',
      );

  Widget host(VodItem item) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<FavoritesStore>.value(value: FavoritesStore()),
        ChangeNotifierProvider<HistoryStore>.value(value: HistoryStore()),
        ChangeNotifierProvider<AppState>.value(value: app),
      ],
      child: MaterialApp(
        home: DetailPage(item: item, source: source),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    // 推荐位是异步拉回来的，多推几帧等它落地。
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('按分类拉相似推荐，并排除自己', (WidgetTester tester) async {
    serveSimilar();
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(itemWithType()));
    await settle(tester);

    expect(find.text('相似推荐'), findsOneWidget);
    expect(find.text('邻居甲'), findsOneWidget);
    expect(find.text('邻居乙'), findsOneWidget);
    // 自己只在标题里出现一次，没有混进推荐位。
    expect(find.text('本片'), findsOneWidget);
    expect(client.requests.single.url.queryParameters['t'], '5');
  });

  testWidgets('没有 type_id 时不发推荐请求', (WidgetTester tester) async {
    serveSimilar();
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final VodItem noType = VodItem(
      id: 9,
      name: '无分类',
      playFrom: 'm3u8',
      playUrl: r'第1集$https://a.com/9.m3u8',
    );
    await tester.pumpWidget(host(noType));
    await settle(tester);

    expect(find.text('相似推荐'), findsNothing);
    expect(client.requests, isEmpty, reason: '连详情都不用补，不该有任何请求');
  });

  testWidgets('推荐请求失败时静默隐藏', (WidgetTester tester) async {
    client = FakeHttpClient(
      (RecordedRequest request) => fakeResponse(500, 'boom'),
    );
    useFakeApi(client);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(itemWithType()));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('相似推荐'), findsNothing);
    expect(find.text('本片'), findsOneWidget, reason: '详情页本身照常可用');
  });

  testWidgets('点演员名进入关键词结果页', (WidgetTester tester) async {
    serveSimilar();
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(itemWithType(actor: '张三,李四')));
    await settle(tester);

    expect(find.text('张三'), findsOneWidget);
    expect(find.text('李四'), findsOneWidget);

    await tester.tap(find.text('张三'));
    await settle(tester);

    expect(find.byType(KeywordPage), findsOneWidget);
    expect(
      client.requests.any((RecordedRequest r) => r.url.queryParameters['wd'] == '张三'),
      isTrue,
      reason: '关键词页应该用 wd=张三 查询',
    );
  });

  testWidgets('导演同样可点，带分隔符的名字会被拆开', (WidgetTester tester) async {
    serveSimilar();
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(itemWithType(actor: '甲/乙、丙', director: '丁')),
    );
    await settle(tester);

    expect(find.text('甲'), findsOneWidget);
    expect(find.text('乙'), findsOneWidget);
    expect(find.text('丙'), findsOneWidget);
    expect(find.text('丁'), findsOneWidget);
  });

  testWidgets('分类标签可点，进入分类浏览页', (WidgetTester tester) async {
    serveSimilar();
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(itemWithType()));
    await settle(tester);

    await tester.tap(find.text('动作片'));
    await settle(tester);

    expect(find.byType(KeywordPage), findsOneWidget);
    expect(
      client.requests.any((RecordedRequest r) => r.url.queryParameters['t'] == '5'),
      isTrue,
    );
  });
}
