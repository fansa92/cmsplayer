import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/app_state.dart';
import 'package:cms_player/state/browse_store.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/state/search_store.dart';
import 'package:cms_player/state/source_store.dart';
import 'package:cms_player/ui/pages/category_page.dart';
import 'package:cms_player/ui/pages/search_page.dart';

import 'helpers/fakes.dart';

/// 字母索引 / 排序方向 / 搜索联想词的 store 与页面行为。
void main() {
  useIsolatedStores();

  final VodSource s1 = sourceOf('甲站', host: 'a.com');

  Map<String, Object> item(
    int id,
    String name, {
    String letter = '',
    String remarks = '',
  }) =>
      <String, Object>{
        'vod_id': id,
        'vod_name': name,
        if (letter.isNotEmpty) 'vod_letter': letter,
        if (remarks.isNotEmpty) 'vod_remarks': remarks,
        'vod_play_from': '',
        'vod_play_url': '',
      };

  FakeHttpClient letterClient(List<Map<String, Object>> list) =>
      FakeHttpClient((RecordedRequest r) => fakeJson(vodPageJson(
            list: list,
            classes: <Map<String, Object>>[
              <String, Object>{'type_id': 6, 'type_name': '动作片'},
            ],
            total: list.length,
          )));

  group('BrowseStore 字母索引与排序方向', () {
    test('availableLetters 来自原始条目，选中字母后侧栏不塌', () async {
      final FakeHttpClient client = letterClient(<Map<String, Object>>[
        item(1, 'Alpha', letter: 'A'),
        item(2, 'Beta', letter: 'B'),
        item(3, '中文片'),
      ]);
      useFakeApi(client);

      final BrowseStore store = BrowseStore();
      await store.attach(s1);
      expect(store.availableLetters, <String>['A', 'B']);

      // 假接口故意忽略 letter，模拟「服务端不认，本地补筛」的站点。
      await store.applyFilter(letter: 'b');
      expect(client.last.url.queryParameters['letter'], 'B');
      expect(store.items.map((VodItem e) => e.name).toList(),
          <String>['Beta']);
      expect(store.availableLetters, <String>['A', 'B'],
          reason: '选中 B 之后仍要能切回 A 或全部');
    });

    test('源站既不给 letter 也不响应时，本地不把整页筛空', () async {
      final FakeHttpClient client = letterClient(<Map<String, Object>>[
        item(1, '中文片一'),
        item(2, '中文片二'),
      ]);
      useFakeApi(client);

      final BrowseStore store = BrowseStore();
      await store.attach(s1);
      expect(store.availableLetters, isEmpty);

      await store.applyFilter(letter: 'A');
      expect(client.last.url.queryParameters['letter'], 'A');
      expect(store.items, hasLength(2));
    });

    test('order 走查询参数，clearFilter 复位 order 与 letter', () async {
      final FakeHttpClient client = letterClient(<Map<String, Object>>[
        item(1, 'Alpha', letter: 'A'),
        item(2, 'Beta', letter: 'B'),
      ]);
      useFakeApi(client);

      final BrowseStore store = BrowseStore();
      await store.attach(s1);
      await store.applyFilter(order: 'asc', letter: 'A');
      expect(client.last.url.queryParameters['order'], 'asc');
      expect(client.last.url.queryParameters['letter'], 'A');
      expect(store.hasFilter, isTrue);

      await store.clearFilter();
      expect(store.order, isEmpty);
      expect(store.letter, isEmpty);
      expect(store.hasFilter, isFalse);
    });

    test('attach 换源会清掉上一轮的字母与排序', () async {
      final FakeHttpClient client = letterClient(<Map<String, Object>>[
        item(1, 'Alpha', letter: 'A'),
      ]);
      useFakeApi(client);
      final BrowseStore store = BrowseStore();
      await store.attach(s1);
      await store.applyFilter(order: 'desc', letter: 'A');

      await store.attach(sourceOf('乙站', host: 'b.com'));
      expect(store.order, isEmpty);
      expect(store.letter, isEmpty);
    });
  });

  group('SearchStore 联想词', () {
    FakeHttpClient suggestClient() => FakeHttpClient((RecordedRequest r) {
          if (r.url.path.endsWith('/vod/suggest')) {
            return fakeJson(<String, Object>{
              'code': 1,
              'info': <String>['庆余年', '庆余年 第二季'],
            });
          }
          return fakeJson(vodPageJson());
        });

    test('联想词进 store，提交搜索后自动收起', () async {
      useFakeApi(suggestClient());
      final SearchStore store = SearchStore();

      await store.suggest('庆', s1);
      expect(store.suggestions, <String>['庆余年', '庆余年 第二季']);

      await store.search(
          keyword: '庆余年', active: s1, all: <VodSource>[s1]);
      expect(store.suggestions, isEmpty);
      expect(store.error, isNull);
    });

    test('同一关键词走缓存，不重复打接口', () async {
      final FakeHttpClient client = suggestClient();
      useFakeApi(client);
      final SearchStore store = SearchStore();

      await store.suggest('庆', s1);
      await store.suggest('庆', s1);
      expect(client.requests, hasLength(1));
    });

    test('接口全挂时静默降级，空关键词清空联想', () async {
      useFakeApi(FakeHttpClient((RecordedRequest r) =>
          fakeResponse(500, 'down')));
      final SearchStore store = SearchStore();

      await store.suggest('庆', s1);
      expect(store.suggestions, isEmpty);
      expect(store.error, isNull);

      await store.suggest('', s1);
      expect(store.suggestions, isEmpty);
    });
  });

  testWidgets('搜索页打字后显示联想词', (WidgetTester tester) async {
    final (SettingsStore, SourceStore) stores =
        (await tester.runAsync(() async {
      final SettingsStore settings = SettingsStore();
      await settings.init();
      final SourceStore sources = SourceStore(settings);
      await sources.load();
      await sources.add(s1);
      await sources.setActive(s1);
      return (settings, sources);
    }))!;

    final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
      if (r.url.path.endsWith('/vod/suggest')) {
        return fakeJson(<String, Object>{
          'code': 1,
          'info': <String>['庆余年', '庆余年 第二季'],
        });
      }
      return fakeJson(vodPageJson());
    });
    useFakeApi(client);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(
              value: AppState(stores.$1)),
          ChangeNotifierProvider<SourceStore>.value(value: stores.$2),
          ChangeNotifierProvider<SearchStore>.value(value: SearchStore()),
          ChangeNotifierProvider<HistoryStore>.value(value: HistoryStore()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SearchPage()),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '庆');
    // 去抖 350ms，到点后联想请求才发出。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('庆余年'), findsOneWidget);
    expect(find.text('庆余年 第二季'), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(2));

    // 提交搜索会触发历史关键词落盘（真实文件 I/O），在 widget 测试的
    // fake async 区里完成后会留下 Windows 文件锁；这部分改由 store 层用例覆盖。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
  });

  testWidgets('分类页在有首字母时显示 A–Z 侧栏', (WidgetTester tester) async {
    final FakeHttpClient client = letterClient(<Map<String, Object>>[
      item(1, 'Alpha', letter: 'A'),
      item(2, 'Beta', letter: 'B'),
    ]);
    useFakeApi(client);

    final BrowseStore browse = BrowseStore();
    await browse.attach(s1);

    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BrowseStore>.value(value: browse),
          ChangeNotifierProvider<HistoryStore>.value(value: HistoryStore()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CategoryPage()),
        ),
      ),
    );
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('全'), findsOneWidget);
  });
}
