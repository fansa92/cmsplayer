import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/favorite_item.dart';
import 'package:cms_player/data/models/play_record.dart';
import 'package:cms_player/data/sync/sync_payload.dart';
import 'package:cms_player/data/sync/sync_service.dart';
import 'package:cms_player/data/sync/sync_transport.dart';

import 'helpers/fakes.dart';

/// 同步编排的四步流程：读本地 → 拉远端 → 合并 → 推远端。
///
/// 重点守住「任何一步失败都不能把本地写坏」和「两边各改各的不互相覆盖」。
void main() {
  useIsolatedStores();

  final DateTime t0 = DateTime(2026, 3, 1, 12).toUtc();
  final DateTime t1 = DateTime(2026, 3, 10, 12).toUtc();

  PlayRecord rec(String key, {DateTime? at, int pos = 0}) => PlayRecord(
        key: key,
        sourceId: 'src',
        sourceName: '测试站',
        vodId: key,
        vodName: '测试影片',
        positionMs: pos,
        updatedAt: at ?? t0,
      );

  FavoriteItem fav(String key) => FavoriteItem.fromVod(
        sourceId: 'src',
        sourceName: '测试站',
        vodId: int.parse(key),
        vodName: '测试影片',
        createdAt: t0,
      );

  SyncPayload payload({
    List<PlayRecord> history = const <PlayRecord>[],
    List<FavoriteItem> favorites = const <FavoriteItem>[],
    Map<String, Map<String, int>> tombs = const <String, Map<String, int>>{},
    DateTime? at,
  }) =>
      SyncPayload(
        updatedAt: at ?? t0,
        history: history,
        favorites: favorites,
        tombstones: tombs,
      );

  Set<String> historyKeys(SyncPayload p) =>
      p.history.map((PlayRecord e) => e.key).toSet();

  group('本地读写', () {
    test('writeLocal 之后三份数据与墓碑都能原样读回', () async {
      final SyncPayload p = payload(
        history: <PlayRecord>[rec('1', pos: 123)],
        favorites: <FavoriteItem>[fav('7')],
        tombs: <String, Map<String, int>>{
          SyncBox.favorites: <String, int>{'gone': t1.millisecondsSinceEpoch},
        },
      );

      await SyncService.writeLocal(p);
      final SyncPayload back = await SyncService.readLocal();

      expect(back.history.single.key, '1');
      expect(back.history.single.positionMs, 123);
      expect(back.favorites.single.key, 'src|7');
      expect(back.sources, isNotEmpty);
      expect(back.tombstones[SyncBox.favorites]!['gone'],
          t1.millisecondsSinceEpoch);
    });

    test('空盘时仍然给出内置源，保证首页不至于一片空白', () async {
      final SyncPayload back = await SyncService.readLocal();
      expect(back.history, isEmpty);
      expect(back.favorites, isEmpty);
      expect(back.sources, isNotEmpty);
    });
  });

  group('同步流程', () {
    test('远端没数据时是首次上传，不产生任何变更计数', () async {
      await SyncService.writeLocal(
        payload(history: <PlayRecord>[rec('h1')]),
      );
      final FakeTransport transport = FakeTransport();

      final SyncOutcome outcome = await SyncService.run(transport);

      expect(outcome.firstTime, isTrue);
      expect(outcome.diff.isEmpty, isTrue);
      expect(outcome.diff.history, 1);
      expect(transport.downloads, 1);
      expect(transport.uploads, 1);
      expect(transport.uploaded, isNotNull);
      expect(historyKeys(transport.uploaded!), <String>{'h1'});
    });

    test('两边各新增一条时都留下，并报「新增 1」', () async {
      await SyncService.writeLocal(
        payload(history: <PlayRecord>[rec('mine')]),
      );
      final FakeTransport transport = FakeTransport(
        remote: payload(history: <PlayRecord>[rec('theirs')]),
      );

      final SyncOutcome outcome = await SyncService.run(transport);

      expect(outcome.firstTime, isFalse);
      expect(outcome.diff.added, 1);
      expect(outcome.diff.summary, contains('新增'));
      expect(historyKeys(await SyncService.readLocal()),
          <String>{'mine', 'theirs'});
      expect(historyKeys(transport.uploaded!), <String>{'mine', 'theirs'});
    });

    test('同一个 key 取时间戳新的那份，并计入更新', () async {
      await SyncService.writeLocal(
        payload(history: <PlayRecord>[rec('h1', pos: 10, at: t0)]),
      );
      final FakeTransport transport = FakeTransport(
        remote: payload(
          history: <PlayRecord>[rec('h1', pos: 999, at: t1)],
          at: t1,
        ),
      );

      final SyncOutcome outcome = await SyncService.run(transport);

      expect(outcome.diff.updated, 1);
      expect(outcome.diff.added, 0);
      final SyncPayload after = await SyncService.readLocal();
      expect(after.history, hasLength(1));
      expect(after.history.single.positionMs, 999);
    });

    test('推送后对端又合了一次时，回包会被再合一遍', () async {
      await SyncService.writeLocal(
        payload(history: <PlayRecord>[rec('h1')]),
      );
      final FakeTransport transport = FakeTransport(
        remote: payload(history: <PlayRecord>[rec('h2')]),
        back: payload(history: <PlayRecord>[rec('h3')]),
      );

      await SyncService.run(transport);

      expect(
        historyKeys(await SyncService.readLocal()),
        <String>{'h1', 'h2', 'h3'},
      );
    });

    test('远端墓碑比条目新时，删除会同步到本机', () async {
      await SyncService.writeLocal(
        payload(history: <PlayRecord>[rec('h1', at: t0)]),
      );
      final FakeTransport transport = FakeTransport(
        remote: payload(
          tombs: <String, Map<String, int>>{
            SyncBox.history: <String, int>{
              'h1': t1.millisecondsSinceEpoch,
            },
          },
        ),
      );

      final SyncOutcome outcome = await SyncService.run(transport);

      expect(outcome.diff.removed, 1);
      expect((await SyncService.readLocal()).history, isEmpty);
    });
  });

  group('失败不写坏本地', () {
    for (final String stage in <String>['拉取', '推送']) {
      test('$stage 抛异常时本地数据保持原样', () async {
        await SyncService.writeLocal(
          payload(history: <PlayRecord>[rec('keep', pos: 77)]),
        );
        final FakeTransport transport = stage == '拉取'
            ? FakeTransport(downloadError: const SyncException('拉取失败'))
            : FakeTransport(uploadError: const SyncException('推送失败'));

        await expectLater(
          SyncService.run(transport),
          throwsA(isA<SyncException>()),
        );

        final SyncPayload after = await SyncService.readLocal();
        expect(historyKeys(after), <String>{'keep'});
        expect(after.history.single.positionMs, 77);
      });
    }
  });
}

/// 记录调用过程的假通道。
class FakeTransport implements SyncTransport {
  FakeTransport({
    this.remote,
    this.back,
    this.downloadError,
    this.uploadError,
  });

  final SyncPayload? remote;
  final SyncPayload? back;
  final Object? downloadError;
  final Object? uploadError;

  int downloads = 0;
  int uploads = 0;
  SyncPayload? uploaded;
  bool closed = false;

  @override
  String get label => '假通道';

  @override
  Future<SyncPayload?> download() async {
    downloads++;
    if (downloadError != null) throw downloadError!;
    return remote;
  }

  @override
  Future<SyncPayload?> upload(SyncPayload payload) async {
    uploads++;
    if (uploadError != null) throw uploadError!;
    uploaded = payload;
    return back;
  }

  @override
  void close() {
    closed = true;
  }
}
