import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/favorite_item.dart';
import 'package:cms_player/data/models/play_record.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/data/sync/sync_payload.dart';

/// 同步数据包的编解码与墓碑清理。
///
/// 同步面对的是"别人设备写的文件"：版本可能更新、字段类型可能不对、
/// 文件可能被截断。解析必须一律返回可读的失败，不能把异常抛给调用方；
/// 墓碑则要能自我收敛，否则会跟着每次同步无限膨胀。
void main() {
  final DateTime now = DateTime(2026, 3, 10, 12);

  PlayRecord rec(String key) => PlayRecord(
        key: key,
        sourceId: 'src',
        sourceName: '测试站',
        vodId: key,
        vodName: '测试影片',
        positionMs: 42,
        updatedAt: now,
      );

  group('数据包格式', () {
    test('encode 带版本号，时间戳统一成 UTC', () {
      final String text = SyncPayload(
        updatedAt: DateTime(2026, 3, 10, 20, 0),
        history: <PlayRecord>[rec('1')],
      ).encode();
      final Map<String, dynamic> json =
          jsonDecode(text) as Map<String, dynamic>;

      expect(json['v'], kSyncFormatVersion);
      expect(json['updatedAt'], isA<String>());
      expect(json['updatedAt'].toString().endsWith('Z'), isTrue);
      expect(json[SyncBox.history], hasLength(1));
    });

    test('三个集合分别落盘，totalItems 合计', () {
      final SyncPayload p = SyncPayload(
        updatedAt: now,
        history: <PlayRecord>[rec('1'), rec('2')],
        favorites: <FavoriteItem>[
          FavoriteItem.fromVod(
            sourceId: 'src',
            sourceName: '测试站',
            vodId: 1,
            vodName: '测试影片',
            createdAt: now,
          ),
        ],
        sources: <VodSource>[
          VodSource.fromRaw(<String, Object>{
            'name': '测试站',
            'api': 'https://a.com/api.php/provide/vod/',
          }),
        ],
      );
      expect(p.totalItems, 4);
      expect(SyncPayload.empty().totalItems, 0);
      expect(SyncPayload.empty().history, isEmpty);
      expect(SyncPayload.empty().tombstones, isEmpty);
    });

    test('往返后条目、墓碑与时间戳都还在', () {
      final SyncPayload p = SyncPayload(
        updatedAt: now.toUtc(),
        history: <PlayRecord>[rec('1')],
        tombstones: <String, Map<String, int>>{
          SyncBox.favorites: <String, int>{'gone': 12345},
        },
      );
      final SyncPayload? back = SyncPayload.decode(p.encode());

      expect(back, isNotNull);
      expect(back!.history.single.key, '1');
      expect(back.history.single.positionMs, 42);
      expect(back.tombstones[SyncBox.favorites]!['gone'], 12345);
      expect(back.updatedAt, p.updatedAt);
    });

    test('老版本 / 没有版本号的包照常读，更高版本直接拒绝', () {
      const String body =
          '{"updatedAt":"2026-03-10T12:00:00.000Z","history":[]}';
      expect(SyncPayload.decode(body), isNotNull,
          reason: '早期版本没写 v 字段，要当 v0 兼容');
      expect(
        SyncPayload.decode(
          '{"v":0,"updatedAt":"2026-03-10T12:00:00.000Z"}',
        ),
        isNotNull,
      );
      expect(
        SyncPayload.decode(
          '{"v":${kSyncFormatVersion + 1},"updatedAt":"2026-03-10T12:00:00.000Z"}',
        ),
        isNull,
        reason: '猜不懂新字段语义，宁可这次不同步',
      );
    });

    test('字段类型不对时退化为空，而不是抛异常', () {
      final SyncPayload? p = SyncPayload.decode(jsonEncode(<String, dynamic>{
        'v': kSyncFormatVersion,
        'updatedAt': '不是时间',
        'history': '本该是数组',
        'favorites': <dynamic>[
          '不是对象',
          <String, dynamic>{'sourceId': 's', 'vodId': '9'},
        ],
        'sources': null,
        'tombstones': <String, dynamic>{
          SyncBox.history: <String, dynamic>{
            'a': 123,
            'b': '不是数字',
            'c': 1.9,
          },
          SyncBox.favorites: <String, dynamic>{},
          'bad': 5,
        },
      }));

      expect(p, isNotNull);
      expect(p!.history, isEmpty);
      expect(p.favorites, hasLength(1));
      expect(p.favorites.single.key, 's|9');
      expect(p.sources, isEmpty);
      expect(p.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(p.tombstones.keys, <String>{SyncBox.history});
      expect(p.tombstones[SyncBox.history], <String, int>{'a': 123, 'c': 1},
          reason: '非数字跳过，小数取整，空集合整个丢掉');
    });

    test('空串 / 空白 / 非对象 / 坏 JSON 一律返回 null', () {
      expect(SyncPayload.decode(''), isNull);
      expect(SyncPayload.decode('   \n  '), isNull);
      expect(SyncPayload.decode('[1,2,3]'), isNull);
      expect(SyncPayload.decode('"一个字符串"'), isNull);
      expect(SyncPayload.decode('null'), isNull);
      expect(SyncPayload.decode('{"v":'), isNull);
      expect(SyncPayload.decode('这不是 JSON'), isNull);
    });

    test('SyncBox 三个集合名与墓碑键一致', () {
      expect(SyncBox.all, <String>['history', 'favorites', 'sources']);
      expect(SyncBox.all.toSet().length, 3);
    });
  });

  group('墓碑清理', () {
    test('超过保留期的删除记录被丢掉，新的留下', () {
      final int recent =
          now.subtract(const Duration(days: 1)).millisecondsSinceEpoch;
      final int old =
          now.subtract(const Duration(days: 400)).millisecondsSinceEpoch;
      final Map<String, Map<String, int>> raw = <String, Map<String, int>>{
        SyncBox.history: <String, int>{'keep': recent, 'drop': old},
        SyncBox.favorites: <String, int>{'gone': old},
      };

      final Map<String, Map<String, int>> pruned =
          SyncPayload.pruneTombstones(raw, now: now);

      expect(pruned, <String, Map<String, int>>{
        SyncBox.history: <String, int>{'keep': recent},
      });
      // 返回新 map，不改动调用方持有的那份。
      expect(raw[SyncBox.history]!['drop'], old);
      expect(raw[SyncBox.favorites], isNotEmpty);
    });

    test('恰好在保留期边界上的记录仍保留', () {
      final int boundary =
          now.subtract(const Duration(days: 365)).millisecondsSinceEpoch;
      final Map<String, Map<String, int>> pruned = SyncPayload.pruneTombstones(
        <String, Map<String, int>>{
          SyncBox.history: <String, int>{'edge': boundary},
        },
        now: now,
      );

      expect(pruned[SyncBox.history]!['edge'], boundary);
    });

    test('超过条数上限时保留最近的，不按插入顺序截断', () {
      final Map<String, Map<String, int>> raw = <String, Map<String, int>>{
        SyncBox.history: <String, int>{
          'a': now.subtract(const Duration(days: 5)).millisecondsSinceEpoch,
          'c': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
          'b': now.subtract(const Duration(days: 4)).millisecondsSinceEpoch,
        },
      };

      final Map<String, Map<String, int>> pruned =
          SyncPayload.pruneTombstones(raw, now: now, maxEntries: 2);

      expect(pruned[SyncBox.history]!.keys.toSet(), <String>{'b', 'c'});
    });

    test('跨集合一起计数，超限后仍按时间取新舍旧', () {
      final Map<String, Map<String, int>> raw = <String, Map<String, int>>{
        SyncBox.history: <String, int>{
          'h-old': now.subtract(const Duration(days: 9)).millisecondsSinceEpoch,
          'h-new': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        },
        SyncBox.favorites: <String, int>{
          'f-mid': now.subtract(const Duration(days: 5)).millisecondsSinceEpoch,
        },
      };

      final Map<String, Map<String, int>> pruned =
          SyncPayload.pruneTombstones(raw, now: now, maxEntries: 2);

      expect(pruned[SyncBox.history]!.keys, <String>['h-new']);
      expect(pruned[SyncBox.favorites]!.keys, <String>['f-mid']);
    });

    test('空输入与零上限都不抛异常', () {
      expect(
          SyncPayload.pruneTombstones(<String, Map<String, int>>{}), isEmpty);
      expect(
        SyncPayload.pruneTombstones(
          <String, Map<String, int>>{
            SyncBox.history: <String, int>{'a': now.millisecondsSinceEpoch},
          },
          now: now,
          maxEntries: 0,
        ),
        isEmpty,
      );
    });
  });
}
