import '../../core/constants.dart';
import '../../core/storage/json_store.dart';
import '../models/favorite_item.dart';
import '../models/play_record.dart';

/// 收藏与播放记录的持久化。
class RecordRepository {
  RecordRepository._();

  /// 历史记录最多保留条数，超出后按最近更新裁剪。
  static const int maxHistory = 500;

  static Future<List<FavoriteItem>> loadFavorites() async {
    final List<Map<String, dynamic>> raw =
        await JsonStore.readList(K.boxFavorites);
    final List<FavoriteItem> list = raw.map(FavoriteItem.fromJson).toList();
    list.sort((FavoriteItem a, FavoriteItem b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  static Future<void> saveFavorites(List<FavoriteItem> list) async {
    await JsonStore.writeList(
      K.boxFavorites,
      list.map((FavoriteItem e) => e.toJson()).toList(),
    );
  }

  static Future<List<PlayRecord>> loadHistory() async {
    final List<Map<String, dynamic>> raw = await JsonStore.readList(K.boxHistory);
    final List<PlayRecord> list = raw.map(PlayRecord.fromJson).toList();
    list.sort((PlayRecord a, PlayRecord b) => b.updatedAt.compareTo(a.updatedAt));
    if (list.length > maxHistory) list.removeRange(maxHistory, list.length);
    return list;
  }

  static Future<void> saveHistory(List<PlayRecord> list) async {
    final List<PlayRecord> sorted = List<PlayRecord>.of(list)
      ..sort((PlayRecord a, PlayRecord b) => b.updatedAt.compareTo(a.updatedAt));
    if (sorted.length > maxHistory) {
      sorted.removeRange(maxHistory, sorted.length);
    }
    await JsonStore.writeList(
      K.boxHistory,
      sorted.map((PlayRecord e) => e.toJson()).toList(),
    );
  }

  static Future<List<String>> loadSearchKeywords() async {
    final List<Map<String, dynamic>> raw = await JsonStore.readList(K.boxSearches);
    return raw
        .map((Map<String, dynamic> e) => (e['q'] ?? '').toString())
        .where((String q) => q.isNotEmpty)
        .toList();
  }

  static Future<void> saveSearchKeywords(List<String> keywords) async {
    await JsonStore.writeList(
      K.boxSearches,
      keywords
          .take(30)
          .map((String q) => <String, dynamic>{'q': q})
          .toList(),
    );
  }
}
