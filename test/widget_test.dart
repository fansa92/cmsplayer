import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/utils/text_utils.dart';
import 'package:cms_player/core/utils/formatter.dart';
import 'package:cms_player/data/api/maccms_api.dart';
import 'package:cms_player/data/models/play_line.dart';
import 'package:cms_player/data/models/paged_result.dart';
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
}
