import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/home_store.dart';

import 'helpers/fakes.dart';

/// 首页多板块：参数、失败隔离、重复内容丢弃。
void main() {
  useIsolatedStores();

  final VodSource s1 = sourceOf('站一', host: 'one.com');
  final VodSource s2 = sourceOf('站二', host: 'two.com');

  Map<String, Object> pageOf(List<Map<String, Object>> list) =>
      vodPageJson(list: list);

  test('attach 后按顺序拉三个板块，参数对齐 macCMS', () async {
    final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
      final Map<String, String> q = r.url.queryParameters;
      if (q['h'] == '24') {
        return fakeJson(pageOf(<Map<String, Object>>[
          vodJson(id: 1, name: '今日一'),
          vodJson(id: 2, name: '今日二'),
        ]));
      }
      if (q['m'] == '30') {
        return fakeJson(pageOf(<Map<String, Object>>[
          vodJson(id: 11, name: '本月一'),
        ]));
      }
      if (q['by'] == 'score') {
        return fakeJson(pageOf(<Map<String, Object>>[
          vodJson(id: 21, name: '高分一'),
          vodJson(id: 22, name: '高分二'),
        ]));
      }
      return fakeJson(pageOf(<Map<String, Object>>[]));
    });
    useFakeApi(client);

    final HomeStore store = HomeStore();
    await store.attach(s1);

    expect(store.loading, isFalse);
    expect(store.sections.map((HomeSection e) => e.id).toList(),
        <String>['day', 'month', 'score']);
    expect(store.sections[0].title, '今日热播');
    expect(store.sections[1].title, '本月热门');
    expect(store.sections[2].title, '高分佳作');
    expect(store.sections[0].items, hasLength(2));
    expect(store.sections[2].items, hasLength(2));

    final List<Map<String, String>> params =
        client.requests.map((RecordedRequest r) => r.url.queryParameters).toList();
    expect(params.any((Map<String, String> q) => q['h'] == '24'), isTrue);
    expect(params.any((Map<String, String> q) => q['m'] == '30'), isTrue);
    expect(params.any((Map<String, String> q) => q['by'] == 'score'), isTrue);
    // 串行拉取：三个板块各一次主请求，没有并发重复。
    expect(client.requests, hasLength(3));
  });

  test('单个板块失败只丢它自己', () async {
    final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
      final Map<String, String> q = r.url.queryParameters;
      if (q['h'] == '24') return fakeResponse(500, 'down');
      if (q['m'] == '30') {
        return fakeJson(pageOf(<Map<String, Object>>[
          vodJson(id: 11, name: '本月一'),
        ]));
      }
      if (q['by'] == 'score') {
        return fakeJson(pageOf(<Map<String, Object>>[
          vodJson(id: 21, name: '高分一'),
        ]));
      }
      return fakeJson(pageOf(<Map<String, Object>>[]));
    });
    useFakeApi(client);

    final HomeStore store = HomeStore();
    await store.attach(s1);

    // 今日热播 500 之后 hot() 会退化成普通列表查询，这里同样给空页，
    // 最终这个板块就是空的、被跳过，但不影响后面两个。
    expect(store.sections.map((HomeSection e) => e.id).toList(),
        <String>['month', 'score']);
  });

  test('与前面板块高度重合的板块被丢弃', () async {
    // 站点不认 m 参数时，hot(month) 会退回普通列表，内容和今日热播一样。
    final List<Map<String, Object>> same = <Map<String, Object>>[
      vodJson(id: 1, name: '片一'),
      vodJson(id: 2, name: '片二'),
      vodJson(id: 3, name: '片三'),
    ];
    final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
      final Map<String, String> q = r.url.queryParameters;
      if (q['h'] == '24') return fakeJson(pageOf(same));
      if (q['m'] == '30') return fakeJson(pageOf(same));
      if (q['by'] == 'score') {
        return fakeJson(pageOf(<Map<String, Object>>[
          vodJson(id: 31, name: '高分一'),
        ]));
      }
      return fakeJson(pageOf(<Map<String, Object>>[]));
    });
    useFakeApi(client);

    final HomeStore store = HomeStore();
    await store.attach(s1);

    expect(store.sections.map((HomeSection e) => e.id).toList(),
        <String>['day', 'score'],
        reason: '本月热门和今日热播是同一批片子，不该重复展示');
  });

  test('空板块不出现，全部为空时 sections 为空', () async {
    final FakeHttpClient client =
        FakeHttpClient((RecordedRequest r) => fakeJson(pageOf(<Map<String, Object>>[])));
    useFakeApi(client);

    final HomeStore store = HomeStore();
    await store.attach(s1);

    expect(store.sections, isEmpty);
    expect(store.isEmpty, isTrue);
    expect(store.loading, isFalse);
  });

  test('同一资源站重复 attach 不重复请求', () async {
    final FakeHttpClient client = FakeHttpClient(
      (RecordedRequest r) => fakeJson(pageOf(<Map<String, Object>>[
            vodJson(id: 1, name: '片一'),
          ])),
    );
    useFakeApi(client);

    final HomeStore store = HomeStore();
    await store.attach(s1);
    final int count = client.requests.length;
    await store.attach(s1);

    expect(client.requests, hasLength(count));
  });

  test('换源途中到达的旧结果不会覆盖新源', () async {
    final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
      final bool old = r.url.host == 'one.com';
      return fakeJson(pageOf(<Map<String, Object>>[
        vodJson(id: old ? 1 : 99, name: old ? '旧源片' : '新源片'),
      ]));
    });
    useFakeApi(client);

    final HomeStore store = HomeStore();
    // 不 await 第一个 attach：模拟用户在站一的板块还没拉完时就切到站二。
    final Future<void> first = store.attach(s1);
    await store.attach(s2);
    await first;

    expect(store.source!.id, s2.id);
    final Set<int> ids = store.sections
        .expand((HomeSection e) => e.items)
        .map((VodItem e) => e.id)
        .toSet();
    expect(ids, <int>{99}, reason: '旧源的板块结果必须被丢弃');
  });
}
