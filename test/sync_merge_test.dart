import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/play_record.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/data/sync/sync_merge.dart';
import 'package:cms_player/data/sync/sync_payload.dart';

/// 合并规则的行为测试。
///
/// 覆盖的是同步最容易出错的三个点：
///  1. 两边各改各的条目，不能互相覆盖（整文件覆盖式同步会丢一边）；
///  2. 删除要能传得过去，且不会被对方的旧条目复活；
///  3. 结果与参数顺序无关。
void main() {
  final DateTime now = DateTime.now();

  PlayRecord rec(String key, DateTime at, {int pos = 0}) => PlayRecord(
        key: key,
        sourceId: key.split('|').first,
        sourceName: '源',
        vodId: key.split('|').last,
        vodName: '影片',
        positionMs: pos,
        updatedAt: at,
      );

  VodSource src(String id, {int sort = 0, DateTime? at}) => VodSource(
        id: id,
        name: id,
        api: 'https://x.example/api.php/provide/vod/',
        sort: sort,
        createdAt: at ?? now,
      );

  SyncPayload payload({
    List<PlayRecord> history = const <PlayRecord>[],
    List<VodSource> sources = const <VodSource>[],
    Map<String, Map<String, int>> tombs = const <String, Map<String, int>>{},
  }) =>
      SyncPayload(
        updatedAt: now,
        history: history,
        sources: sources,
        tombstones: tombs,
      );

  Set<String> keys(List<PlayRecord> l) => l.map((PlayRecord e) => e.key).toSet();

  group('合并规则', () {
    test('两边各自新增的条目都要留下，不能互相覆盖', () {
      final SyncPayload a = payload(
        history: <PlayRecord>[rec('s|1', now, pos: 100)],
      );
      final SyncPayload b = payload(
        history: <PlayRecord>[rec('s|2', now, pos: 200)],
      );

      final SyncPayload merged = SyncMerger.merge(a, b);

      expect(keys(merged.history), <String>{'s|1', 's|2'});
      expect(merged.history.length, 2);
    });

    test('同一个 key 两边都有时，取时间戳新的那份', () {
      final DateTime older = now.subtract(const Duration(hours: 1));
      final SyncPayload a =
          payload(history: <PlayRecord>[rec('s|1', older, pos: 10)]);
      final SyncPayload b =
          payload(history: <PlayRecord>[rec('s|1', now, pos: 999)]);

      final SyncPayload merged = SyncMerger.merge(a, b);

      expect(merged.history, hasLength(1));
      expect(merged.history.first.positionMs, 999,
          reason: '对方那台更新过，应当采用对方的进度');
    });

    test('结果与参数顺序无关（合并对称）', () {
      final SyncPayload a = payload(
        history: <PlayRecord>[rec('s|1', now), rec('s|2', now)],
        sources: <VodSource>[src('A', sort: 1)],
      );
      final SyncPayload b = payload(
        history: <PlayRecord>[rec('s|3', now)],
        sources: <VodSource>[src('B', sort: 0)],
      );

      final SyncPayload ab = SyncMerger.merge(a, b);
      final SyncPayload ba = SyncMerger.merge(b, a);

      expect(keys(ab.history), keys(ba.history));
      expect(ab.sources.map((VodSource e) => e.id).toList(),
          ba.sources.map((VodSource e) => e.id).toList());
    });
  });

  group('删除墓碑', () {
    test('墓碑比条目新时，条目被删掉', () {
      final DateTime t1 = now.subtract(const Duration(hours: 2));
      final SyncPayload a =
          payload(history: <PlayRecord>[rec('s|1', t1)]); // 旧条目
      // 对方两小时前的条目，一小时前把它删了
      final SyncPayload b = payload(
        history: <PlayRecord>[rec('s|1', t1)],
        tombs: <String, Map<String, int>>{
          SyncBox.history: <String, int>{
            's|1': now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          },
        },
      );

      final SyncPayload merged = SyncMerger.merge(a, b);

      expect(merged.history, isEmpty,
          reason: '删除时刻晚于条目时刻，应当保持删除');
    });

    test('条目比墓碑新时，条目复活（删了之后又重新看过）', () {
      final DateTime deleted = now.subtract(const Duration(hours: 2));
      final SyncPayload a = payload(
        history: <PlayRecord>[rec('s|1', now)], // 两小时删除之后又播放过
      );
      final SyncPayload b = payload(
        tombs: <String, Map<String, int>>{
          SyncBox.history: <String, int>{
            's|1': deleted.millisecondsSinceEpoch,
          },
        },
      );

      final SyncPayload merged = SyncMerger.merge(a, b);

      expect(merged.history, hasLength(1),
          reason: '墓碑比条目旧，说明删除早已被后续播放覆盖，不该再删');
    });

    test('墓碑随合并结果一起带过去，下一轮仍然生效', () {
      final SyncPayload a = payload();
      final SyncPayload b = payload(
        tombs: <String, Map<String, int>>{
          SyncBox.history: <String, int>{'s|1': now.millisecondsSinceEpoch},
        },
      );

      final SyncPayload merged = SyncMerger.merge(a, b);

      expect(merged.tombstones[SyncBox.history], contains('s|1'));
    });
  });

  group('源列表排序', () {
    test('按 sort 排，不按时间戳重排', () {
      // 三个源的时间戳依次递减，但 sort 依次递增 —— 结果应以 sort 为准。
      final SyncPayload a = payload(sources: <VodSource>[
        src('A', sort: 0, at: now),
        src('B', sort: 1, at: now.subtract(const Duration(hours: 1))),
      ]);
      final SyncPayload b = payload(sources: <VodSource>[
        src('C', sort: 2, at: now.subtract(const Duration(hours: 2))),
      ]);

      final SyncPayload merged = SyncMerger.merge(a, b);

      expect(merged.sources.map((VodSource e) => e.id).toList(),
          <String>['A', 'B', 'C']);
    });

    test('sort 相同时按名字兜底，保证顺序稳定', () {
      final SyncPayload a =
          payload(sources: <VodSource>[src('B', sort: 0), src('A', sort: 0)]);
      final SyncPayload b = payload(sources: <VodSource>[src('C', sort: 0)]);

      final SyncPayload merged = SyncMerger.merge(a, b);

      expect(merged.sources.map((VodSource e) => e.id).toList(),
          <String>['A', 'B', 'C']);
    });
  });

  group('合并战报', () {
    test('新增、更新、移除分别计数', () {
      final DateTime older = now.subtract(const Duration(hours: 1));
      final SyncPayload before = payload(
        history: <PlayRecord>[
          rec('keep', now),
          rec('newer', older),
          rec('gone', now),
        ],
      );
      final SyncPayload after = payload(
        history: <PlayRecord>[
          rec('keep', now),
          rec('newer', now), // 时间戳变了 -> 更新
          rec('added', now), // 本地没有 -> 新增
          // 'gone' 不在 -> 移除
        ],
      );

      final SyncDiff d = SyncMerger.diff(before, after);

      expect(d.added, 1);
      expect(d.updated, 1);
      expect(d.removed, 1);
      expect(d.isEmpty, isFalse);
      expect(d.summary, contains('新增'));
      expect(d.summary, contains('更新'));
      expect(d.summary, contains('移除'));
    });

    test('完全没变时 isEmpty 为真，摘要提示一致', () {
      final SyncPayload p =
          payload(history: <PlayRecord>[rec('keep', now)]);

      final SyncDiff d = SyncMerger.diff(p, p);

      expect(d.isEmpty, isTrue);
      expect(d.summary, '数据一致，无需变更');
      expect(d.history, 1);
    });
  });

  group('版本兼容', () {
    test('数据包往返后内容不变', () {
      final SyncPayload p = payload(
        history: <PlayRecord>[rec('s|1', now, pos: 42)],
        sources: <VodSource>[src('A', sort: 3)],
      );

      final SyncPayload? back = SyncPayload.decode(p.encode());

      expect(back, isNotNull);
      expect(back!.history.single.key, 's|1');
      expect(back.history.single.positionMs, 42);
      // id 是由 name|api 哈希推导出来的，不落盘，往返后会重新算一遍，
      // 所以这里断言 name 而不是 id。
      expect(back.sources.single.name, 'A');
      expect(back.sources.single.sort, 3);
    });

    test('读到更高版本直接拒绝，不硬合', () {
      final SyncPayload? decoded = SyncPayload.decode(
        '{"v": 999, "updatedAt": "2020-01-01T00:00:00Z"}',
      );

      expect(decoded, isNull);
    });

    test('乱码返回 null 而不是抛异常', () {
      expect(SyncPayload.decode('这不是 JSON'), isNull);
      expect(SyncPayload.decode(''), isNull);
      expect(SyncPayload.decode('[1,2,3]'), isNull);
    });
  });
}
