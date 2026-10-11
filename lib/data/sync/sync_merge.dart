import '../models/favorite_item.dart';
import '../models/play_record.dart';
import '../models/vod_source.dart';
import 'sync_payload.dart';

/// 合并战报：相对于合并前的本地，发生了什么。
class SyncDiff {
  const SyncDiff({
    this.added = 0,
    this.updated = 0,
    this.removed = 0,
    this.history = 0,
    this.favorites = 0,
    this.sources = 0,
  });

  /// 本地没有、这次合并进来的条数。
  final int added;

  /// 两边都有、但取了对方那份（对方那台上更新过）。
  final int updated;

  /// 被删除墓碑裁掉的条数。
  final int removed;

  /// 合并后各集合的条数，用于结果提示。
  final int history;
  final int favorites;
  final int sources;

  bool get isEmpty => added == 0 && updated == 0 && removed == 0;

  /// 两轮合并的战报叠加。第二轮只关心总数，所以条数取后者。
  SyncDiff operator +(SyncDiff other) => SyncDiff(
        added: added + other.added,
        updated: updated + other.updated,
        removed: removed + other.removed,
        history: other.history,
        favorites: other.favorites,
        sources: other.sources,
      );

  /// 一句话摘要，直接喂给 SnackBar。
  String get summary {
    if (isEmpty) return '数据一致，无需变更';
    return <String>[
      if (added > 0) '新增 $added',
      if (updated > 0) '更新 $updated',
      if (removed > 0) '移除 $removed',
    ].join('、');
  }
}

/// 合并规则里的一个条目：key 去重，ts 裁决。
class _Entry<T> {
  const _Entry(this.key, this.ts, this.item);

  final String key;
  final int ts;
  final T item;
}

/// 合并器。
///
/// 规则一句话讲完：**同一个 key 只留一份，谁的时间戳新留谁；
/// 时间戳不比删除墓碑新的，保持删除。**
///
/// 这样两边各改各的条目不会互相覆盖（整文件覆盖式同步就会丢一边），
/// 而"我在手机上删掉的收藏"也不会被电脑上的旧数据复活。
class SyncMerger {
  const SyncMerger._();

  /// 合并两个数据包。参数顺序无关，结果对称。
  static SyncPayload merge(SyncPayload a, SyncPayload b) {
    final Map<String, Map<String, int>> tombs = SyncPayload.pruneTombstones(
      _mergeTombstones(a.tombstones, b.tombstones),
    );

    final List<_Entry<PlayRecord>> history =
        _mergeList<PlayRecord>(_history(a), _history(b), tombs);
    final List<_Entry<FavoriteItem>> favorites =
        _mergeList<FavoriteItem>(_favorites(a), _favorites(b), tombs);
    final List<_Entry<VodSource>> sources =
        _mergeList<VodSource>(_sources(a), _sources(b), tombs);

    history.sort((_Entry<PlayRecord> x, _Entry<PlayRecord> y) =>
        y.ts.compareTo(x.ts));
    favorites.sort((_Entry<FavoriteItem> x, _Entry<FavoriteItem> y) =>
        y.ts.compareTo(x.ts));
    // 源的顺序是用户自己排的，合并后仍然按 sort 走，不能按时间重排。
    // 注意元素是 _Entry 而不是 VodSource 本身，取值要经 .item。
    sources.sort((_Entry<VodSource> x, _Entry<VodSource> y) {
      final int c = x.item.sort.compareTo(y.item.sort);
      return c != 0 ? c : x.item.name.compareTo(y.item.name);
    });

    return SyncPayload(
      updatedAt: a.updatedAt.isAfter(b.updatedAt) ? a.updatedAt : b.updatedAt,
      history: history.map((_Entry<PlayRecord> e) => e.item).toList(),
      favorites: favorites.map((_Entry<FavoriteItem> e) => e.item).toList(),
      sources: sources.map((_Entry<VodSource> e) => e.item).toList(),
      tombstones: tombs,
    );
  }

