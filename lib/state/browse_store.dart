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
  String _order = '';
  String _letter = '';
  int _pageSize = K.defaultPageSize;
  int _pageNo = 1;
  int _pageCount = 1;
  int _total = 0;
  List<VodItem> _items = <VodItem>[];

  /// 未经本地筛选的原始条目，用来算 A–Z 侧栏有哪些字母可点。
  /// 用筛选后的 [items] 算的话，选中「B」之后侧栏就只剩 B，没法再切走了。
  List<VodItem> _rawItems = <VodItem>[];
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
  String get order => _order;
  String get letter => _letter;
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
      _sortBy.isNotEmpty ||
      _order.isNotEmpty ||
      _letter.isNotEmpty;

  bool get canLoadMore => _pageNo < _pageCount;

  /// 当前这批结果里出现过、且能拿来做索引的首字母（已排序）。
  ///
  /// 中文片名没有拼音库，只能认源站给的 `vod_letter` 和以英文字母开头的
  /// 片名；一个字母都没有时界面会把侧栏整个隐藏，不留一排死按钮。
  List<String> get availableLetters {
    final Set<String> letters = <String>{};
    for (final VodItem item in _rawItems) {
      final String l = letterOf(item);
      if (l.isNotEmpty) letters.add(l);
    }
    final List<String> sorted = letters.toList()..sort();
    return List<String>.unmodifiable(sorted);
  }

  /// 取一个条目可索引的首字母，取不到返回空串。
  static String letterOf(VodItem item) {
    final String given = item.letter.trim().toUpperCase();
    if (RegExp(r'^[A-Z]$').hasMatch(given)) return given;
    final String name = item.name.trim().toUpperCase();
    if (name.isNotEmpty && RegExp(r'^[A-Z]').hasMatch(name)) {
      return name.substring(0, 1);
    }
    return '';
  }

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
    _order = '';
    _letter = '';
    _items = <VodItem>[];
    _rawItems = <VodItem>[];
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
        order: _order,
        letter: _letter,
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

      _rawItems = page.items;
      _items = _applyFilters(page.items);
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
        order: _order,
        letter: _letter,
        isEnd: _onlyFinished ? true : null,
        detail: true,
      );
      _rawItems = <VodItem>[..._rawItems, ...page.items];
      _items = _applyFilters(_rawItems);
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

  /// 服务端侧筛选的本地兜底（已完结 / 首字母）。
  ///
  /// 认 `isend` / `letter` 的站服务端已经筛过，再筛一次不改变结果；不认的
  /// 站会把参数当空气，靠这一步保证列表里不混进连载中或其它字母的片子。
  /// `letter` 只在响应里确实出现该字母时才动本地过滤：很多站既不认
  /// `letter` 也不返回 `vod_letter`，无脑按首字母筛会把整页清空。
  List<VodItem> _applyFilters(List<VodItem> items) {
    if (!_onlyFinished && _letter.isEmpty) return items;
    final bool useLetter = _letter.isNotEmpty &&
        items.any((VodItem e) => letterOf(e) == _letter);
    return items.where((VodItem e) {
      if (_onlyFinished && !e.finishedLikely) return false;
      if (useLetter && letterOf(e) != _letter) return false;
      return true;
    }).toList(growable: false);
  }

  void _resetPages() {
    _items = <VodItem>[];
    _rawItems = <VodItem>[];
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
    String? order,
    String? letter,
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
    if (order != null) {
      final String next = (order == 'asc' || order == 'desc') ? order : '';
      if (_order != next) {
        _order = next;
        changed = true;
      }
    }
    if (letter != null) {
      final String upper = letter.trim().toUpperCase();
      final String next = RegExp(r'^[A-Z]$').hasMatch(upper) ? upper : '';
      if (_letter != next) {
        _letter = next;
        changed = true;
      }
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
    _order = '';
    _letter = '';
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
