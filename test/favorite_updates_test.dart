import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/data/models/favorite_item.dart';
import 'package:cms_player/data/models/vod_item.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/data/repository/record_repository.dart';
import 'package:cms_player/state/favorites_store.dart';

import 'helpers/fakes.dart';

/// 收藏更新检查：靠 `ids` 批量详情拿最新集数，和收藏时的基线比。
void main() {
  useIsolatedStores();

  final VodSource source = sourceOf('主站');
  final VodSource other = sourceOf('备用站', host: 'b.com');

  late FavoritesStore favorites;

  setUp(() async {
    favorites = FavoritesStore();
    await favorites.load();
  });

  String playUrl(int id, int episodes) => List<String>.generate(
        episodes,
        (int i) => '第${i + 1}集\$https://a.com/$id/$i.m3u8',
      ).join('#');

  VodItem itemOf(int id, {int episodes = 10}) => VodItem(
        id: id,
        name: '剧$id',
        playFrom: 'm3u8',
        playUrl: playUrl(id, episodes),
      );

  /// 假接口：按请求里的 `ids` 返回对应集数的详情。
  FakeHttpClient serve(Map<int, int> episodesByVodId) {
    final FakeHttpClient client = FakeHttpClient((RecordedRequest request) {
      if (request.url.host == 'b.com') return fakeResponse(500, 'boom');
      final String raw = request.url.queryParameters['ids'] ?? '';
      final List<Map<String, Object>> list = <Map<String, Object>>[];
      for (final String part in raw.split(',')) {
        final int id = int.tryParse(part) ?? 0;
        final int episodes = episodesByVodId[id] ?? 0;
        if (episodes <= 0) continue;
        list.add(<String, Object>{
          'vod_id': id,
          'vod_name': '剧$id',
          'vod_play_from': 'm3u8',
          'vod_play_url': playUrl(id, episodes),
        });
      }
      return fakeJson(vodPageJson(list: list, total: list.length));
    });
    useFakeApi(client);
    return client;
  }

  test('集数变多时标记有更新', () async {
    await favorites.toggle(source: source, item: itemOf(1, episodes: 10));
    serve(<int, int>{1: 13});

    await favorites.checkUpdates(sources: <VodSource>[source]);

    final String key = favorites.items.single.key;
    expect(favorites.updatedCount, 1);
    expect(favorites.hasUpdate(key), isTrue);
    expect(favorites.latestEpisodesOf(key), 13);
  });

  test('集数没变不算更新', () async {
    await favorites.toggle(source: source, item: itemOf(1, episodes: 10));
    serve(<int, int>{1: 10});

    await favorites.checkUpdates(sources: <VodSource>[source]);

    expect(favorites.updatedCount, 0);
    expect(favorites.latestEpisodesOf(favorites.items.single.key), 10);
  });

  test('老数据没有基线：第一次检查只补基线，不误报', () async {
    await RecordRepository.saveFavorites(<FavoriteItem>[
      FavoriteItem.fromVod(
        sourceId: source.id,
        sourceName: source.name,
        vodId: 2,
        vodName: '老收藏',
        episodes: 0,
      ),
    ]);
    await favorites.load();
    serve(<int, int>{2: 20});

    await favorites.checkUpdates(sources: <VodSource>[source]);

    final FavoriteItem fav = favorites.items.single;
    expect(favorites.updatedCount, 0, reason: '没有基线就没有更新可言');
    expect(fav.episodes, 20, reason: '基线要被写回，避免下次仍无基线');

    // 再检查一次：这次有基线了，集数没变仍是 0。
    await favorites.checkUpdates(sources: <VodSource>[source], force: true);
    expect(favorites.updatedCount, 0);
  });

  test('点开之后清掉标记并推进基线', () async {
    await favorites.toggle(source: source, item: itemOf(1, episodes: 10));
    serve(<int, int>{1: 14});
    await favorites.checkUpdates(sources: <VodSource>[source]);
    final String key = favorites.items.single.key;
    expect(favorites.hasUpdate(key), isTrue);

    await favorites.markSeen(key);

    expect(favorites.hasUpdate(key), isFalse);
    expect(favorites.items.single.episodes, 14);
    expect(await RecordRepository.loadFavorites(), hasLength(1));
    expect((await RecordRepository.loadFavorites()).single.episodes, 14,
        reason: '基线要落盘，重启后不该重新报一次');
  });

  test('限频：非强制调用不会重复请求', () async {
    await favorites.toggle(source: source, item: itemOf(1, episodes: 10));
    final FakeHttpClient client = serve(<int, int>{1: 11});

    await favorites.checkUpdates(sources: <VodSource>[source]);
    final int first = client.requests.length;
    await favorites.checkUpdates(sources: <VodSource>[source]);

    expect(first, 1);
    expect(client.requests.length, first, reason: '六分钟内不该再打接口');

    await favorites.checkUpdates(sources: <VodSource>[source], force: true);
    expect(client.requests.length, first + 1);
  });

  test('单个源失败不影响其它源', () async {
    await favorites.toggle(source: other, item: itemOf(5, episodes: 3));
    await favorites.toggle(source: source, item: itemOf(1, episodes: 10));
    serve(<int, int>{1: 12, 5: 9});

    await favorites.checkUpdates(sources: <VodSource>[other, source]);

    final String key = favorites.items
        .firstWhere((FavoriteItem e) => e.sourceId == source.id)
        .key;
    expect(favorites.hasUpdate(key), isTrue);
    expect(favorites.latestEpisodesOf(key), 12);
  });

  test('删掉收藏后更新状态一起清掉', () async {
    await favorites.toggle(source: source, item: itemOf(1, episodes: 10));
    serve(<int, int>{1: 12});
    await favorites.checkUpdates(sources: <VodSource>[source]);
    final String key = favorites.items.single.key;
    expect(favorites.hasUpdate(key), isTrue);

    await favorites.remove(key);

    expect(favorites.hasUpdate(key), isFalse);
    expect(favorites.latestEpisodesOf(key), isNull);
    expect(favorites.updatedCount, 0);
  });
}
