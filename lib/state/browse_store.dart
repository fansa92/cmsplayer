import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/logger.dart';
import '../data/models/paged_result.dart';
import '../data/models/vod_category.dart';
import '../data/models/vod_item.dart';
import '../data/models/vod_source.dart';
import '../data/repository/vod_repository.dart';

/// 首页 / 分类页的数据状态。
class BrowseStore extends ChangeNotifier {
  VodSource? _source;
  List<VodCategory> _categories = <VodCategory>[];

  /// 选中的分类 id 集合。空集合 = 全部分类。
  ///
  /// 原来是一个 `int`，只能单选；改成集合后单选仍然是最常见的用法
  /// （集合里只有一个元素），macCMS 的 `t=6,7` 也才用得起来。
  Set<int> _typeIds = <int>{};
  bool _onlyFinished = false;

  /// 分类条是否处于「多选模式」。只是 UI 状态，不进查询参数。
  bool _multiSelect = false;
  String _year = '';
  String _area = '';
  String _lang = '';
  String _sortBy = '';
  int _pageSize = K.defaultPageSize;
  int _pageNo = 1;
  int _pageCount = 1;
  int _total = 0;
  List<VodItem> _items = <VodItem>[];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  bool _disposed = false;

  // ---------------- getters ----------------
  VodSource? get source => _source;
  List<VodCategory> get categories => _categories;

  /// 可供点击的分类。详见 [VodCategory.leafOnly]。
  List<VodCategory> get selectableCategories =>
      VodCategory.leafOnly(_categories);

  /// 选中的第一个分类（沿用旧的单选语义，供展示类逻辑使用）。
  int get typeId => _typeIds.isEmpty ? 0 : _typeIds.first;
  Set<int> get selectedCategoryIds => Set<int>.unmodifiable(_typeIds);
  bool get multiSelect => _multiSelect;
  bool get onlyFinished => _onlyFinished;
  String get year => _year;
  String get area => _area;
  String get lang => _lang;
  String get sortBy => _sortBy;
  int get pageSize => _pageSize;
  int get pageNo => _pageNo;
  int get pageCount => _pageCount;
  int get total => _total;
  List<VodItem> get items => _items;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;

  bool get hasFilter =>
      _typeIds.isNotEmpty ||
      _onlyFinished ||
      _year.isNotEmpty ||
      _area.isNotEmpty ||
      _lang.isNotEmpty ||
      _sortBy.isNotEmpty;

  bool get canLoadMore => _pageNo < _pageCount;

  String get categoryTitle {
    if (_typeIds.isEmpty) return '全部';
    if (_categories.isEmpty) return '全部';
    final Map<int, String> names = <int, String>{
      for (final VodCategory c in _categories) c.id: c.name,
    };
    final List<String> picked = <String>[
      for (final int id in _typeIds)
        if (names[id] != null) names[id]!,
    ];
    if (picked.isEmpty) return '全部';
    if (picked.length == 1) return picked.first;
    return '${picked.first} 等 ${picked.length} 类';
  }

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  // ---------------------------------------------------------------- 生命周期

  /// 切换资源站时重置所有筛选与分页。
  Future<void> attach(VodSource source) async {
    if (_source?.id == source.id) return;
    _source = source;
    _categories = <VodCategory>[];
    _typeIds = <int>{};
    _onlyFinished = false;
    _multiSelect = false;
    _year = '';
    _area = '';
    _lang = '';
    _sortBy = '';
    _items = <VodItem>[];
    _pageNo = 1;
    _pageCount = 1;
    _total = 0;
    _error = null;
    _emit();
    await refresh();
  }

  // ---------------------------------------------------------------- 查询

