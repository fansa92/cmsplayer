import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/errors.dart';
import 'package:cms_player/data/api/maccms_api.dart';
import 'package:cms_player/data/models/vod_source.dart';

import 'helpers/fakes.dart';

/// macCMS 接口兼容层：老 ac=videolist、顶层错误码、XML 老格式、
/// order/letter 新参数，以及联想词的多形状解析与降级。
void main() {
  useIsolatedStores();

  final VodSource source = sourceOf('老站', host: 'old.com');

  Map<String, Object> pageOf(List<Map<String, Object>> list) =>
      vodPageJson(list: list, total: list.length);

  Map<String, Object> plain(int id) =>
      vodJson(id: id, name: '片子$id');

  Map<String, Object> playable(int id) => vodJson(
        id: id,
        name: '片子$id',
        playFrom: 'm3u8',
        playUrl: r'第01集$https://a.com/1.m3u8',
      );

  group('ac=detail → videolist 自动降级', () {
    test('detail 返回条目却没有播放地址时重试 videolist', () async {
      final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
        final Map<String, String> q = r.url.queryParameters;
        return fakeJson(pageOf(<Map<String, Object>>[
          q['ac'] == 'videolist' ? playable(7) : plain(7),
        ]));
      });
      useFakeApi(client);

      final MacCmsApi api = MacCmsApi(source, client: client);
      final item = await api.detail(7);

      expect(item, isNotNull);
      expect(item!.hasPlayInfo, isTrue);
      expect(client.requests.length, 2);
      expect(client.requests.first.url.queryParameters['ac'], 'detail');
      expect(client.requests.last.url.queryParameters['ac'], 'videolist');
    });

    test('记住只认 videolist 的源，换实例后直接走 videolist', () async {
      final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
        final Map<String, String> q = r.url.queryParameters;
        final int id = int.tryParse(q['ids'] ?? '7') ?? 7;
        return fakeJson(pageOf(<Map<String, Object>>[
          q['ac'] == 'videolist' ? playable(id) : plain(id),
        ]));
      });
      useFakeApi(client);

      await MacCmsApi(source, client: client).detail(7);
      await MacCmsApi(source, client: client).detail(8);

      expect(
        client.requests
            .map((RecordedRequest r) => r.url.queryParameters['ac'])
            .toList(),
        <String>['detail', 'videolist', 'videolist'],
      );
    });

    test('detail 抛错时退回 videolist；两个都失败才抛错', () async {
      final FakeHttpClient ok = FakeHttpClient((RecordedRequest r) =>
          fakeJson(pageOf(<Map<String, Object>>[playable(7)])));
      useFakeApi(ok);
      ok.queued.add(fakeResponse(500, 'no detail'));

      final MacCmsApi api = MacCmsApi(source, client: ok);
      expect((await api.detail(7))!.hasPlayInfo, isTrue);
      expect(ok.requests.length, 2);

      final FakeHttpClient bad = FakeHttpClient((RecordedRequest r) =>
          fakeResponse(500, 'down'));
      final MacCmsApi failing = MacCmsApi(source, client: bad);
      await expectLater(failing.detail(7), throwsA(isA<VodException>()));
      expect(bad.requests.length, 2);
    });

    test('列表查询不因为缺播放地址而多打一次请求', () async {
      final FakeHttpClient client = FakeHttpClient((RecordedRequest r) =>
          fakeJson(pageOf(<Map<String, Object>>[plain(7)])));
      useFakeApi(client);

      await MacCmsApi(source, client: client).query(detail: true);

      expect(client.requests, hasLength(1));
      expect(client.last.url.queryParameters['ac'], 'detail');
    });
  });

  group('顶层 code / msg', () {
    test('code=0 且没有数据时把 msg 透出来', () {
      expect(
        () => MacCmsApi.parseVodPage(
          '{"code":0,"msg":"接口已关闭","list":[]}',
        ),
        throwsA(
          isA<VodException>().having(
            (VodException e) => e.message,
            'message',
            contains('接口已关闭'),
          ),
        ),
      );
    });

    test('code=0 但带着正常 list 时不误伤', () {
      final page = MacCmsApi.parseVodPage(
        '{"code":0,"list":[{"vod_id":1,"vod_name":"还在"}]}',
      );
      expect(page.items.single.name, '还在');
    });

    test('msg 为空时给出带 code 的兜底文案', () {
      expect(
        () => MacCmsApi.parseVodPage('{"code":0,"list":[]}'),
        throwsA(isA<VodException>().having(
          (VodException e) => e.message,
          'message',
          contains('code=0'),
        )),
      );
    });
  });

  group('at=json 与老 XML 响应', () {
    test('查询显式带 at=json，用户没设过的参数保持不发送', () async {
      final FakeHttpClient client = FakeHttpClient((RecordedRequest r) =>
          fakeJson(pageOf(<Map<String, Object>>[])));
      useFakeApi(client);

      await MacCmsApi(source, client: client).query();

      final Map<String, String> q = client.last.url.queryParameters;
      expect(q['at'], 'json');
      expect(q.containsKey('order'), isFalse);
      expect(q.containsKey('letter'), isFalse);
    });

    test('v8 采集接口的 RSS/XML 能解析成条目、分类与播放线路', () {
      const String xml = '''
<?xml version="1.0" encoding="utf-8"?>
<rss version="5.0">
<list page="2" pagecount="9" pagesize="20" recordcount="170">
  <video>
    <last>2019-02-06 13:32:28</last>
    <id>493</id><tid>9</tid>
    <name><![CDATA[流浪地球]]></name>
    <type>恐怖片</type><pic>https://p/1.jpg</pic>
    <lang>国语</lang><area>大陆</area><year>2019</year><state>1</state>
    <note><![CDATA[HD]]></note>
    <actor><![CDATA[吴京]]></actor><director><![CDATA[郭帆]]></director>
    <des><![CDATA[<p>简介<br>第二行</p>]]></des>
    <dl><dd from="m3u8"><![CDATA[第1集\$https://a.com/1.m3u8#第2集\$https://a.com/2.m3u8]]></dd></dl>
  </video>
</list>
<class><ty id="1">电影</ty><ty id="9">科幻片</ty></class>
</rss>
''';

      final page = MacCmsApi.parseVodPage(xml);
      expect(page.page, 2);
      expect(page.pageCount, 9);
      expect(page.total, 170);
      expect(page.categories.map((e) => e.name).toList(),
          <String>['电影', '科幻片']);

      final item = page.items.single;
      expect(item.id, 493);
      expect(item.name, '流浪地球');
      expect(item.year, '2019');
      expect(item.actor, '吴京');
      expect(item.director, '郭帆');
      expect(item.isEnd, isTrue);
      expect(item.playLines.single.name, 'm3u8');
      expect(item.playLines.single.episodes.length, 2);
      expect(item.playLines.single.episodes.first.url,
          'https://a.com/1.m3u8');
      expect(item.content, '简介\n第二行');
    });

    test('HTML 错误页仍然报可读异常', () {
      expect(
        () => MacCmsApi.parseVodPage('<html><body>404</body></html>'),
        throwsA(isA<VodException>()),
      );
    });
  });

  group('order / letter 参数', () {
    test('合法值才发送，letter 统一大写', () async {
      final FakeHttpClient client = FakeHttpClient((RecordedRequest r) =>
          fakeJson(pageOf(<Map<String, Object>>[])));
      useFakeApi(client);
      final MacCmsApi api = MacCmsApi(source, client: client);

      await api.query(order: 'ASC', letter: 'b', sortBy: 'time');
      Map<String, String> q = client.last.url.queryParameters;
      expect(q['order'], 'asc');
      expect(q['letter'], 'B');
      expect(q['by'], 'time');

      await api.query(order: '随便', letter: '中');
      q = client.last.url.queryParameters;
      expect(q.containsKey('order'), isFalse);
      expect(q.containsKey('letter'), isFalse);
    });
  });

  group('联想词', () {
    test('字符串数组、对象数组与嵌套 info.list 都能解析并去重', () {
      expect(
        MacCmsApi.parseSuggest('["庆余年", "庆余年 第二季", "庆余年"]',
            exclude: '庆余年'),
        <String>['庆余年 第二季'],
      );
      expect(
        MacCmsApi.parseSuggest(
          '{"code":1,"info":[{"name":"庆余年"},{"vod_name":"庆余年 2"}]}',
        ),
        <String>['庆余年', '庆余年 2'],
      );
      expect(
        MacCmsApi.parseSuggest('{"data":{"list":[{"word":"A&amp;B"}]}}'),
        <String>['A&B'],
      );
    });

    test('REST 可用时不打 Provide，两个端点都失败才回退到片名', () async {
      final FakeHttpClient client = FakeHttpClient((RecordedRequest r) {
        if (r.url.path.endsWith('/vod/suggest')) {
          return fakeResponse(404, 'not found');
        }
        if (r.url.path.endsWith('/ajax/suggest')) {
          return fakeJson(<String, Object>{
            'code': 1,
            'list': <Map<String, Object>>[
              <String, Object>{'name': '庆余年'},
              <String, Object>{'name': '庆余年 第二季'},
            ],
          });
        }
        return fakeJson(pageOf(<Map<String, Object>>[
          plain(1),
          playable(2),
        ]));
      });
      useFakeApi(client);

      final MacCmsApi api = MacCmsApi(source, client: client);
      final List<String> words = await api.suggest('庆');

      expect(words, <String>['庆余年', '庆余年 第二季']);
      expect(client.requests, hasLength(2));
      expect(client.requests.first.url.path, '/api.php/vod/suggest');
      expect(client.requests.last.url.path, '/index.php/ajax/suggest');

      // 第二个源没有 REST 联想接口：两枪落空后走 ac=list&wd= 拿片名。
      final VodSource other = sourceOf('新站', host: 'new.com');
      final FakeHttpClient fallback = FakeHttpClient((RecordedRequest r) {
        if (r.url.path.contains('suggest')) return fakeResponse(404, 'nope');
        return fakeJson(pageOf(<Map<String, Object>>[
          vodJson(id: 3, name: '庆余年 特别版'),
        ]));
      });
      useFakeApi(fallback);
      final List<String> fallbackWords =
          await MacCmsApi(other, client: fallback).suggest('庆');
      expect(fallbackWords, <String>['庆余年 特别版']);
      expect(fallback.last.url.queryParameters['wd'], '庆');
      expect(fallback.last.url.queryParameters['ac'], 'list');
    });
  });
}
