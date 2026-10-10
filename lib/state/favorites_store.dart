import 'package:flutter/foundation.dart';

import '../data/models/favorite_item.dart';
import '../data/models/vod_item.dart';
import '../data/models/vod_source.dart';
import '../data/repository/record_repository.dart';

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
    await _save();
    _emit();
  }

  Future<void> removeMany(List<String> keys) async {
    final Set<String> set = keys.toSet();
    _items.removeWhere((FavoriteItem e) => set.contains(e.key));
    await _save();
    _emit();
  }

  Future<void> clear() async {
    _items = <FavoriteItem>[];
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
