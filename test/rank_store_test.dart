import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/rank_store.dart';

import 'helpers/fakes.dart';

/// 榜单状态：排序参数、分页、失败分支。
///
/// 榜单页本身只是把这些状态摆成网格，逻辑都在 store 里，所以主要测 store。
void main() {
  useIsolatedStores();

  late RankStore rank;
  late VodSource source;

  /// 每次请求都返回一页 2 条、共 3 页的数据。
  FakeHttpClient listClient({int pageCount = 3}) =>
      FakeHttpClient((RecordedRequest r) {
        final int page = int.tryParse(r.url.queryParameters['pg'] ?? '1') ?? 1;
        final String by = r.url.queryParameters['by'] ?? '';
        return fakeJson(vodPageJson(
          page: page,
          pageCount: pageCount,
          total: pageCount * 2,
          list: <Map<String, Object>>[
            for (int i = 0; i < 2; i++)
              vodJson(
                id: page * 10 + i,
                name: '$by-$page-$i',
                playFrom: 'm3u8',
                playUrl: r'第1集$https://a.com/1.m3u8',
              ),
          ],
          classes: <Map<String, Object>>[
            <String, Object>{'type_id': 1, 'type_name': '电影'},
          ],
        ));
      });

  setUp(() {
    rank = RankStore();
    source = sourceOf('测试站');
  });

  tearDown(() => rank.dispose());

  test('默认按最多播放拉第一页', () async {
    final FakeHttpClient client = listClient();
    useFakeApi(client);

    await rank.attach(source);

    expect(rank.sortBy, 'hits');
    expect(rank.loading, isFalse);
    expect(rank.items, hasLength(2));
    expect(rank.pageNo, 1);
    expect(rank.pageCount, 3);
    expect(rank.total, 6);
    expect(rank.canLoadMore, isTrue);
    expect(client.last.url.queryParameters['by'], 'hits');
    expect(client.last.url.queryParameters['pg'], '1');
    expect(client.last.url.queryParameters['ac'], 'detail');
  });

  test('同一个源重复 attach 不再请求', () async {
    final FakeHttpClient client = listClient();
    useFakeApi(client);

    await rank.attach(source);
    final int first = client.requests.length;
    await rank.attach(source);

    expect(client.requests, hasLength(first));
  });

  test('换排序清空旧数据并按新参数重拉', () async {
    final FakeHttpClient client = listClient();
    useFakeApi(client);
    await rank.attach(source);
    expect(rank.items.first.name, startsWith('hits'));

    await rank.setSort('score');

    expect(rank.sortBy, 'score');
    expect(rank.sortLabel, '最高评分');
    expect(rank.items.first.name, startsWith('score'));
    expect(rank.pageNo, 1);
    expect(client.last.url.queryParameters['by'], 'score');
  });

  test('选同一个排序是空操作', () async {
    final FakeHttpClient client = listClient();
    useFakeApi(client);
    await rank.attach(source);
    final int before = client.requests.length;

    await rank.setSort('hits');

    expect(client.requests, hasLength(before));
  });

  test('翻页追加，到末页就不再请求', () async {
    final FakeHttpClient client = listClient();
    useFakeApi(client);
    await rank.attach(source);

    await rank.loadMore();
    expect(rank.items, hasLength(4));
    expect(rank.pageNo, 2);
    expect(client.last.url.queryParameters['pg'], '2');

    await rank.loadMore();
    expect(rank.items, hasLength(6));
    expect(rank.canLoadMore, isFalse);

    final int before = client.requests.length;
    await rank.loadMore();
    expect(client.requests, hasLength(before));
  });

  test('请求失败时给出错误且不再转圈', () async {
    final FakeHttpClient client = FakeHttpClient(
      (RecordedRequest r) => fakeResponse(500, 'down'),
    );
    useFakeApi(client);

    await rank.attach(source);

    expect(rank.loading, isFalse);
    expect(rank.items, isEmpty);
    expect(rank.error, isNotNull);

    // 重试成功应清掉错误。
    client.responder = (RecordedRequest r) => fakeJson(vodPageJson(
          list: <Map<String, Object>>[vodJson(id: 1, name: '回来了')],
          total: 1,
        ));
    await rank.refresh(force: true);

    expect(rank.error, isNull);
    expect(rank.items.single.name, '回来了');
  });

  test('还没绑定源时 refresh 直接返回', () async {
    final FakeHttpClient client = listClient();
    useFakeApi(client);

    await rank.refresh(force: true);
    await rank.loadMore();

    expect(client.requests, isEmpty);
    expect(rank.items, isEmpty);
  });

  test('切源时重置榜单并重新拉取', () async {
    final FakeHttpClient client = listClient();
    useFakeApi(client);
    await rank.attach(source);

    await rank.attach(sourceOf('另一个站', host: 'b.com'));

    expect(rank.source?.name, '另一个站');
    expect(rank.items, hasLength(2));
    expect(client.last.url.host, 'b.com');
  });
}
