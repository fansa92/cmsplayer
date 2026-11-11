import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/browse_store.dart';
import 'package:cms_player/state/search_store.dart';

import 'helpers/fakes.dart';

/// 首页浏览与搜索的状态机：分页、筛选、多源聚合、失败兜底、搜索历史。
///
/// 网络全部接到假客户端上；仓储缓存由 useIsolatedStores 在用例间清空。
void main() {
  useIsolatedStores();

  final VodSource s1 = sourceOf('站一', host: 'one.com');
  final VodSource s2 = sourceOf('站二', host: 'two.com');

  // 让列表响应自带 class，refresh 就不会再补一次分类请求，
  // 于是 client.last 始终是本次主查询，断言参数时不会被干扰。
  final List<Map<String, Object>> sampleClasses = <Map<String, Object>>[
    <String, Object>{'type_id': 6, 'type_name': '动作片'},
  ];

  /// 按 pg / wd / 站点 host 生成分页响应的假客户端。
  FakeHttpClient pagingClient({
    List<Map<String, Object>>? classes,
    int pageCount = 2,
    Set<String>? failingHosts,
  }) =>
      FakeHttpClient((RecordedRequest r) {
        if (failingHosts?.contains(r.url.host) ?? false) {
          return fakeResponse(500, 'down');
        }
        final Map<String, String> q = r.url.queryParameters;
        final int pg = int.tryParse(q['pg'] ?? '1') ?? 1;
        final String wd = q['wd'] ?? '';
        return fakeJson(vodPageJson(
          list: <Map<String, Object>>[
            vodJson(id: pg * 10, name: '${r.url.host}#$wd-P$pg-A'),
            vodJson(id: pg * 10 + 1, name: '${r.url.host}#$wd-P$pg-B'),
          ],
          classes: classes,
          page: pg,
          pageCount: pageCount,
          total: pageCount * 20,
        ));
      });

  group('BrowseStore', () {
    test('attach 重置分页并拉取首页，响应里的 class 直接当分类', () async {
      final FakeHttpClient client = pagingClient(
        classes: <Map<String, Object>>[
          <String, Object>{'type_id': 6, 'type_name': '动作片'},
        ],
      );
      useFakeApi(client);
      final BrowseStore store = BrowseStore();

      await store.attach(s1);

      expect(store.loading, isFalse);
      expect(store.error, isNull);
      expect(store.items, hasLength(2));
      expect(store.pageNo, 1);
      expect(store.pageCount, 2);
      expect(store.canLoadMore, isTrue);
      expect(store.source!.id, s1.id);
      expect(store.categories.single.name, '动作片');
      // class 随列表一起回来了，不该再单独打一次分类请求。
      expect(client.requests, hasLength(1));
    });

    test('响应没带 class 时才补一次分类请求', () async {
      final FakeHttpClient client = pagingClient();
      useFakeApi(client);
      final BrowseStore store = BrowseStore();

      await store.attach(s1);

      expect(client.requests, hasLength(2));
      expect(client.requests.last.url.queryParameters['ac'], 'list');
    });

    test('attach 会清空上一个源的筛选与列表', () async {
      final FakeHttpClient client = pagingClient();
      useFakeApi(client);
      final BrowseStore store = BrowseStore();
      await store.attach(s1);
      await store.applyFilter(year: '2024', area: '美国');
      expect(store.hasFilter, isTrue);

      await store.attach(s2);

      expect(store.source!.id, s2.id);
      expect(store.hasFilter, isFalse);
      expect(store.pageNo, 1);
      expect(store.items, hasLength(2));
    });

    test('loadMore 追加条目并推进页码，最后一页不再请求', () async {
      final FakeHttpClient client = pagingClient(pageCount: 2);
      useFakeApi(client);
      final BrowseStore store = BrowseStore();
      await store.attach(s1);
      final int before = client.requests.length;

      await store.loadMore();
      expect(store.items, hasLength(4));
      expect(store.pageNo, 2);
      expect(store.canLoadMore, isFalse);
      expect(store.loadingMore, isFalse);
      expect(client.requests.length, before + 1);

      await store.loadMore();
      expect(client.requests.length, before + 1, reason: '没有下一页就不该发请求');
    });

    test('selectCategory 清空旧列表并回到第一页', () async {
      final FakeHttpClient client =
          pagingClient(pageCount: 3, classes: sampleClasses);
      useFakeApi(client);
      final BrowseStore store = BrowseStore();
      await store.attach(s1);
      await store.loadMore();
      expect(store.pageNo, 2);

      await store.selectCategory(6);
      expect(store.typeId, 6);
      expect(store.pageNo, 1);
      expect(store.items, hasLength(2));
      expect(client.last.url.queryParameters['t'], '6');
      expect(store.hasFilter, isTrue);

      final int count = client.requests.length;
      await store.selectCategory(6);
      expect(client.requests.length, count, reason: '重复选同一个分类不重复拉');
    });

    test('applyFilter 只在真的变化时刷新，参数名对齐 macCMS', () async {
      final FakeHttpClient client = pagingClient(classes: sampleClasses);
      useFakeApi(client);
      final BrowseStore store = BrowseStore();
      await store.attach(s1);
      final int count = client.requests.length;

      await store.applyFilter(year: '', area: '');
      expect(client.requests.length, count, reason: '值没变就不刷新');

      await store.applyFilter(year: '2024', area: '美国', sortBy: 'hits');
      expect(store.hasFilter, isTrue);
      final Map<String, String> q = client.last.url.queryParameters;
      expect(q['year'], '2024');
      expect(q['area'], '美国');
      expect(q['by'], 'hits');
      expect(q.containsKey('yy'), isFalse);

      await store.clearFilter();
      expect(store.hasFilter, isFalse);
      expect(store.typeId, 0);
      expect(store.pageNo, 1);
    });

    test('setPageSize 重置分页并把新值发给接口', () async {
      final FakeHttpClient client = pagingClient(classes: sampleClasses);
      useFakeApi(client);
      final BrowseStore store = BrowseStore();
      await store.attach(s1);
      await store.loadMore();

      await store.setPageSize(36);

      expect(store.pageSize, 36);
      expect(store.pageNo, 1);
      expect(client.last.url.queryParameters['pagesize'], '36');
    });

    test('请求失败时留下 error 并复位 loading', () async {
      final FakeHttpClient client =
          pagingClient(failingHosts: <String>{'one.com'});
      useFakeApi(client);
      final BrowseStore store = BrowseStore();

      await store.attach(s1);

      expect(store.error, isNotNull);
      expect(store.error, contains('HTTP 500'));
      expect(store.loading, isFalse);
      expect(store.items, isEmpty);
    });

    test('categoryTitle 与只有叶子分类可点', () async {
      final FakeHttpClient client = pagingClient(
        classes: <Map<String, Object>>[
          <String, Object>{
            'type_id': 1,
            'type_name': '电影片',
            'type_pid': 0,
          },
          <String, Object>{
            'type_id': 6,
            'type_name': '动作片',
            'type_pid': 1,
          },
        ],
      );
      useFakeApi(client);
      final BrowseStore store = BrowseStore();

      expect(store.categoryTitle, '全部');
      await store.attach(s1);
      expect(store.categories, hasLength(2));
      // VodCategory.leafOnly 的规则已在 widget_test 覆盖，这里只验证透传。
      expect(store.selectableCategories.length, 1);
      expect(store.selectableCategories.single.name, '动作片');
      await store.selectCategory(6);
      expect(store.categoryTitle, '动作片');
    });
  });

  group('分类多选与已完结筛选', () {
    final List<Map<String, Object>> classes = <Map<String, Object>>[
      <String, Object>{'type_id': 6, 'type_name': '动作片', 'type_pid': 0},
      <String, Object>{'type_id': 7, 'type_name': '喜剧片', 'type_pid': 0},
    ];

    /// 固定条目 + 固定分类表的假客户端，用来观察筛选参数与本地过滤。
    FakeHttpClient listClient(List<Map<String, Object>> list) =>
        FakeHttpClient((RecordedRequest r) {
          return fakeJson(vodPageJson(
            list: list,
            classes: classes,
            total: list.length,
          ));
        });

    test('多选分类把 t 拼成逗号分隔的 id', () async {
      final FakeHttpClient client = listClient(<Map<String, Object>>[
        vodJson(id: 1, name: 'A'),
      ]);
      useFakeApi(client);
      final BrowseStore store = BrowseStore();
      await store.attach(s1);

      await store.setCategories(<int>{6, 7});

      expect(client.last.url.queryParameters['t'], '6,7');
      expect(store.selectedCategoryIds, <int>{6, 7});
      expect(store.categoryTitle, '动作片 等 2 类');
      expect(store.pageNo, 1);
    });

    test('toggleCategory 累加与取消，取消到空回到全部', () async {
      final FakeHttpClient client = listClient(<Map<String, Object>>[
        vodJson(id: 1, name: 'A'),
      ]);
      useFakeApi(client);
      final BrowseStore store = BrowseStore();
      await store.attach(s1);

      await store.toggleCategory(6);
      expect(store.selectedCategoryIds, <int>{6});
      expect(store.categoryTitle, '动作片');

      await store.toggleCategory(7);
      expect(store.selectedCategoryIds, <int>{6, 7});

      await store.toggleCategory(6);
      expect(store.selectedCategoryIds, <int>{7});

      await store.toggleCategory(7);
      expect(store.selectedCategoryIds, isEmpty);
      expect(store.categoryTitle, '全部');
      // 空集合的查询缓存键与 attach 那一次相同，直接断言 last 会读到旧请求，
      // 这里强制发一次再验证「没有 t 参数」。
      await store.refresh(force: true);
      expect(client.last.url.queryParameters.containsKey('t'), isFalse);
    });

    test('退出多选模式只保留第一个分类', () async {
      final FakeHttpClient client = listClient(<Map<String, Object>>[
        vodJson(id: 1, name: 'A'),
      ]);
      useFakeApi(client);
      final BrowseStore store = BrowseStore();
      await store.attach(s1);

      await store.setMultiSelect(true);
      expect(store.multiSelect, isTrue);
      await store.setCategories(<int>{6, 7});

      await store.setMultiSelect(false);

      expect(store.multiSelect, isFalse);
      expect(store.selectedCategoryIds, <int>{6});
      expect(client.last.url.queryParameters['t'], '6');
    });

    test('已完结：请求带 isend=1，且本地再筛一遍', () async {
      // 模拟"站点不认 isend、原样返回"的行为：混合数据全给回来。
      final FakeHttpClient client = listClient(<Map<String, Object>>[
        vodJson(id: 1, name: '完结的', isEnd: true),
        vodJson(id: 2, name: '连载的', isEnd: false),
        vodJson(id: 3, name: '也完结的', isEnd: true),
      ]);
      useFakeApi(client);
      final BrowseStore store = BrowseStore();
      await store.attach(s1);
      expect(store.items, hasLength(3));

      await store.applyFilter(onlyFinished: true);

      expect(client.last.url.queryParameters['isend'], '1');
      expect(store.onlyFinished, isTrue);
      expect(store.items.map((VodItem e) => e.id).toList(), <int>[1, 3]);
    });

    test('已完结：源站没给 vod_isend 时按备注兜底', () async {
      final FakeHttpClient client = listClient(<Map<String, Object>>[
        vodJson(id: 1, name: '写了已完结', remarks: '已完结'),
        vodJson(id: 2, name: '更新中', remarks: '更新至第 12 集'),
        vodJson(id: 3, name: '全 24 集', remarks: '全24集'),
        vodJson(id: 4, name: '什么都没写'),
      ]);
      useFakeApi(client);
      final BrowseStore store = BrowseStore();
      await store.attach(s1);

      await store.applyFilter(onlyFinished: true);

      // 只认备注里明确的完结信号；「更新至」和空备注都不算。
      expect(store.items.map((VodItem e) => e.id).toList(), <int>[1, 3]);
    });

    test('clearFilter 复位分类集合、多选模式与完结筛选', () async {
      final FakeHttpClient client = listClient(<Map<String, Object>>[
        vodJson(id: 1, name: 'A', isEnd: true),
      ]);
      useFakeApi(client);
      final BrowseStore store = BrowseStore();
      await store.attach(s1);

      await store.setMultiSelect(true);
      await store.setCategories(<int>{6, 7});
      await store.applyFilter(onlyFinished: true, year: '2024');
      expect(store.hasFilter, isTrue);

      await store.clearFilter();

      expect(store.hasFilter, isFalse);
      expect(store.selectedCategoryIds, isEmpty);
      expect(store.multiSelect, isFalse);
      expect(store.onlyFinished, isFalse);
      expect(store.year, isEmpty);
      // clearFilter 后的缓存键与 attach 相同，会直接命中，这里强制再拉一次。
      await store.refresh(force: true);
      expect(client.last.url.queryParameters.containsKey('isend'), isFalse);
    });
  });

  group('SearchStore', () {
    test('单源搜索填充结果、来源映射与搜索历史', () async {
      final FakeHttpClient client = pagingClient();
      useFakeApi(client);
      final SearchStore store = SearchStore();

      await store.search(
        keyword: '  庆余年  ',
        active: s1,
        all: <VodSource>[s1],
      );

      expect(store.query, '庆余年');
      expect(store.items, hasLength(2));
      expect(store.hasResult, isTrue);
      expect(store.loading, isFalse);
      expect(store.sourceOf(store.items.first)!.id, s1.id);
      expect(store.history, <String>['庆余年']);
      expect(client.last.url.queryParameters['wd'], '庆余年');
    });

    test('空关键词与没有可用源时不发请求', () async {
      final FakeHttpClient client = pagingClient();
      useFakeApi(client);
      final SearchStore store = SearchStore();

      await store.search(keyword: '   ', active: s1, all: <VodSource>[s1]);
      expect(client.requests, isEmpty);

      await store.search(
        keyword: 'x',
        active: null,
        all: const <VodSource>[],
      );
      expect(store.error, '请先添加并启用一个资源站');
      expect(client.requests, isEmpty);
    });

    test('多源结果按「片名 + 年代」聚合，页码取各源最大值', () async {
      // 两个源返回同名同年代的条目，但 id 不同（各站自增，必然不同）。
      final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
        final int pg = int.tryParse(r.url.queryParameters['pg'] ?? '1') ?? 1;
        final int idBase = r.url.host == 'one.com' ? 100 : 200;
        return fakeJson(vodPageJson(
          list: <Map<String, Object>>[
            vodJson(id: idBase + pg, name: '同一部片子', year: '2024'),
          ],
          page: pg,
          pageCount: 2,
          total: 20,
        ));
      });
      useFakeApi(client);
      final SearchStore store = SearchStore();

      await store.search(
        keyword: '片子',
        active: s1,
        all: <VodSource>[s1, s2],
        multiSource: true,
      );

      expect(store.multiSource, isTrue);
      expect(store.items, hasLength(1), reason: '两个源的同名片只留一条');
      expect(store.sourceCountOf(store.items.single), 2);
      expect(store.sourceOf(store.items.single)!.id, s1.id);
      expect(store.pageCount, 2);
      expect(store.canLoadMore, isTrue);
      expect(client.requests, hasLength(2));
    });

    test('同名但年代不同不合并', () async {
      final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
        final bool first = r.url.host == 'one.com';
        return fakeJson(vodPageJson(
          list: <Map<String, Object>>[
            vodJson(id: first ? 1 : 2, name: '同名片', year: first ? '2024' : '1998'),
          ],
          total: 1,
        ));
      });
      useFakeApi(client);
      final SearchStore store = SearchStore();

      await store.search(
        keyword: '同名',
        active: s1,
        all: <VodSource>[s1, s2],
        multiSource: true,
      );

      expect(store.items, hasLength(2), reason: '同名不同年不能当同一部片');
      expect(store.sourceCountOf(store.items.first), 1);
    });

    test('片名带「国语版」「(2024)」等尾巴仍能聚合', () async {
      final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
        final bool first = r.url.host == 'one.com';
        return fakeJson(vodPageJson(
          list: <Map<String, Object>>[
            vodJson(
              id: first ? 1 : 2,
              // 域名不同，但片名收敛后一致，应该被当成同一部。
              name: first ? '流浪地球 2 (2023)' : '流浪地球2国语版',
              year: '2023',
            ),
          ],
          total: 1,
        ));
      });
      useFakeApi(client);
      final SearchStore store = SearchStore();

      await store.search(
        keyword: '流浪地球',
        active: s1,
        all: <VodSource>[s1, s2],
        multiSource: true,
      );

      expect(store.items, hasLength(1));
      expect(store.sourceCountOf(store.items.single), 2);
    });

    test('代表条目优先取有播放地址、集数多的那条', () async {
      final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
        final bool first = r.url.host == 'one.com';
        return fakeJson(vodPageJson(
          list: <Map<String, Object>>[
            vodJson(
              id: first ? 1 : 2,
              name: '同一部片子',
              year: '2024',
              // 第一个源没给播放地址，第二个源给了两集。
              playFrom: first ? '' : '线路一',
              playUrl: first ? '' : r'第1集$https://a/1.m3u8#第2集$https://a/2.m3u8',
            ),
          ],
          total: 1,
        ));
      });
      useFakeApi(client);
      final SearchStore store = SearchStore();

      await store.search(
        keyword: '片子',
        active: s1,
        all: <VodSource>[s1, s2],
        multiSource: true,
      );

      final VodItem only = store.items.single;
      expect(only.hasPlayInfo, isTrue, reason: '应换成有播放地址的那条');
      expect(only.episodeCount, 2);
      // 代表换了，来源标签也要跟着换成它所在的源。
      expect(store.sourceOf(only)!.id, s2.id);
      expect(store.sourceCountOf(only), 2);
    });

    test('多源里单个源失败只丢它自己的结果', () async {
      final FakeHttpClient client =
          pagingClient(pageCount: 1, failingHosts: <String>{'two.com'});
      useFakeApi(client);
      final SearchStore store = SearchStore();

      await store.search(
        keyword: '片子',
        active: s1,
        all: <VodSource>[s1, s2],
        multiSource: true,
      );

      expect(store.error, isNull);
      expect(store.items, hasLength(2));
      expect(store.items.every((Object e) => e.toString().contains('one.com')),
          isTrue,
          reason: '只剩成功那个源的结果');
    });

    test('loadMore 追加下一页，到最后一页后不再请求', () async {
      final FakeHttpClient client = pagingClient(pageCount: 2);
      useFakeApi(client);
      final SearchStore store = SearchStore();
      await store.search(keyword: '片子', active: s1, all: <VodSource>[s1]);
      final int count = client.requests.length;

      await store.loadMore(active: s1, all: <VodSource>[s1]);
      expect(store.items, hasLength(4));
      expect(store.pageNo, 2);
      expect(store.canLoadMore, isFalse);

      await store.loadMore(active: s1, all: <VodSource>[s1]);
      expect(client.requests.length, count + 1);
    });

    test('搜索历史去重、保序、上限 30，可删除与清空', () async {
      final FakeHttpClient client = pagingClient();
      useFakeApi(client);
      final SearchStore store = SearchStore();
      for (int i = 0; i < 32; i++) {
        await store.search(
          keyword: 'k$i',
          active: s1,
          all: <VodSource>[s1],
        );
      }
      await store.search(keyword: 'k0', active: s1, all: <VodSource>[s1]);

      expect(store.history, hasLength(30));
      expect(store.history.first, 'k0', reason: '重复搜索要挪到最前');
      expect(store.history.where((String q) => q == 'k0'), hasLength(1));
      expect(store.history.contains('k0'), isTrue);
      expect(store.history.contains('k1'), isFalse, reason: '最老的两条被挤掉');

      await store.removeHistory('k0');
      expect(store.history.contains('k0'), isFalse);
      await store.clearHistory();
      expect(store.history, isEmpty);
    });

    test('历史能从磁盘读回，clearResult 清空结果', () async {
      final FakeHttpClient client = pagingClient();
      useFakeApi(client);
      final SearchStore first = SearchStore();
      await first.search(keyword: '历史词', active: s1, all: <VodSource>[s1]);

      final SearchStore second = SearchStore();
      await second.loadHistory();
      expect(second.history, <String>['历史词']);

      await second.search(keyword: '新词', active: s1, all: <VodSource>[s1]);
      second.clearResult();
      expect(second.query, '');
      expect(second.items, isEmpty);
      expect(second.hasResult, isFalse);
      expect(second.pageNo, 1);
      expect(second.error, isNull);
      expect(second.history, isNotEmpty, reason: '清结果不该清历史');
    });

    test('setMultiSource 与 loadHistory 的幂等', () async {
      final SearchStore store = SearchStore();
      store.setMultiSource(true);
      expect(store.multiSource, isTrue);
      await store.loadHistory();
      await store.loadHistory();
      expect(store.history, isEmpty);
    });
  });
}
