import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/favorite_item.dart';
import 'package:cms_player/data/models/paged_result.dart';
import 'package:cms_player/data/models/play_line.dart';
import 'package:cms_player/data/models/play_record.dart';
import 'package:cms_player/data/models/play_task.dart';
import 'package:cms_player/data/models/vod_category.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';

/// 数据模型层：磁盘 JSON 往返、旧数据兼容、以及播放器依赖的派生属性。
///
/// 这些字段直接来自各家 macCMS 站点，类型五花八门（数字 ID 有时是字符串、
/// 布尔有时是 0/1），解析层必须"宽容但不猜错"。
void main() {
  group('PlayRecord', () {
    PlayRecord record({
      int positionMs = 0,
      int durationMs = 0,
      bool finished = false,
      String lineName = '',
      String episodeName = '',
      int episodeIndex = 0,
    }) =>
        PlayRecord(
          key: 'src|7',
          sourceId: 'src',
          sourceName: '测试站',
          vodId: '7',
          vodName: '测试影片',
          positionMs: positionMs,
          durationMs: durationMs,
          finished: finished,
          lineName: lineName,
          episodeName: episodeName,
          episodeIndex: episodeIndex,
          updatedAt: DateTime(2026, 3, 10, 12),
        );

    test('进度：已看完优先，其次防除零与越界', () {
      expect(record(positionMs: 400, durationMs: 1000).progress, 0.4);
      expect(record(positionMs: 400).progress, 0);
      expect(
          record(finished: true, positionMs: 1, durationMs: 1000).progress, 1);
      expect(record(positionMs: 5000, durationMs: 1000).progress, 1);
      expect(record(positionMs: -10, durationMs: 1000).progress, 0);
    });

    test('进度文案覆盖未开始 / 已看完 / 看到某时刻', () {
      expect(record().progressLabel, '未开始');
      expect(record(positionMs: 83000).progressLabel, '未开始',
          reason: '没有总时长就不该瞎报"看到 xx"');
      expect(record(positionMs: 83000, durationMs: 100000).progressLabel,
          '看到 01:23');
      expect(record(finished: true).progressLabel, '已看完');
    });

    test('集名兜底与线路前缀', () {
      expect(record().episodeLabel, '第1集');
      expect(record(episodeIndex: 2).episodeLabel, '第3集');
      expect(record(episodeName: '第01集').episodeLabel, '第01集');
      expect(record(lineName: '线路1', episodeName: '第01集').episodeLabel,
          '线路1 · 第01集');
    });

    test('copyWith 只改指定字段，key 与来源信息保持不变', () {
      final PlayRecord old = record(positionMs: 100, durationMs: 1000);
      final PlayRecord next = old.copyWith(positionMs: 900, finished: true);

      expect(next.key, 'src|7');
      expect(next.sourceId, 'src');
      expect(next.vodName, '测试影片');
      expect(next.positionMs, 900);
      expect(next.durationMs, 1000);
      expect(next.finished, isTrue);
      // 原对象不被改动（值对象语义）。
      expect(old.positionMs, 100);
      expect(old.finished, isFalse);
    });

    test('JSON 往返不丢字段', () {
      final PlayRecord source = record(
        positionMs: 1234,
        durationMs: 5678,
        lineName: '线路1',
        episodeName: '第02集',
        episodeIndex: 1,
      );
      final PlayRecord back = PlayRecord.fromJson(
        jsonDecode(jsonEncode(source.toJson())) as Map<String, dynamic>,
      );

      expect(back.key, source.key);
      expect(back.positionMs, 1234);
      expect(back.durationMs, 5678);
      expect(back.episodeName, '第02集');
      expect(back.updatedAt, source.updatedAt);
    });

    test('旧数据缺 key / 字段是字符串时也能读出来', () {
      final PlayRecord back = PlayRecord.fromJson(<String, dynamic>{
        'sourceId': 'src',
        'vodId': '7',
        'vodName': '  老记录  ',
        'positionMs': '2500',
        'durationMs': '10000',
        'finished': 1, // 不是布尔 true，按未看完处理
        'updatedAt': '不是时间',
      });

      expect(back.key, 'src|7', reason: '老版本没有 key 字段，要能推出来');
      expect(back.vodName, '老记录');
      expect(back.positionMs, 2500);
      expect(back.durationMs, 10000);
      expect(back.finished, isFalse);
      expect(back.updatedAt.year, greaterThan(2000),
          reason: '时间解析失败要退化成当前时间，不能是 epoch');
    });
  });

  group('FavoriteItem', () {
    test('fromVod 用 sourceId|vodId 作为 key', () {
      final FavoriteItem item = FavoriteItem.fromVod(
        sourceId: 'abc',
        sourceName: '测试站',
        vodId: 42,
        vodName: '庆余年',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(item.key, 'abc|42');
      expect(item.vodId, '42');
      expect(item.createdAt, DateTime(2026, 1, 1));
    });

    test('JSON 往返与缺 key 兜底', () {
      final FavoriteItem item = FavoriteItem.fromVod(
        sourceId: 'abc',
        sourceName: '测试站',
        vodId: 42,
        vodName: '庆余年',
        remarks: 'HD',
        createdAt: DateTime(2026, 1, 1),
      );
      final FavoriteItem back = FavoriteItem.fromJson(item.toJson());
      expect(back.key, item.key);
      expect(back.remarks, 'HD');
      expect(back.createdAt, item.createdAt);

      final FavoriteItem legacy = FavoriteItem.fromJson(<String, dynamic>{
        'sourceId': 'abc',
        'vodId': '42',
        'createdAt': '',
      });
      expect(legacy.key, 'abc|42');
      expect(legacy.createdAt.year, greaterThan(2000));
    });
  });

  group('PlayTask', () {
    test('正常情况下的派生属性', () {
      final PlayTask task = _task();

      expect(task.isValid, isTrue);
      expect(task.line!.name, '线路A');
      expect(task.episode!.name, '第01集');
      expect(task.title, '测试影片');
      expect(task.subtitle, '线路A · 第01集');
      expect(task.recordKey, '${task.source.id}|7');
      expect(task.hasNext, isTrue);
      expect(task.hasPrev, isFalse);
    });

    test('最后一集不能下一集，非第一集可以上一集', () {
      final PlayTask task = _task(episodeIndex: 1);
      expect(task.hasNext, isFalse);
      expect(task.hasPrev, isTrue);
      expect(task.subtitle, '线路A · 第02集');
    });

    test('线路或集下标越界时不崩，只把状态标成无效', () {
      for (final PlayTask task in <PlayTask>[
        _task(lineIndex: -1),
        _task(lineIndex: 9),
        _task(episodeIndex: -1),
        _task(episodeIndex: 9),
      ]) {
        expect(task.isValid, isFalse);
        expect(task.subtitle, '');
        expect(task.hasNext, isFalse);
      }
    });

    test('copyWith 换源后 recordKey 跟着变', () {
      final PlayTask task = _task();
      final VodSource other = VodSource.fromRaw(<String, Object>{
        'name': '备用站',
        'api': 'https://b.com/api.php/provide/vod/',
      });
      final PlayTask next = task.copyWith(source: other, episodeIndex: 1);

      expect(next.item, same(task.item));
      expect(next.lineIndex, 0);
      expect(next.episodeIndex, 1);
      expect(next.recordKey, '${other.id}|7');
      expect(next.recordKey, isNot(task.recordKey));
    });

    test('toString 带上片名与定位，便于日志排查', () {
      expect(_task().toString(), contains('测试影片'));
      expect(_task(episodeIndex: 1).toString(), contains('0/1'));
    });
  });

  group('PagedResult', () {
    test('hasNext 与空页判断', () {
      expect(
        const PagedResult<int>(items: <int>[1], page: 1, pageCount: 3).hasNext,
        isTrue,
      );
      expect(
        const PagedResult<int>(items: <int>[1], page: 3, pageCount: 3).hasNext,
        isFalse,
      );
      expect(VodPage.empty().isEmpty, isTrue);
      expect(VodPage.empty().isNotEmpty, isFalse);
    });

    test('merge 追加条目并采用下一页的分页信息', () {
      const PagedResult<String> first = PagedResult<String>(
        items: <String>['a'],
        page: 1,
        pageCount: 3,
        total: 3,
      );
      const PagedResult<String> next = PagedResult<String>(
        items: <String>['b'],
        page: 2,
        pageCount: 4,
        total: 40,
      );

      final PagedResult<String> merged = first.merge(next);

      expect(merged.items, <String>['a', 'b']);
      expect(merged.page, 2);
      expect(merged.pageCount, 4);
      expect(merged.total, 40);
      // 不修改入参。
      expect(first.items, <String>['a']);
    });
  });

  group('播放地址解析的脏数据', () {
    test('一段里可以有多个备用地址', () {
      final List<PlayLine> lines = VodItem.parsePlayLines(
        'm3u8',
        r'第01集$https://a.com/1.m3u8$https://b.com/1.m3u8$https://c.com/1.m3u8',
      );
      expect(lines.single.episodes.single.url, 'https://a.com/1.m3u8');
      expect(lines.single.episodes.single.mirrors,
          <String>['https://b.com/1.m3u8', 'https://c.com/1.m3u8']);
    });

    test('缺分隔符、缺地址、空线路都跳过而不是产出坏条目', () {
      expect(VodItem.parsePlayLines('m3u8', '没有分隔符'), isEmpty);
      expect(VodItem.parsePlayLines('m3u8', r'$https://a.com/1.m3u8'), isEmpty);
      expect(VodItem.parsePlayLines('m3u8', r'第01集$'), isEmpty);
      expect(VodItem.parsePlayLines('m3u8', r'第01集$   '), isEmpty);

      final List<PlayLine> lines = VodItem.parsePlayLines(
        'm3u8\$\$\$dbm3u8',
        r'第01集$https://a.com/1.m3u8$$$#',
      );
      expect(lines, hasLength(1), reason: '空线路不应混进结果');
    });

    test('集名与地址两侧空白都被清掉', () {
      final List<PlayLine> lines = VodItem.parsePlayLines(
        'm3u8',
        ' 第01集 \$ https://a.com/1.m3u8 \$ https://b.com/1.m3u8 '
            '# 第02集 \$ https://a.com/2.m3u8 ',
      );
      expect(lines.single.episodes[0].name, '第01集');
      expect(lines.single.episodes[0].url, 'https://a.com/1.m3u8');
      expect(
          lines.single.episodes[0].mirrors, <String>['https://b.com/1.m3u8']);
      expect(lines.single.episodes[1].name, '第02集');
    });

    test('线路名数量不足时按序号补齐', () {
      final List<PlayLine> lines = VodItem.parsePlayLines(
        'm3u8',
        r'第01集$https://a.com/1.m3u8$$$第01集$https://b.com/1.m3u8',
      );
      expect(
          lines.map((PlayLine e) => e.name).toList(), <String>['m3u8', '线路2']);
    });

    test('传入已解析的 playLines 时不再重复解析', () {
      final List<PlayLine> cached = <PlayLine>[
        const PlayLine(
          name: '缓存线路',
          episodes: <PlayEpisode>[
            PlayEpisode(name: '正片', url: 'https://cache/1.m3u8'),
          ],
        ),
      ];
      final VodItem item = VodItem(
        id: 1,
        name: 'x',
        playUrl: r'第01集$https://raw/1.m3u8',
        playLines: cached,
      );
      expect(item.playLines, same(cached));
      expect(item.playLines.single.episodes.single.url, 'https://cache/1.m3u8');
    });
  });

  group('VodItem.fromJson', () {
    test('清洗 HTML 与实体，并解析出线路', () {
      final VodItem item = VodItem.fromJson(<String, dynamic>{
        'vod_id': '12',
        'vod_name': 'A&amp;B',
        'vod_remarks': 'HD&nbsp;版',
        'vod_content': '<p>简介<br/>第二行</p>',
        'vod_year': '2024',
        'vod_play_from': 'm3u8',
        'vod_play_url': r'第01集$https://a.com/1.m3u8',
      });

      expect(item.id, 12);
      expect(item.name, 'A&B');
      expect(item.remarks, 'HD 版');
      expect(item.content, '简介\n第二行');
      expect(item.year, '2024');
      expect(item.hasPlayInfo, isTrue);
      expect(item.episodeCount, 1);
    });

    test('优先使用缓存里的 playLines', () {
      final VodItem item = VodItem.fromJson(<String, dynamic>{
        'vod_id': 1,
        'vod_name': 'x',
        'vod_play_url': r'第01集$https://raw/1.m3u8',
        'playLines': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': '缓存线路',
            'episodes': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': '正片',
                'url': 'https://cache/1.m3u8',
                'mirrors': <String>['', 'https://cache/backup.m3u8'],
              },
            ],
          },
        ],
      });

      expect(item.playLines.single.name, '缓存线路');
      expect(item.playLines.single.episodes.single.mirrors,
          <String>['https://cache/backup.m3u8'],
          reason: '空字符串备用地址要被过滤掉');
    });

    test('解析展示类元信息并支持序列化往返', () {
      final VodItem item = VodItem.fromJson(<String, dynamic>{
        'vod_id': 7,
        'vod_name': '元信息',
        'vod_score': '8.7',
        'vod_hits': '1.2万',
        'vod_isend': '1',
        'vod_serial': '更新至第 12 集',
        'vod_total': 24,
        'vod_duration': '45分钟',
        'vod_pubdate': '2024-05-01',
        'vod_sub': '别名甲',
        'vod_letter': 'y',
        'vod_up': '33',
        'vod_down': 2,
      });

      expect(item.score, closeTo(8.7, 1e-9));
      expect(item.scoreLabel, '8.7');
      expect(item.hits, 12000, reason: '「万」要换算成具体数字');
      expect(item.hitsLabel, '1.2万');
      expect(item.isEnd, isTrue);
      expect(item.endLabel, '已完结');
      expect(item.serial, '更新至第 12 集');
      expect(item.totalEpisodes, 24);
      expect(item.duration, '45分钟');
      expect(item.pubDate, '2024-05-01');
      expect(item.subName, '别名甲');
      expect(item.letter, 'Y');
      expect(item.upCount, 33);
      expect(item.downCount, 2);

      final VodItem back = VodItem.fromJson(item.toJson());
      expect(back.score, item.score);
      expect(back.hits, item.hits);
      expect(back.isEnd, isTrue);
      expect(back.serial, item.serial);
      expect(back.totalEpisodes, item.totalEpisodes);
      expect(back.letter, 'Y');
    });

    test('没有备注时角标退到更新进度 / 完结状态', () {
      expect(VodItem(id: 1, name: 'a').badgeText, '');
      expect(
        VodItem(id: 1, name: 'a', serial: '更新至 3 集').badgeText,
        '更新至 3 集',
      );
      expect(VodItem(id: 1, name: 'a', isEnd: true).badgeText, '已完结');
      expect(
        VodItem(id: 1, name: 'a', isEnd: false, serial: 'x').badgeText,
        'x',
        reason: '进度比"连载中"更具体，优先展示',
      );
    });

    test('认不出来的 isend 当作「源站没说」', () {
      final VodItem weird =
          VodItem.fromJson(<String, dynamic>{'vod_id': 1, 'vod_isend': '未知'});
      expect(weird.isEnd, isNull);
      expect(weird.endLabel, isNull);

      final VodItem zero =
          VodItem.fromJson(<String, dynamic>{'vod_id': 1, 'vod_isend': 0});
      expect(zero.isEnd, isFalse);
      expect(zero.endLabel, '连载中');
    });

    test('equality 只看 id，toJson 能还原全部字段', () {
      final VodItem a = VodItem(id: 1, name: '甲');
      final VodItem b = VodItem(id: 1, name: '乙');
      final VodItem c = VodItem(id: 2, name: '甲');

      expect(a, b);
      expect(a, isNot(c));
      expect(a.hashCode, b.hashCode);

      final VodItem back = VodItem.fromJson(a.toJson());
      expect(back.id, a.id);
      expect(back.name, a.name);
      expect(back.isEmpty, isFalse);
      expect(VodItem(id: 0, name: '').isEmpty, isTrue);
    });
  });

  group('VodSource', () {
    test('normalizeApi 去尾部问号、按需补斜杠', () {
      expect(
        VodSource.normalizeApi(' https://a.com/api.php/provide/vod?? '),
        'https://a.com/api.php/provide/vod/',
      );
      expect(
        VodSource.normalizeApi('https://a.com/api.php/provide/vod#'),
        'https://a.com/api.php/provide/vod/',
      );
      // 自带 query 的接口不能再补斜杠，否则参数会落到路径里。
      expect(
        VodSource.normalizeApi('https://a.com/api.php?ac=list'),
        'https://a.com/api.php?ac=list',
      );
      expect(VodSource.normalizeApi(''), '');
      expect(VodSource.normalizeApi('  '), '');
    });

    test('isUsable 挡掉 cms:// 等私有协议与空地址', () {
      expect(
          _source(api: 'https://a.com/api.php/provide/vod/').isUsable, isTrue);
      expect(_source(api: 'cms://ddys').isUsable, isFalse);
      expect(_source(api: '').isUsable, isFalse);
      expect(_source(api: 'ftp://a.com/x').isUsable, isFalse);
      expect(VodSource.hostOf('cms://ddys'), 'ddys');
      expect(VodSource.hostOf(''), '未命名资源站');
    });

    test('headers 支持自定义 UA / Referer，无源站时不发空 Referer', () {
      final VodSource custom = VodSource.fromRaw(<String, Object>{
        'name': 'x',
        'api': 'https://a.com/api.php/provide/vod/',
        'userAgent': 'UA-X',
        'referer': 'https://b.com/',
      });
      expect(custom.headers['User-Agent'], 'UA-X');
      expect(custom.headers['Referer'], 'https://b.com/');
      expect(custom.headers['Accept'], '*/*');

      final VodSource plain = VodSource.fromRaw(<String, Object>{
        'name': 'x',
        'api': 'https://a.com/api.php/provide/vod/',
      });
      expect(plain.headers['Referer'], 'https://a.com/');
      expect(plain.headers['User-Agent'], isNotEmpty);

      final VodSource broken = VodSource.fromRaw(<String, Object>{
        'name': 'x',
        'api': '不是网址',
      });
      expect(broken.origin, '');
      expect(broken.headers.containsKey('Referer'), isFalse);
    });

    test('fromRaw 兼容别名键与 0/1/字符串形式的 enabled', () {
      final VodSource s = VodSource.fromRaw(<String, Object>{
        'name': 'x',
        'api': 'https://a.com/api.php/provide/vod/',
        'note': '备注',
        'jx': 'https://p.com/?url=',
        'ua': 'UA-Y',
        'encoding': 'gbk',
        'enabled': '1',
        'sort': 3,
      });

      expect(s.note, '备注');
      expect(s.parseApi, 'https://p.com/?url=');
      expect(s.userAgent, 'UA-Y');
      expect(s.charset, 'gbk');
      expect(s.enabled, isTrue);
      expect(s.sort, 3);

      expect(
          VodSource.fromRaw(<String, Object>{'enabled': 0}).enabled, isFalse);
      expect(VodSource.fromRaw(<String, Object>{'enabled': false}).enabled,
          isFalse);
      expect(VodSource.fromRaw(<String, Object>{'enabled': 'true'}).enabled,
          isFalse,
          reason: '只有 true / 1 / "1" 算启用，避免把任意字符串当成真');
      expect(VodSource.fromRaw(<String, Object>{}).enabled, isTrue);
    });

    test('没填名字时用域名兜底，copyWith 保留 id 与创建时间', () {
      final VodSource s = VodSource.fromRaw(<String, Object>{
        'api': 'https://cdn.example.com/api.php/provide/vod/',
        'createdAt': '2024-01-02T03:04:05',
      });
      expect(s.name, 'cdn.example.com');
      expect(s.createdAt, DateTime(2024, 1, 2, 3, 4, 5));

      final VodSource next = s.copyWith(name: '改名', enabled: false, sort: 9);
      expect(next.id, s.id);
      expect(next.createdAt, s.createdAt);
      expect(next.name, '改名');
      expect(next.enabled, isFalse);
      expect(next.sort, 9);
    });

    test('equality 按 id，同一 name|api 重复导入视为同一个源', () {
      final VodSource a = _source();
      final VodSource b = _source();
      final VodSource c = _source(name: '另一个站');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('VodCategory', () {
    test('JSON 往返与相等性', () {
      const VodCategory c = VodCategory(id: 6, name: '动作片', parentId: 1);
      expect(VodCategory.fromJson(c.toJson()), c);
      expect(c.toString(), contains('动作片'));
    });

    test('分层结构异常到筛完为空时退回原列表', () {
      // 互相指为父分类，筛完一个叶子都不剩；此时宁可全显示，也不能空白。
      final List<VodCategory> weird = <VodCategory>[
        const VodCategory(id: 1, name: 'a', parentId: 2),
        const VodCategory(id: 2, name: 'b', parentId: 1),
      ];
      expect(VodCategory.leafOnly(weird), same(weird));
    });
  });
}

/// 造一个两条线路、第一条两集的播放任务。
PlayTask _task({int lineIndex = 0, int episodeIndex = 0}) {
  final VodSource source = _source();
  final VodItem item = VodItem(
    id: 7,
    name: '测试影片',
    playFrom: r'线路A$$$线路B',
    playUrl: r'第01集$https://a.com/1.m3u8#第02集$https://a.com/2.m3u8'
        r'$$$第01集$https://b.com/1.m3u8',
  );
  return PlayTask(
    source: source,
    item: item,
    lineIndex: lineIndex,
    episodeIndex: episodeIndex,
  );
}

VodSource _source({
  String name = '测试站',
  String api = 'https://a.com/api.php/provide/vod/',
}) =>
    VodSource.fromRaw(<String, Object>{
      'name': name,
      'api': api,
    });
