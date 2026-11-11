import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/logger.dart';
import '../data/models/paged_result.dart';
import '../data/models/vod_item.dart';
import '../data/models/vod_source.dart';
import '../data/repository/vod_repository.dart';

/// 榜单页数据状态。
///
/// macCMS 的排序本来只是一个 `by` 参数，分类页把它当筛选条件用；这里单独
/// 拎出来做榜单，逻辑比浏览页简单得多：只有「排序方式 + 分页」，
/// 不需要年代 / 地区 / 分类抽屉。
class RankStore extends ChangeNotifier {
  /// 榜单支持的排序方式。`by=input`（最多推荐）太依赖各站自己的推荐位，
  /// 放在榜单里名不副实，所以不列。
  static const List<String> sorts = <String>['hits', 'score', 'time'];

  VodSource? _source;
  String _sortBy = sorts.first;
  int _pageNo = 1;
  int _pageCount = 1;
  int _total = 0;
  List<VodItem> _items = <VodItem>[];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  bool _disposed = false;

  VodSource? get source => _source;
  String get sortBy => _sortBy;
  int get pageNo => _pageNo;
  int get pageCount => _pageCount;
  int get total => _total;
  List<VodItem> get items => _items;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;
  bool get canLoadMore => _pageNo < _pageCount;

  /// 排序方式的中文名。
  String get sortLabel => K.sortOptions[_sortBy] ?? _sortBy;

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  /// 绑定资源站。同一个站重复调用不会重复请求 —— 榜单是在壳外单独 push
  /// 的页面，每次打开都会走一遍 attach，不去重就会每开一次打一次请求。
  Future<void> attach(VodSource source) async {
    if (_source?.id == source.id) return;
    _source = source;
    _items = <VodItem>[];
    _pageNo = 1;
    _pageCount = 1;
    _total = 0;
    _error = null;
    _emit();
    await refresh();
  }

  Future<void> setSort(String by) async {
    if (_sortBy == by) return;
    _sortBy = by;
    _items = <VodItem>[];
    _pageNo = 1;
    _pageCount = 1;
    _total = 0;
    _emit();
    await refresh();
  }

  Future<void> refresh({bool force = false}) async {
    final VodSource? source = _source;
    if (source == null) return;

    _loading = true;
    _error = null;
    _emit();
    try {
      final VodPage page = await VodRepository.instance.query(
        source: source,
        pageNo: 1,
        pageSize: K.defaultPageSize,
        sortBy: _sortBy,
        detail: true,
        force: force,
      );
      _items = page.items;
      _pageNo = page.page;
      _pageCount = page.pageCount;
      _total = page.total;
    } on Object catch (e) {
      AppLog.e('Rank', 'refresh failed: $e');
      _error = e.toString();
    } finally {
      _loading = false;
      _emit();
    }
  }

  Future<void> loadMore() async {
    final VodSource? source = _source;
    if (source == null) return;
    if (_loading || _loadingMore || !canLoadMore) return;

    _loadingMore = true;
    _emit();
    try {
      final VodPage page = await VodRepository.instance.query(
        source: source,
        pageNo: _pageNo + 1,
        pageSize: K.defaultPageSize,
        sortBy: _sortBy,
        detail: true,
      );
      _items = <VodItem>[..._items, ...page.items];
      _pageNo = page.page;
      _pageCount = page.pageCount;
      _total = page.total;
    } on Object catch (e) {
      AppLog.e('Rank', 'loadMore failed: $e');
      _error = e.toString();
    } finally {
      _loadingMore = false;
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