  Future<void> refresh({bool force = false}) async {
    final VodSource? source = _source;
    if (source == null) return;

    _loading = true;
    _error = null;
    _emit();

    try {
      // 先拉列表：macCMS 的任意一次响应都带 class，分类可以顺带拿到。
      // 原来的顺序是先单独拉一次分类、再拉列表，冷启动会连着打两个请求，
      // 而部分资源站（实测 cj.ffzyapi.com）对短时间连发请求会降级返回，
      // 把第二个请求（也就是真正要展示的列表）挤成失败。
      final VodPage page = await VodRepository.instance.query(
        source: source,
        pageNo: 1,
        pageSize: _pageSize,
        typeIds: _typeIds.toList(),
        year: _year,
        area: _area,
        lang: _lang,
        sortBy: _sortBy,
        isEnd: _onlyFinished ? true : null,
        detail: true,
        force: force,
      );

      if (_categories.isEmpty && page.categories.isNotEmpty) {
        _categories = page.categories;
        _emit();
      }

      // 列表响应确实没带 class 时才补一次分类请求。
      if (_categories.isEmpty) {
        try {
          _categories = await VodRepository.instance.refreshCategories(source);
          _emit();
        } on Object catch (e) {
          AppLog.d('Browse', 'categories failed: $e');
        }
      }

      _items = _applyEndFilter(page.items);
      _pageNo = page.page;
      _pageCount = page.pageCount;
      _total = page.total;
      if (_items.isEmpty && _categories.isEmpty) {
        _error = '该资源站没有返回任何内容';
      }
    } on Object catch (e) {
      AppLog.e('Browse', 'refresh failed: $e');
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
        pageSize: _pageSize,
        typeIds: _typeIds.toList(),
        year: _year,
        area: _area,
        lang: _lang,
        sortBy: _sortBy,
        isEnd: _onlyFinished ? true : null,
        detail: true,
      );
      _items = <VodItem>[..._items, ..._applyEndFilter(page.items)];
      _pageNo = page.page;
      _pageCount = page.pageCount;
      _total = page.total;
    } on Object catch (e) {
      AppLog.e('Browse', 'loadMore failed: $e');
      _error = e.toString();
    } finally {
      _loadingMore = false;
      _emit();
    }
  }

  // ---------------------------------------------------------------- 筛选

  /// 已完结筛选的本地兜底。
  ///
  /// 服务端认 `isend` 就已经筛过一遍，这里再筛一次不会改变结果；不认的
  /// 站点会把参数当空气，靠这一步保证列表里不会混进连载中的片子。
  List<VodItem> _applyEndFilter(List<VodItem> items) {
    if (!_onlyFinished) return items;
    return items
        .where((VodItem e) => e.finishedLikely)
        .toList(growable: false);
  }

  void _resetPages() {
    _items = <VodItem>[];
    _pageNo = 1;
    _pageCount = 1;
  }

  /// 单选：点分类条上的某个分类。传 0 表示「全部」。
  Future<void> selectCategory(int typeId) =>
      setCategories(typeId > 0 ? <int>{typeId} : <int>{});

  /// 多选模式下累加 / 取消某个分类。
  Future<void> toggleCategory(int id) {
    if (id <= 0) return setCategories(<int>{});
    final Set<int> next = Set<int>.from(_typeIds);
    if (!next.remove(id)) next.add(id);
    return setCategories(next);
  }

  /// 直接指定分类集合。空集合等同于「全部」。
  Future<void> setCategories(Set<int> ids) async {
    final Set<int> next = ids.where((int e) => e > 0).toSet();
    if (next.length == _typeIds.length && next.containsAll(_typeIds)) return;
    _typeIds = next;
    _resetPages();
    _emit();
    await refresh();
  }

  /// 切换分类条的多选模式。退出多选时把选中收敛成第一个，避免留下
  /// 一个用户看不见的解释不清的多选状态。
  Future<void> setMultiSelect(bool value) async {
    if (_multiSelect == value) return;
    _multiSelect = value;
    _emit();
    if (!value && _typeIds.length > 1) {
      await setCategories(<int>{_typeIds.first});
    }
  }

  Future<void> applyFilter({
    String? year,
    String? area,
    String? lang,
    String? sortBy,
    bool? onlyFinished,
  }) async {
    bool changed = false;
    if (year != null && _year != year) {
      _year = year;
      changed = true;
    }
    if (area != null && _area != area) {
      _area = area;
      changed = true;
    }
    if (lang != null && _lang != lang) {
      _lang = lang;
      changed = true;
    }
    if (sortBy != null && _sortBy != sortBy) {
      _sortBy = sortBy;
      changed = true;
    }
    if (onlyFinished != null && _onlyFinished != onlyFinished) {
      _onlyFinished = onlyFinished;
      changed = true;
    }
    if (!changed) return;
    _resetPages();
    _emit();
    await refresh();
  }

  Future<void> clearFilter() async {
    if (!hasFilter) return;
    _typeIds = <int>{};
    _onlyFinished = false;
    _multiSelect = false;
    _year = '';
    _area = '';
    _lang = '';
    _sortBy = '';
    _resetPages();
    _emit();
    await refresh();
  }

  Future<void> setPageSize(int size) async {
    if (_pageSize == size) return;
    _pageSize = size;
    _items = <VodItem>[];
    _pageNo = 1;
    _pageCount = 1;
    _emit();
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
