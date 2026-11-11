import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/core/utils/collections.dart';
import 'package:cms_player/data/models/play_record.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/data/sync/sync_payload.dart';
import 'package:cms_player/data/sync/sync_tombstones.dart';
import 'package:cms_player/state/favorites_store.dart';
import 'package:cms_player/state/history_store.dart';
import 'package:cms_player/state/source_store.dart';

import 'helpers/fakes.dart';

/// 历史 / 收藏 / 资源站三个 Store：内存状态、落盘回读、删除墓碑。
///
/// 删除必须同时写墓碑，否则对方设备下次同步会把删掉的东西推回来 ——
/// 这是同步里最容易静默出错的一环，逐条钉住。
void main() {
  useIsolatedStores();

  final DateTime t0 = DateTime(2026, 3, 1, 9);
  final DateTime t1 = DateTime(2026, 3, 10, 9);

  PlayRecord rec(
    String key, {
    DateTime? at,
    String sourceId = 'src',
    int pos = 0,
  }) =>
      PlayRecord(
        key: key,
        sourceId: sourceId,
        sourceName: '测试站',
        vodId: key,
        vodName: '测试影片',
        positionMs: pos,
        durationMs: 1000,
        updatedAt: at ?? t0,
      );

  VodItem item(int id, {String name = '测试影片'}) =>
      VodItem(id: id, name: name, pic: 'https://a.com/p.jpg', remarks: 'HD');

  Future<SettingsStore> settings() async {
    final SettingsStore s = SettingsStore();
    await s.init();
    return s;
  }

  Future<Map<String, Map<String, int>>> tombs() =>
      SyncTombstones.instance.load();

  group('HistoryStore', () {
    test('upsert 按 key 去重，列表始终按更新时间倒序', () async {
      final HistoryStore store = HistoryStore();
      await store.upsert(rec('a', at: t0));
      await store.upsert(rec('b', at: t1));
      await store
          .upsert(rec('a', at: t1.add(const Duration(hours: 1)), pos: 500));

      expect(store.records, hasLength(2));
      expect(store.records.first.key, 'a');
      expect(store.records.first.positionMs, 500);
      expect(store.records.last.key, 'b');
    });

    test('查询结果与最近 N 条', () async {
      final HistoryStore store = HistoryStore();
      await store.upsert(rec('a', at: t0, sourceId: 's1'));
      await store.upsert(rec('b', at: t1, sourceId: 's2'));
      await store.upsert(rec('c', at: t1.add(const Duration(hours: 1))));

      expect(store.byKey('a')!.key, 'a');
      expect(store.byKey('不存在'), isNull);
      expect(store.byIds('s1', 0), isNull); // key 是字符串，不会按数字匹配
      expect(store.forSource('s2').single.key, 'b');
      expect(store.recent(limit: 2).map((PlayRecord e) => e.key).toList(),
          <String>['c', 'b']);
      expect(store.isEmpty, isFalse);
    });

    test('load 从磁盘恢复，loading 状态正确收尾', () async {
      final HistoryStore first = HistoryStore();
      await first.upsert(rec('a', at: t0, pos: 123));

      final HistoryStore second = HistoryStore();
      expect(second.loading, isTrue);
      await second.load();
      expect(second.loading, isFalse);
      expect(second.records.single.positionMs, 123);
    });

    test('remove 写墓碑，removeMany 只为真正删掉的条目写', () async {
      final HistoryStore store = HistoryStore();
      await store.upsert(rec('a'));
      await store.upsert(rec('b'));
      await store.upsert(rec('c'));

      await store.remove('a');
      expect((await tombs())[SyncBox.history]!.containsKey('a'), isTrue);

      await store.removeMany(<String>['b', '根本不存在']);
      final Map<String, int>? history = (await tombs())[SyncBox.history];
      expect(history!.containsKey('b'), isTrue);
      expect(history.containsKey('根本不存在'), isFalse);
      expect(store.records.single.key, 'c');
    });

    test('clear 把当时存在的每一条都记成墓碑', () async {
      final HistoryStore store = HistoryStore();
      await store.upsert(rec('a'));
      await store.upsert(rec('b'));

      await store.clear();

      expect(store.isEmpty, isTrue);
      final Map<String, int>? history = (await tombs())[SyncBox.history];
      expect(history!.keys.toSet(), <String>{'a', 'b'});
    });

    test('写操作会通知监听者', () async {
      final HistoryStore store = HistoryStore();
      int notifications = 0;
      store.addListener(() {
        notifications++;
      });
      await store.upsert(rec('a'));
      expect(notifications, greaterThan(0));
      store.dispose();
    });
  });

  group('FavoritesStore', () {
    test('toggle 收藏 / 取消收藏，且不产生重复项', () async {
      final FavoritesStore store = FavoritesStore();
      final VodSource source = sourceOf('测试站');

      expect(await store.toggle(source: source, item: item(7)), isTrue);
      expect(store.items, hasLength(1));
      expect(store.contains(source.id, 7), isTrue);
      expect(store.find(source.id, 7)!.vodName, '测试影片');
      expect(store.find(source.id, 7)!.remarks, 'HD');
      expect(store.items.single.key, '${source.id}|7');

      expect(await store.toggle(source: source, item: item(7)), isFalse);
      expect(store.isEmpty, isTrue);
    });

    test('取消收藏与 remove / removeMany / clear 都写墓碑', () async {
      final FavoritesStore store = FavoritesStore();
      final VodSource source = sourceOf('测试站');
      for (final int id in <int>[1, 2, 3]) {
        await store.toggle(source: source, item: item(id));
      }

      await store.toggle(source: source, item: item(1));
      expect((await tombs())[SyncBox.favorites]!.containsKey('${source.id}|1'),
          isTrue);

      await store.remove('${source.id}|2');
      expect((await tombs())[SyncBox.favorites]!.containsKey('${source.id}|2'),
          isTrue);

      await store.removeMany(<String>['${source.id}|3', '不存在']);
      final Map<String, int>? favs = (await tombs())[SyncBox.favorites];
      expect(favs!.containsKey('${source.id}|3'), isTrue);
      expect(favs.containsKey('不存在'), isFalse);

      await store.toggle(source: source, item: item(4));
      await store.clear();
      expect(store.isEmpty, isTrue);
      expect((await tombs())[SyncBox.favorites]!.containsKey('${source.id}|4'),
          isTrue);
    });

    test('keyOf / forSource 与落盘回读', () async {
      final FavoritesStore store = FavoritesStore();
      final VodSource source = sourceOf('测试站');
      expect(store.keyOf(source.id, 9), '${source.id}|9');
      await store.toggle(source: source, item: item(9));
      expect(store.forSource(source.id), hasLength(1));
      expect(store.forSource('别的源'), isEmpty);

      final FavoritesStore reloaded = FavoritesStore();
      await reloaded.load();
      expect(reloaded.items.single.key, '${source.id}|9');
      expect(reloaded.loading, isFalse);
    });
  });

  group('SourceStore', () {
    test('空盘时给内置源，active 自动落到第一个可用源', () async {
      final SourceStore store = SourceStore(await settings());
      await store.load();

      expect(store.sources, isNotEmpty);
      expect(store.loading, isFalse);
      expect(store.active, isNotNull);
      expect(store.activeId, store.active!.id);
      expect(store.lastError, isNull);
    });

    test('add 同名同接口视为同一个源，只更新字段', () async {
      final SourceStore store = SourceStore(await settings());
      await store.load();
      final int before = store.sources.length;

      final VodSource raw = sourceOf('新站');
      await store.add(raw);
      expect(store.sources, hasLength(before + 1));

      await store.add(
        VodSource.fromRaw(<String, Object>{
          'name': '新站',
          'api': 'https://a.com/api.php/provide/vod/',
          'note': '改过的备注',
        }),
      );
      expect(store.sources, hasLength(before + 1));
      expect(
        store.sources.firstWhere((VodSource s) => s.id == raw.id).note,
        '改过的备注',
      );
    });

    test('addMany 返回新增条数，重复导入不再增加', () async {
      final SourceStore store = SourceStore(await settings());
      await store.load();
      final List<VodSource> incoming = <VodSource>[
        sourceOf('甲'),
        sourceOf('乙'),
      ];

      expect(await store.addMany(incoming), 2);
      expect(await store.addMany(incoming), 0);
      expect(store.sources.length, greaterThanOrEqualTo(2));
    });

    test('move 重排后 sort 连续', () async {
      final SourceStore store = SourceStore(await settings());
      await store.load();
      await store.addMany(<VodSource>[sourceOf('甲'), sourceOf('乙')]);
      final List<String> before =
          store.sources.map((VodSource s) => s.name).toList();

      await store.move(0, store.sources.length - 1);

      expect(
          store.sources.map((VodSource s) => s.name).toList(), isNot(before));
      expect(
        store.sources.map((VodSource s) => s.sort).toList(),
        List<int>.generate(store.sources.length, (int i) => i),
      );
    });

    test('停用当前源后 active 自动回退，setActive 会写进设置', () async {
      final SettingsStore prefs = await settings();
      final SourceStore store = SourceStore(prefs);
      await store.load();
      await store.addMany(<VodSource>[sourceOf('甲'), sourceOf('乙')]);
      final VodSource first = store.active!;
      final VodSource second = store.sources.firstWhere(
        (VodSource s) => s.id != first.id && s.enabled,
      );
      // setActive 对"已经是当前源"会短路，所以切到另一个源才会落设置。
      await store.setActive(second);
      expect(prefs.activeSourceId, second.id);
      expect(store.activeId, second.id);

      await store.toggleEnabled(second.id);
      expect(store.activeId, isNot(second.id), reason: '停用的源不能再当激活源');
      expect(store.active, isNotNull);
    });

    test('remove 与 clearAll 写墓碑，resetToBuiltin 可恢复', () async {
      final SourceStore store = SourceStore(await settings());
      await store.load();
      final VodSource added = sourceOf('要删的站');
      await store.add(added);

      await store.remove(added.id);
      expect((await tombs())[SyncBox.sources]!.containsKey(added.id), isTrue);

      await store.addMany(<VodSource>[sourceOf('甲'), sourceOf('乙')]);
      await store.clearAll();
      expect(store.sources, isEmpty);
      expect(store.activeId, '');
      final Map<String, int>? tombstones = (await tombs())[SyncBox.sources];
      expect(tombstones!.length, greaterThanOrEqualTo(2));

      await store.resetToBuiltin();
      expect(store.sources, isNotEmpty);
    });

    test('导出再导入能还原自定源', () async {
      final SourceStore store = SourceStore(await settings());
      await store.load();
      await store.add(
        VodSource.fromRaw(<String, Object>{
          'name': '带备注的站',
          'api': 'https://b.com/api.php/provide/vod/',
          'note': '备注',
          'charset': 'gbk',
        }),
      );
      final String json = store.exportJson();
      expect(json, contains('带备注的站'));

      final SourceStore another = SourceStore(await settings());
      await another.load();
      // 两个 Store 共用同一份磁盘数据，先清空才能测到"导入带来新增"。
      await another.clearAll();
      final int added = await another.importFromText(json);
      expect(added, greaterThan(0));
      final VodSource? imported =
          another.sources.firstWhereOrNull((VodSource s) => s.name == '带备注的站');
      expect(imported, isNotNull);
      expect(imported!.charset, 'gbk');
    });

    test('test / testMany 走注入的 pinger，状态位正确复位', () async {
      final SourceStore store = SourceStore(await settings());
      await store.load();
      final VodSource ok = sourceOf('可用');
      final VodSource bad = sourceOf('挂了');
      await store.addMany(<VodSource>[ok, bad]);

      SourceStore.pinger = (VodSource s) async => s.name == '可用';
      expect(await store.test(ok), isTrue);
      expect(store.testingId, isNull, reason: 'finally 里要清掉测试中标记');

      final Set<String> passed = await store.testMany(<VodSource>[ok, bad]);
      expect(passed, <String>{ok.id});
    });
  });
}
