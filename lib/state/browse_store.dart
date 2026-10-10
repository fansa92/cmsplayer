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
  int _typeId = 0;
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
  int get typeId => _typeId;
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
      _typeId > 0 || _year.isNotEmpty || _area.isNotEmpty || _lang.isNotEmpty || _sortBy.isNotEmpty;

  bool get canLoadMore => _pageNo < _pageCount;

  String get categoryTitle {
    if (_categories.isEmpty) return '全部';
    final VodCategory? c =
        _categories.where((VodCategory e) => e.id == _typeId).firstOrNull;
    return c?.name ?? '全部';
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
    _typeId = 0;
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
      if (_categories.isEmpty) {
        try {
          final List<VodCategory> cats =
              await VodRepository.instance.refreshCategories(source);
          _categories = cats;
          _emit();
        } on Object catch (e) {
          AppLog.d('Browse', 'categories failed: $e');
        }
      }

      final VodPage page = await VodRepository.instance.query(
        source: source,
        pageNo: 1,
        pageSize: _pageSize,
        typeId: _typeId,
        year: _year,
        area: _area,
        lang: _lang,
        sortBy: _sortBy,
        detail: true,
        force: force,
      );

      if (_categories.isEmpty && page.categories.isNotEmpty) {
        _categories = page.categories;
      }
      _items = page.items;
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
        typeId: _typeId,
        year: _year,
        area: _area,
        lang: _lang,
        sortBy: _sortBy,
        detail: true,
      );
      _items = <VodItem>[..._items, ...page.items];
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

  Future<void> selectCategory(int typeId) async {
    if (_typeId == typeId) return;
    _typeId = typeId;
    _items = <VodItem>[];
    _pageNo = 1;
    _pageCount = 1;
    _emit();
    await refresh();
  }

  Future<void> applyFilter({
    String? year,
    String? area,
    String? lang,
    String? sortBy,
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
    if (!changed) return;
    _items = <VodItem>[];
    _pageNo = 1;
    _pageCount = 1;
    _emit();
    await refresh();
  }

  Future<void> clearFilter() async {
    if (!hasFilter) return;
    _typeId = 0;
    _year = '';
    _area = '';
    _lang = '';
    _sortBy = '';
    _items = <VodItem>[];
    _pageNo = 1;
    _pageCount = 1;
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

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final Iterator<T> it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
