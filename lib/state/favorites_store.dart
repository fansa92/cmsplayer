import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../data/models/favorite_item.dart';
import '../data/models/vod_item.dart';
import '../data/models/vod_source.dart';
import '../data/repository/record_repository.dart';
import '../data/repository/vod_repository.dart';
import '../data/sync/sync_payload.dart';
import '../data/sync/sync_tombstones.dart';

/// 收藏状态。
///
/// 除了增删，它还负责「收藏的剧更新了没有」：进收藏页时按源批量拉一次
/// 详情，把集数和收藏时的基线比对。结果只放内存 —— 这是个随时可以重算的
/// 派生状态，没必要持久化，重启后重新检查一次就行。
class FavoritesStore extends ChangeNotifier {
  List<FavoriteItem> _items = <FavoriteItem>[];
  bool _loading = true;
  bool _disposed = false;

  /// `key -> 最近一次检查到的集数`。
  final Map<String, int> _latest = <String, int>{};

  /// 有更新的收藏 key。
  final Set<String> _updated = <String>{};

  bool _checking = false;
  bool _rebaseDirty = false;
  DateTime? _lastCheckAt;

  /// 每批最多查多少部：ids 拼在 URL 里，太多会被服务端截断。
  static const int _checkBatch = 50;

  List<FavoriteItem> get items => _items;
  bool get loading => _loading;
  bool get isEmpty => _items.isEmpty;
  bool get checking => _checking;

  /// 有更新的收藏数量。
  int get updatedCount => _updated.length;

  DateTime? get lastCheckAt => _lastCheckAt;

  bool hasUpdate(String key) => _updated.contains(key);

  /// 该条收藏最近一次检查到的集数，没检查过时为 null。
  int? latestEpisodesOf(String key) => _latest[key];

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  /// 本表在墓碑里的类型名。
  ///
  /// 删除本地数据时必须顺手记一条墓碑，否则对方设备下次同步会把这条收藏
  /// 又推回来 —— 删除看起来"没生效"。见 [SyncTombstones]。
  static const String tombstoneType = SyncBox.favorites;

  Future<void> load() async {
    _loading = true;
    _emit();
    try {
      _items = await RecordRepository.loadFavorites();
    } finally {
      _loading = false;
      _emit();
    }
  }

  String keyOf(String sourceId, int vodId) => '$sourceId|$vodId';

  bool contains(String sourceId, int vodId) =>
      _items.any((FavoriteItem e) => e.key == keyOf(sourceId, vodId));

  FavoriteItem? find(String sourceId, int vodId) {
    for (final FavoriteItem e in _items) {
      if (e.key == keyOf(sourceId, vodId)) return e;
    }
    return null;
  }

  List<FavoriteItem> forSource(String sourceId) =>
      _items.where((FavoriteItem e) => e.sourceId == sourceId).toList();

  /// 返回收藏后的新状态（true = 已收藏）。
  Future<bool> toggle({
    required VodSource source,
    required VodItem item,
  }) async {
    final String key = keyOf(source.id, item.id);
    final int index = _items.indexWhere((FavoriteItem e) => e.key == key);
    if (index >= 0) {
      _items.removeAt(index);
      // 取消收藏也是删除，同样要记墓碑，否则对方下次同步会把它又加回来。
      await SyncTombstones.instance.mark(tombstoneType, key);
      await _save();
      _emit();
      return false;
    }
    _items.insert(
      0,
      FavoriteItem.fromVod(
        sourceId: source.id,
        sourceName: source.name,
        vodId: item.id,
        vodName: item.name,
        vodPic: item.pic,
        typeName: item.typeName,
        remarks: item.remarks,
        episodes: item.episodeCount,
      ),
    );
    // 新收藏以当前集数为基线，天然不算"有更新"。
    _updated.remove(key);
    await _save();
    _emit();
    return true;
  }

  Future<void> remove(String key) async {
    final int index = _items.indexWhere((FavoriteItem e) => e.key == key);
    if (index < 0) return;
    _items.removeAt(index);
    _latest.remove(key);
    _updated.remove(key);
    // 先记墓碑再落盘：反过来的话，进程在这中间被杀掉就会留下"数据删了但
    // 墓碑没记"的状态，同步时对方会把收藏原样推回来。
    await SyncTombstones.instance.mark(tombstoneType, key);
    await _save();
    _emit();
  }

