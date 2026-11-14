import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/state/source_compare_store.dart';

import 'helpers/fakes.dart';

/// 全源对比：同名匹配、年代过滤、排序、失败兜底。
void main() {
  useIsolatedStores();

  final VodSource a = sourceOf('A 站', host: 'a.com');
  final VodSource b = sourceOf('B 站', host: 'b.com');
  final VodSource c = sourceOf('C 站', host: 'c.com');
  final VodSource d = sourceOf('D 站', host: 'd.com');

  String episodes(int id, int count) => List<String>.generate(
        count,
        (int i) => '第${i + 1}集\$https://a.com/$id/$i.m3u8',
      ).join('#');

  Map<String, Object> item({
    required int id,
    required String name,
    String year = '2019',
    int count = 10,
  }) =>
      vodJson(
        id: id,
        name: name,
        year: year,
        playFrom: 'm3u8',
        playUrl: episodes(id, count),
      );

  void serve() {
    final FakeHttpClient client = FakeHttpClient((RecordedRequest request) {
      switch (request.url.host) {
        case 'a.com':
          return fakeJson(vodPageJson(
            list: <Map<String, Object>>[
              item(id: 1, name: '庆余年 高清', count: 10),
              item(id: 2, name: '完全无关的片子', count: 3),
            ],
            total: 2,
          ));
        case 'b.com':
          return fakeJson(vodPageJson(
            list: <Map<String, Object>>[
              item(id: 3, name: '庆余年', count: 13),
            ],
            total: 1,
          ));
        case 'c.com':
          // 同名但年代不同：同名翻拍，不该算进来。
          return fakeJson(vodPageJson(
            list: <Map<String, Object>>[
              item(id: 4, name: '庆余年', year: '2024', count: 20),
            ],
            total: 1,
          ));
        default:
          return fakeResponse(500, 'boom');
      }
    });
    useFakeApi(client);
  }

  test('同名片跨源比对：集数、可播放、排序', () async {
    serve();
    final SourceCompareStore store = SourceCompareStore();
    addTearDown(store.dispose);

    await store.compare(
      title: '庆余年（2019）',
      year: '2019',
      sources: <VodSource>[a, b, c, d],
    );

    expect(store.running, isFalse);
    expect(store.foundCount, 2);
    expect(store.playableCount, 2);
    expect(store.failedCount, 1);

    // 能播的在前，集数多的优先；没找到的第三；失败的垫底。
    expect(
      store.entries.map((CompareEntry e) => e.source.name),
      <String>['B 站', 'A 站', 'C 站', 'D 站'],
    );
    expect(store.entries[0].episodeCount, 13);
    expect(store.entries[1].episodeCount, 10);
    expect(store.entries[2].status, CompareStatus.missing);
    expect(store.entries[3].status, CompareStatus.failed);

    final CompareEntry? best = store.best;
    expect(best, isNotNull);
    expect(best!.source.id, b.id);
    expect(best.episodeCount, 13);
  });

  test('搜索关键词会去掉括号里的年代', () async {
    final List<Uri> urls = <Uri>[];
    final FakeHttpClient client = FakeHttpClient((RecordedRequest request) {
      urls.add(request.url);
      return fakeJson(vodPageJson(list: <Map<String, Object>>[
        item(id: 1, name: '庆余年', count: 5),
      ]));
    });
    useFakeApi(client);

    final SourceCompareStore store = SourceCompareStore();
    addTearDown(store.dispose);
    await store.compare(
      title: '庆余年(2019)',
      year: '2019',
      sources: <VodSource>[a],
    );

    expect(urls, isNotEmpty);
    expect(urls.first.queryParameters['wd'], '庆余年');
  });

  test('没有源时不发请求，直接是空结果', () async {
    final FakeHttpClient client = FakeHttpClient();
    useFakeApi(client);

    final SourceCompareStore store = SourceCompareStore();
    addTearDown(store.dispose);
    await store.compare(title: '随便', sources: const <VodSource>[]);

    expect(store.entries, isEmpty);
    expect(store.running, isFalse);
    expect(client.requests, isEmpty);
  });

  test('新一轮对比会丢弃上一轮的迟到结果', () async {
    final Completer<void> gate = Completer<void>();
    final FakeHttpClient client = FakeHttpClient((RecordedRequest request) {
      if (request.url.host == 'slow.com') {
        return fakeResponse(200, '{"code":1,"list":[]}');
      }
      return fakeJson(vodPageJson(list: <Map<String, Object>>[
        item(id: 1, name: '庆余年', count: 6),
      ]));
    });
    client.gate = gate.future;
    useFakeApi(client);

    final SourceCompareStore store = SourceCompareStore();
    addTearDown(store.dispose);

    final Future<void> first = store.compare(
      title: '庆余年',
      sources: <VodSource>[a],
    );
    final Future<void> second = store.compare(
      title: '另一部片',
      sources: <VodSource>[b],
    );
    gate.complete();
    await Future.wait<void>(<Future<void>>[first, second]);

    expect(store.title, '另一部片');
    expect(store.entries.length, 1);
    expect(store.entries.single.source.id, b.id);
  });
}
