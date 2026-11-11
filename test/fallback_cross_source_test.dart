import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/play_task.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/data/repository/fallback_repository.dart';

import 'helpers/fakes.dart';

/// 跨源降级：在别的资源站里找「同一部片子的同一集」。
///
/// 匹配条件刻意收得很紧 —— 宁可漏掉一次降级，也不能把用户带到另一部片子上。
void main() {
  useIsolatedStores();

  const String playUrl = r'第01集$https://b.com/1.m3u8';

  PlayTask task({String name = '庆余年', String year = '2024'}) => PlayTask(
        source: sourceOf('当前站', host: 'cur.com'),
        item: VodItem(
          id: 1,
          name: name,
          year: year,
          playFrom: 'm3u8',
          playUrl: r'第01集$https://cur.com/1.m3u8',
        ),
        lineIndex: 0,
        episodeIndex: 0,
      );

  Map<String, Object> hit({
    String name = '庆余年',
    String year = '2024',
    String url = playUrl,
    int id = 2,
  }) =>
      vodJson(
        id: id,
        name: name,
        year: year,
        playFrom: 'm3u8',
        playUrl: url,
      );

  /// 按 host 返回搜索结果；failing 里的 host 直接 500。
  FakeHttpClient crossClient(
    Map<String, List<Map<String, Object>>> results, {
    Set<String> failing = const <String>{},
  }) =>
      FakeHttpClient((RecordedRequest r) {
        if (failing.contains(r.url.host)) return fakeResponse(500, 'down');
        return fakeJson(vodPageJson(
          list: results[r.url.host] ?? <Map<String, Object>>[],
        ));
      });

  test('没有候选源或片名为空时直接返回，不发请求', () async {
    final FakeHttpClient client =
        crossClient(<String, List<Map<String, Object>>>{});
    useFakeApi(client);

    expect(await FallbackResolver.crossSource(task(), <VodSource>[]), isEmpty);
    expect(
      await FallbackResolver.crossSource(
        task(name: '  '),
        <VodSource>[sourceOf('备用站')],
      ),
      isEmpty,
    );
    expect(client.requests, isEmpty);
  });

  test('同名、同年代、同集名时给出可播放的跨源候选', () async {
    final VodSource backup = sourceOf('备用站', host: 'b.com');
    final FakeHttpClient client =
        crossClient(<String, List<Map<String, Object>>>{
      'b.com': <Map<String, Object>>[hit()],
    });
    useFakeApi(client);

    final List<SourceFallback> result =
        await FallbackResolver.crossSource(task(), <VodSource>[backup]);

    expect(result, hasLength(1));
    expect(result.single.url, 'https://b.com/1.m3u8');
    expect(result.single.label, '备用站');
    expect(result.single.source.id, backup.id);
    expect(result.single.lineIndex, 0);
    expect(result.single.episodeIndex, 0);
    expect(result.single.item.hasPlayInfo, isTrue);
    expect(client.last.url.queryParameters['wd'], '庆余年');
    expect(client.last.url.queryParameters['ac'], 'detail');
  });

  test('片名带「高清 / 完整版」等修饰后缀仍能匹配', () async {
    final FakeHttpClient client =
        crossClient(<String, List<Map<String, Object>>>{
      'b.com': <Map<String, Object>>[hit(name: '庆余年 高清 完整版')],
    });
    useFakeApi(client);

    final List<SourceFallback> result = await FallbackResolver.crossSource(
      task(),
      <VodSource>[sourceOf('备用站', host: 'b.com')],
    );

    expect(result, hasLength(1));
  });

  test('年代不同 / 集名对不上 / 片名差太远都不降级', () async {
    final VodSource backup = sourceOf('备用站', host: 'b.com');
    final FakeHttpClient client =
        crossClient(<String, List<Map<String, Object>>>{
      'b.com': <Map<String, Object>>[
        hit(year: '2019'),
        hit(url: r'第02集$https://b.com/2.m3u8'),
        hit(name: '庆余年之外传全集特别版'),
        hit(name: '完全是另一部片子'),
      ],
    });
    useFakeApi(client);

    expect(
      await FallbackResolver.crossSource(task(), <VodSource>[backup]),
      isEmpty,
    );
  });

  test('某个源挂了只丢它自己的结果，其它源照常返回', () async {
    final VodSource good = sourceOf('好站', host: 'b.com');
    final VodSource bad = sourceOf('坏站', host: 'bad.com');
    final FakeHttpClient client = crossClient(
      <String, List<Map<String, Object>>>{
        'b.com': <Map<String, Object>>[hit()],
        'bad.com': <Map<String, Object>>[hit()],
      },
      failing: <String>{'bad.com'},
    );
    useFakeApi(client);

    final List<SourceFallback> result =
        await FallbackResolver.crossSource(task(), <VodSource>[bad, good]);

    expect(result, hasLength(1));
    expect(result.single.source.id, good.id);
  });

  test('最多只搜 5 个源，避免一个超时源拖垮整条降级链', () async {
    final FakeHttpClient client =
        crossClient(<String, List<Map<String, Object>>>{});
    useFakeApi(client);
    final List<VodSource> many = List<VodSource>.generate(
      7,
      (int i) => sourceOf('站$i', host: 's$i.com'),
    );

    await FallbackResolver.crossSource(task(), many);

    expect(client.requests, hasLength(5));
  });

  test('最多返回 2 个候选', () async {
    final List<VodSource> sources = <VodSource>[
      sourceOf('甲', host: 's1.com'),
      sourceOf('乙', host: 's2.com'),
      sourceOf('丙', host: 's3.com'),
    ];
    final FakeHttpClient client =
        crossClient(<String, List<Map<String, Object>>>{
      's1.com': <Map<String, Object>>[hit(id: 11)],
      's2.com': <Map<String, Object>>[hit(id: 12)],
      's3.com': <Map<String, Object>>[hit(id: 13)],
    });
    useFakeApi(client);

    final List<SourceFallback> result =
        await FallbackResolver.crossSource(task(), sources);

    expect(result, hasLength(2));
    expect(
        result.map((SourceFallback e) => e.label).toSet(), <String>{'甲', '乙'});
  });

  test('搜索结果没带播放地址时，会再拉一次详情来确认集', () async {
    final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
      final Map<String, String> q = r.url.queryParameters;
      // query(detail: true) 与 ensureDetail 都是 ac=detail，
      // 后者额外带 ids 参数。
      final bool isDetail = q.containsKey('ids');
      return fakeJson(vodPageJson(
        list: <Map<String, Object>>[
          isDetail ? hit() : hit(url: ''), // 列表模式没有播放地址
        ],
      ));
    });
    useFakeApi(client);

    final List<SourceFallback> result = await FallbackResolver.crossSource(
      task(),
      <VodSource>[sourceOf('备用站', host: 'b.com')],
    );

    expect(result, hasLength(1));
    expect(result.single.url, 'https://b.com/1.m3u8');
    expect(
        client.requests.any(
            (RecordedRequest r) => r.url.queryParameters.containsKey('ids')),
        isTrue);
  });
}