  Future<void> removeMany(List<String> keys) async {
    final Set<String> set = keys.toSet();
    final List<String> removed = _items
        .where((FavoriteItem e) => set.contains(e.key))
        .map((FavoriteItem e) => e.key)
        .toList(growable: false);
    if (removed.isEmpty) return;
    _items.removeWhere((FavoriteItem e) => set.contains(e.key));
    for (final String key in removed) {
      _latest.remove(key);
      _updated.remove(key);
    }
    await SyncTombstones.instance.markMany(tombstoneType, removed);
    await _save();
    _emit();
  }

  Future<void> clear() async {
    // 清空是逐条删除的等价物，要把当时存在的每一条都记成墓碑 —— 只清本地
    // 的话，其他设备下次同步会把整个收藏列表又推回来。
    final List<String> keys =
        _items.map((FavoriteItem e) => e.key).toList(growable: false);
    _items = <FavoriteItem>[];
    _latest.clear();
    _updated.clear();
    await SyncTombstones.instance.markMany(tombstoneType, keys);
    await _save();
    _emit();
  }

  // ---------------------------------------------------------------- 更新检查

  /// 批量检查收藏里有没有新集。
  ///
  /// [force] 为假时受 [K.favoriteCheckInterval] 限频：进收藏页都会调一次，
  /// 不加限制的话来回切 tab 就会一直打接口。
  Future<void> checkUpdates({
    required List<VodSource> sources,
    bool force = false,
  }) async {
    if (_checking || _items.isEmpty || sources.isEmpty) return;
    final DateTime? last = _lastCheckAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < K.favoriteCheckInterval) {
      return;
    }

    _checking = true;
    _emit();
    try {
      final Map<String, List<FavoriteItem>> grouped =
          <String, List<FavoriteItem>>{};
      for (final FavoriteItem f in _items) {
        grouped.putIfAbsent(f.sourceId, () => <FavoriteItem>[]).add(f);
      }

      for (final VodSource source in sources) {
        final List<FavoriteItem> list =
            grouped[source.id] ?? const <FavoriteItem>[];
        if (list.isEmpty) continue;

        for (int start = 0; start < list.length; start += _checkBatch) {
          int end = start + _checkBatch;
          if (end > list.length) end = list.length;
          final List<FavoriteItem> batch = list.sublist(start, end);
          final List<int> ids = batch
              .map((FavoriteItem e) => int.tryParse(e.vodId) ?? 0)
              .where((int e) => e > 0)
              .toList(growable: false);
          if (ids.isEmpty) continue;

          List<VodItem> details;
          try {
            details = await VodRepository.instance
                .detailsByIds(source: source, ids: ids);
          } on Object {
            // 单个源失败不影响其它源，下次进页面再试。
            continue;
          }

          final Map<String, VodItem> byId = <String, VodItem>{
            for (final VodItem d in details) '${d.id}': d,
          };

          for (final FavoriteItem fav in batch) {
            final VodItem? latest = byId[fav.vodId];
            if (latest == null) continue;
            final int newest = latest.episodeCount > 0
                ? latest.episodeCount
                : latest.totalEpisodes;
            if (newest <= 0) continue;
            _latest[fav.key] = newest;

            if (fav.episodes <= 0) {
              // 老数据没有基线：把当前集数写回去当基线，但不算更新。
              _replace(fav.key, fav.copyWith(episodes: newest));
            } else if (newest > fav.episodes) {
              _updated.add(fav.key);
            } else {
              _updated.remove(fav.key);
            }
          }
        }
      }

      if (_rebaseDirty) await _save();
    } finally {
      _rebaseDirty = false;
      _checking = false;
      _lastCheckAt = DateTime.now();
      _emit();
    }
  }

  /// 用户点开了这条收藏：把基线推进到最新集数，清掉"有更新"。
  Future<void> markSeen(String key) async {
    final int? newest = _latest[key];
    final int index = _items.indexWhere((FavoriteItem e) => e.key == key);
    _updated.remove(key);
    if (index >= 0 && newest != null && newest > _items[index].episodes) {
      _items[index] = _items[index].copyWith(episodes: newest);
      await _save();
    }
    _emit();
  }

  /// 替换某条收藏并标记需要落盘（批量检查里可能改很多条，最后统一写一次）。
  void _replace(String key, FavoriteItem next) {
    final int index = _items.indexWhere((FavoriteItem e) => e.key == key);
    if (index < 0) return;
    _items[index] = next;
    _rebaseDirty = true;
  }

  Future<void> _save() => RecordRepository.saveFavorites(_items);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
