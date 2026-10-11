import 'package:flutter/foundation.dart';

import '../data/models/favorite_item.dart';
import '../data/models/vod_item.dart';
import '../data/models/vod_source.dart';
import '../data/repository/record_repository.dart';
import '../data/sync/sync_payload.dart';
import '../data/sync/sync_tombstones.dart';

/// 收藏状态。
class FavoritesStore extends ChangeNotifier {
  List<FavoriteItem> _items = <FavoriteItem>[];
  bool _loading = true;
  bool _disposed = false;

  List<FavoriteItem> get items => _items;
  bool get loading => _loading;
  bool get isEmpty => _items.isEmpty;

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
      ),
    );
    await _save();
    _emit();
    return true;
  }

  Future<void> remove(String key) async {
    final int index = _items.indexWhere((FavoriteItem e) => e.key == key);
    if (index < 0) return;
    _items.removeAt(index);
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
    await SyncTombstones.instance.markMany(tombstoneType, keys);
    await _save();
    _emit();
  }

  Future<void> _save() => RecordRepository.saveFavorites(_items);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
