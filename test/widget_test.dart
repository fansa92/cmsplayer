import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:cms_player/core/utils/text_utils.dart';
import 'package:cms_player/core/utils/formatter.dart';
import 'package:cms_player/data/api/maccms_api.dart';
import 'package:cms_player/data/api/source_importer.dart';
import 'package:cms_player/data/models/play_line.dart';
import 'package:cms_player/data/models/paged_result.dart';
import 'package:cms_player/data/models/vod_category.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';

void main() {
  group('VodSource', () {
    test('规范化接口地址并生成稳定 ID', () {
      final VodSource a = VodSource.fromRaw(<String, Object>{
        'name': '测试站',
        'api': 'https://example.com/api.php/provide/vod',
      });
      expect(a.api, 'https://example.com/api.php/provide/vod/');
      expect(a.origin, 'https://example.com');
      expect(a.headers['Referer'], 'https://example.com/');

      // 同名同接口重复导入必须得到同一个 ID，避免重复项。
      final VodSource b = VodSource.fromRaw(<String, Object>{
        'name': '测试站',
        'api': 'https://example.com/api.php/provide/vod/',
      });
      expect(a.id, b.id);
    });

    test('自定义 Referer 优先于源站兜底', () {
      final VodSource s = VodSource.fromRaw(<String, Object>{
        'name': 'x',
        'api': 'https://a.com/api.php/provide/vod/',
        'referer': 'https://b.com/',
      });
      expect(s.headers['Referer'], 'https://b.com/');
    });
  });

  group('播放地址解析', () {
    test(r'解析 $$$ / # / $ 三级结构', () {
      const String from = r'm3u8$$$dbm3u8';
      const String url =
          '第01集\$https://a.com/1.m3u8#第02集\$https://a.com/2.m3u8'
          '\$\$\$'
          '第01集\$https://b.com/1.m3u8\$https://c.com/1.m3u8';

      final List<PlayLine> lines = VodItem.parsePlayLines(from, url);

      expect(lines.length, 2);
      expect(lines[0].name, 'm3u8');
      expect(lines[0].episodes.length, 2);
      expect(lines[0].episodes[0].name, '第01集');
      expect(lines[0].episodes[0].url, 'https://a.com/1.m3u8');

      expect(lines[1].name, 'dbm3u8');
      expect(lines[1].episodes[0].mirrors, <String>['https://c.com/1.m3u8']);
    });

    test('线路数与 play_from 不一致时用序号兜底', () {
      final List<PlayLine> lines =
          VodItem.parsePlayLines('m3u8', '第01集\$https://a.com/1.m3u8');
      expect(lines.single.name, 'm3u8');
      expect(lines.single.episodes.single.url, 'https://a.com/1.m3u8');
    });

    test('空输入返回空列表', () {
      expect(VodItem.parsePlayLines(null, ''), isEmpty);
      expect(VodItem.parsePlayLines('m3u8', '#'), isEmpty);
    });
  });

  group('macCMS 响应解析', () {
    test('v10 字典结构', () {
      const String body = '''
      {"code":1,"msg":"数据列表","page":2,"pagecount":9,"total":170,"limit":"20",
       "class":[{"type_id":1,"type_name":"电影","type_pid":0}],
       "list":[{"vod_id":7,"vod_name":" 测试 ","vod_pic":"https://p/1.jpg",
                "type_id":1,"type_name":"电影","vod_remarks":"HD",
                "vod_content":"<p>简介<br>第二行</p>"}]}
      ''';
      final VodPage page = MacCmsApi.parseVodPage(body);

      expect(page.page, 2);
      expect(page.pageCount, 9);
      expect(page.total, 170);
      expect(page.categories.single.name, '电影');
      expect(page.items.single.name, '测试');
      expect(page.items.single.content, '简介\n第二行');
    });

    test('老版本数组结构', () {
      const String body = '[{"vod_id":3,"vod_name":"老片"}]';
      final VodPage page = MacCmsApi.parseVodPage(body);
      expect(page.items.single.id, 3);
      expect(page.pageCount, 1);
    });

    test('缺少 pagecount 时按 total/limit 推算', () {
      const String body =
          '{"total":45,"limit":"20","list":[{"vod_id":1,"vod_name":"a"},'
          '{"vod_id":2,"vod_name":"b"}]}';
      expect(MacCmsApi.parseVodPage(body).pageCount, 3);
    });

    test('非 JSON 抛出可读错误', () {
      expect(
        () => MacCmsApi.parseVodPage('<html>404</html>'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('工具函数', () {
    test('stripHtml 处理标签与实体', () {
      expect(stripHtml('<p>a&nbsp;b&amp;c</p>'), 'a b&c');
    });

    test('isDirectPlayable', () {
      expect(isDirectPlayable('https://a.com/x.m3u8'), isTrue);
      expect(isDirectPlayable('https://a.com/x.mp4?t=1'), isTrue);
      expect(isDirectPlayable('https://a.com/player/?url=abc'), isFalse);
      expect(isDirectPlayable('rtsp://a.com/live'), isTrue);
    });

    test('resolveUrl 补全相对地址', () {
      expect(
        resolveUrl('//cdn.a.com/x.m3u8', base: 'https://site.com/api/'),
        'https://cdn.a.com/x.m3u8',
      );
      expect(
        resolveUrl('/vod/1.m3u8', base: 'https://site.com/api.php/provide/vod/'),
        'https://site.com/vod/1.m3u8',
      );
    });

    test('formatDuration', () {
      expect(formatDuration(const Duration(seconds: 65)), '1:05');
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });
  });

  group('SourceImporter 宽容解析', () {
    test('官方 source.json 的尾逗号不再报"不是合法的 JSON"', () {
      // 官方 cms-player/vod-source/source.json 的真实格式：
      // 若干对象的最后一个属性后面带着逗号（该文件实测 4 处）。
      const String official = '''
      [
          {
              "name": "黑木耳",
              "api": "https://json.heimuer.xyz/api.php/provide/vod/",
          },
          {
              "name": "华为吧",
              "api": "https://hw8.live/api.php/provide/vod/",
          },
          {
              "name": "极速资源",
              "api": "https://jszyapi.com/api.php/provide/vod/"
          }
      ]
      ''';

      // 标准解析必须失败，否则这条用例证明不了问题存在。
      expect(() => jsonDecode(official), throwsA(isA<FormatException>()));

      final List<VodSource> sources = SourceImporter.parse(official);
      expect(sources.length, 3);
      expect(sources[0].name, '黑木耳');
      expect(sources[0].api, 'https://json.heimuer.xyz/api.php/provide/vod/');
      expect(sources[1].name, '华为吧');
      expect(sources[2].api, 'https://jszyapi.com/api.php/provide/vod/');
    });

    test('支持注释，且不误伤字符串内的逗号与斜杠', () {
      const String text = '''
      {
        // 资源站列表
        "sources": [
          {
            "name": "示例站",
            /* 接口地址 */
            "api": "https://a.com/api.php/provide/vod/",
          },
          {
            "name": "带逗号",
            "api": "https://b.com/api.php/provide/vod/?a=1,2#x"
          }
        ]
      }
      ''';

      final List<VodSource> sources = SourceImporter.parse(text);
      expect(sources.length, 2);
      expect(sources[1].api, 'https://b.com/api.php/provide/vod/?a=1,2#x');
    });

    test('跳过 cms:// 等非 http 协议的条目', () {
      const String text = '''
      [
        {"name": "低端影视", "api": "cms://ddys"},
        {"name": "在线之家", "api": "cms://zxzj"},
        {"name": "正常站", "api": "https://ok.com/api.php/provide/vod/"}
      ]
      ''';

      final List<VodSource> sources = SourceImporter.parse(text);
      expect(sources.length, 1);
      expect(sources.single.name, '正常站');
    });

    test('彻底没有可用条目时给出可读错误', () {
      expect(
        () => SourceImporter.parse('[{"name": "没有接口"}]'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('分类分层', () {
    test('剔除被子分类引用的父分类', () {
      // ffzyapi 实测的 class 顺序：1/2/3/4 是 type_pid=0 的父分类，
      // 6/7/13 是它们的子分类。父分类查询返回空，必须排除。
      final List<VodCategory> all = <VodCategory>[
        const VodCategory(id: 1, name: '电影片', parentId: 0),
        const VodCategory(id: 2, name: '连续剧', parentId: 0),
        const VodCategory(id: 6, name: '动作片', parentId: 1),
        const VodCategory(id: 7, name: '喜剧片', parentId: 1),
        const VodCategory(id: 13, name: '国产剧', parentId: 2),
      ];

      expect(
        VodCategory.leafOnly(all).map((VodCategory e) => e.id).toList(),
        <int>[6, 7, 13],
      );
    });

    test('扁平分类原样保留', () {
      final List<VodCategory> flat = <VodCategory>[
        const VodCategory(id: 1, name: 'a'),
        const VodCategory(id: 2, name: 'b'),
      ];
      expect(VodCategory.leafOnly(flat), same(flat));
    });

    test('没有 type_pid 字段时原样保留', () {
      final List<VodCategory> noPid = <VodCategory>[
        const VodCategory(id: 1, name: 'a', parentId: 0),
        const VodCategory(id: 2, name: 'b', parentId: 0),
      ];
      expect(VodCategory.leafOnly(noPid), same(noPid));
    });

    test('空列表原样返回', () {
      expect(VodCategory.leafOnly(const <VodCategory>[]), isEmpty);
    });
  });

  group('查询参数（对齐线上真实行为）', () {
    // 实测 cj.ffzyapi.com：`year=2024` 把 total 从 98497 压到 10963 且返回项
    // 全部是 2024；`yy=2024` 与不带参数的结果 total 和 id 序列完全一致，
    // 即被源站彻底忽略。这里守住参数名，防止回归。
    test('年份走 year 参数，不发 yy', () async {
      final _RecordingClient client = _RecordingClient(
        '{"total":1,"limit":"20","list":[{"vod_id":1,"vod_name":"a"}]}',
      );
      final MacCmsApi api = MacCmsApi(
        VodSource.fromRaw(<String, Object>{
          'name': 't',
          'api': 'https://x.example/api.php/provide/vod/',
        }),
        client: client,
      );

      await api.query(year: '2024', area: '美国', sortBy: 'hits');

      final Map<String, String> q = client.lastUri!.queryParameters;
      expect(q['ac'], 'list');
      expect(q['year'], '2024');
      expect(q.containsKey('yy'), isFalse, reason: 'yy 会被源站忽略，等于没筛');
      expect(q['area'], '美国');
      expect(q['by'], 'hits');
    });

    test('未选中的筛选项不发送对应参数', () async {
      final _RecordingClient client = _RecordingClient(
        '{"total":0,"limit":"20","list":[]}',
      );
      final MacCmsApi api = MacCmsApi(
        VodSource.fromRaw(<String, Object>{
          'name': 't',
          'api': 'https://x.example/api.php/provide/vod/',
        }),
        client: client,
      );

      await api.query();

      final Map<String, String> q = client.lastUri!.queryParameters;
      for (final String k
          in <String>['year', 'area', 'lang', 'by', 'wd', 't']) {
        expect(q.containsKey(k), isFalse, reason: '$k 不应出现在请求里');
      }
    });
  });
}

/// 截获真实请求 URL 的 http 客户端，用来断言线上参数。
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._body);

  final String _body;
  Uri? lastUri;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastUri = request.url;
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[utf8.encode(_body)]),
      200,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
      request: request,
    );
  }
}