  /// 合并前后各集合的条数增减。
  static SyncDiff diff(SyncPayload before, SyncPayload after) {
    int added = 0, updated = 0, removed = 0;

    void tally(List<_Entry<Object?>> b, List<_Entry<Object?>> a) {
      final Map<String, int> bm = <String, int>{
        for (final _Entry<Object?> e in b) e.key: e.ts,
      };
      final Map<String, int> am = <String, int>{
        for (final _Entry<Object?> e in a) e.key: e.ts,
      };
      am.forEach((String k, int v) {
        final int? old = bm[k];
        if (old == null) {
          added++;
        } else if (old != v) {
          updated++;
        }
      });
      for (final String k in bm.keys) {
        if (!am.containsKey(k)) removed++;
      }
    }

    tally(_history(before), _history(after));
    tally(_favorites(before), _favorites(after));
    tally(_sources(before), _sources(after));

    return SyncDiff(
      added: added,
      updated: updated,
      removed: removed,
      history: after.history.length,
      favorites: after.favorites.length,
      sources: after.sources.length,
    );
  }

  // ---------------------------------------------------------------- 条目

  static List<_Entry<PlayRecord>> _history(SyncPayload p) => p.history
      .map((PlayRecord e) => _Entry<PlayRecord>(
            e.key,
            e.updatedAt.millisecondsSinceEpoch,
            e,
          ))
      .toList();

  static List<_Entry<FavoriteItem>> _favorites(SyncPayload p) => p.favorites
      .map((FavoriteItem e) => _Entry<FavoriteItem>(
            e.key,
            e.createdAt.millisecondsSinceEpoch,
            e,
          ))
      .toList();

  static List<_Entry<VodSource>> _sources(SyncPayload p) => p.sources
      .map((VodSource e) => _Entry<VodSource>(
            e.id,
            e.createdAt.millisecondsSinceEpoch,
            e,
          ))
      .toList();

  // ---------------------------------------------------------------- 内部

  static List<_Entry<T>> _mergeList<T>(
    List<_Entry<T>> left,
    List<_Entry<T>> right,
    Map<String, Map<String, int>> tombs,
  ) {
    final Map<String, int> tomb = tombs[_collectionOf<T>()] ?? const <String, int>{};

    final Map<String, _Entry<T>> byKey = <String, _Entry<T>>{};
    for (final _Entry<T> e in left) {
      byKey[e.key] = e;
    }
    for (final _Entry<T> e in right) {
      final _Entry<T>? cur = byKey[e.key];
      // 严格大于才覆盖：两边时间戳相同说明是同一条，留哪边都一样。
      if (cur == null || e.ts > cur.ts) byKey[e.key] = e;
    }

    final List<_Entry<T>> out = <_Entry<T>>[];
    for (final _Entry<T> e in byKey.values) {
      final int? deletedAt = tomb[e.key];
      // 用 >= 而不是 >：同毫秒内先加后删时，应当算作删掉了。
      if (deletedAt != null && deletedAt >= e.ts) continue;
      out.add(e);
    }
    return out;
  }

  static String _collectionOf<T>() {
    if (T == PlayRecord) return SyncBox.history;
    if (T == FavoriteItem) return SyncBox.favorites;
    return SyncBox.sources;
  }

  static Map<String, Map<String, int>> _mergeTombstones(
    Map<String, Map<String, int>> a,
    Map<String, Map<String, int>> b,
  ) {
    final Map<String, Map<String, int>> out = <String, Map<String, int>>{};
    for (final Map<String, Map<String, int>> side
        in <Map<String, Map<String, int>>>[a, b]) {
      side.forEach((String box, Map<String, int> items) {
        final Map<String, int> inner =
            out.putIfAbsent(box, () => <String, int>{});
        items.forEach((String key, int ts) {
          final int? cur = inner[key];
          if (cur == null || ts > cur) inner[key] = ts;
        });
      });
    }
    return out;
  }
}
