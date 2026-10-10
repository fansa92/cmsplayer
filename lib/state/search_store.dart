import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import '../data/models/paged_result.dart';
import '../data/models/vod_item.dart';
import '../data/models/vod_source.dart';
import '../data/repository/record_repository.dart';
import '../data/repository/vod_repository.dart';

/// 搜索状态。支持单源搜索与多源并发搜索。
class SearchStore extends ChangeNotifier {
  String _query = '';
  List<VodItem> _items = <VodItem>[];
  final Map<String, VodSource> _itemSource = <String, VodSource>{};
  bool _loading = false;
  String? _error;
  int _pageNo = 1;
  int _pageCount = 1;
  bool _multiSource = false;
  List<String> _history = <String>[];
  bool _historyLoaded = false;
  bool _disposed = false;

  String get query => _query;
  List<VodItem> get items => _items;
  bool get loading => _loading;
  String? get error => _error;
  int get pageNo => _pageNo;
  int get pageCount => _pageCount;
  bool get canLoadMore => _pageNo < _pageCount;
  bool get multiSource => _multiSource;
  bool get hasResult => _items.isNotEmpty;
  List<String> get history => _history;

  /// 结果条目所属的源（多源搜索时用于展示来源标签）。
  VodSource? sourceOf(VodItem item) => _itemSource['${item.id}|${item.name}'];

  static String _itemKey(VodItem item) => '${item.id}|${item.name}';

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  void setMultiSource(bool value) {
    if (_multiSource == value) return;
    _multiSource = value;
    _emit();
  }

  void clearResult() {
    _query = '';
    _items = <VodItem>[];
    _itemSource.clear();
    _error = null;
    _pageNo = 1;
    _pageCount = 1;
    _emit();
  }

  // ---------------------------------------------------------------- 历史

  Future<void> loadHistory() async {
    if (_historyLoaded) return;
    _history = await RecordRepository.loadSearchKeywords();
    _historyLoaded = true;
    _emit();
  }

  Future<void> _pushHistory(String q) async {
    final String keyword = q.trim();
    if (keyword.isEmpty) return;
    _history.remove(keyword);
    _history.insert(0, keyword);
    if (_history.length > 30) _history.removeRange(30, _history.length);
    await RecordRepository.saveSearchKeywords(_history);
  }

  Future<void> removeHistory(String q) async {
    _history.remove(q);
    await RecordRepository.saveSearchKeywords(_history);
    _emit();
  }

  Future<void> clearHistory() async {
    _history = <String>[];
    await RecordRepository.saveSearchKeywords(_history);
    _emit();
  }

  // ---------------------------------------------------------------- 搜索

  Future<void> search({
    required String keyword,
    required VodSource? active,
    required List<VodSource> all,
    bool multiSource = false,
    int pageNo = 1,
  }) async {
    final String q = keyword.trim();
    if (q.isEmpty) return;
    if (active == null && all.isEmpty) {
      _error = '请先添加并启用一个资源站';
      _emit();
      return;
    }

    _query = q;
    _multiSource = multiSource;
    _loading = true;
    _error = null;
    if (pageNo <= 1) {
      _items = <VodItem>[];
      _itemSource.clear();
    }
    _emit();

    try {
      if (multiSource && all.length > 1) {
        await _searchMulti(q: q, sources: all, pageNo: pageNo);
      } else {
        final VodSource source = active ?? all.first;
        await _searchSingle(q: q, source: source, pageNo: pageNo);
      }
      if (pageNo <= 1) await _pushHistory(q);
    } on Object catch (e) {
      AppLog.e('Search', 'failed: $e');
      _error = e.toString();
    } finally {
      _loading = false;
      _emit();
    }
  }

  Future<void> loadMore({
    required VodSource? active,
    required List<VodSource> all,
  }) async {
    if (_loading || !canLoadMore || _query.isEmpty) return;
    await search(
      keyword: _query,
      active: active,
      all: all,
      multiSource: _multiSource,
      pageNo: _pageNo + 1,
    );
  }

  Future<void> _searchSingle({
    required String q,
    required VodSource source,
    required int pageNo,
  }) async {
    final VodPage page = await VodRepository.instance.query(
      source: source,
      pageNo: pageNo,
      keyword: q,
      detail: true,
      force: pageNo <= 1,
    );
    final List<VodItem> incoming = page.items;
    for (final VodItem item in incoming) {
      _itemSource[_itemKey(item)] = source;
    }
    _items = pageNo <= 1 ? incoming : <VodItem>[..._items, ...incoming];
    _pageNo = page.page;
    _pageCount = page.pageCount;
  }

  Future<void> _searchMulti({
    required String q,
    required List<VodSource> sources,
    required int pageNo,
  }) async {
    // 单个源失败不应让整次搜索失败，逐个兜底成空页。
    final List<Future<VodPage>> futures = sources.map((VodSource s) async {
      try {
        return await VodRepository.instance.query(
          source: s,
          pageNo: pageNo,
          keyword: q,
          detail: true,
        );
      } on Object {
        return VodPage.empty();
      }
    }).toList();

    final List<VodPage> pages = await Future.wait(futures);

    final Map<String, VodItem> merged = pageNo <= 1
        ? <String, VodItem>{}
        : <String, VodItem>{
            for (final VodItem e in _items) '${e.id}|${e.name}': e,
          };

    int maxPage = 1;
    for (int i = 0; i < pages.length; i++) {
      final VodPage page = pages[i];
      if (page.pageCount > maxPage) maxPage = page.pageCount;
      for (final VodItem item in page.items) {
        final String key = _itemKey(item);
        merged[key] ??= item;
        _itemSource[key] = sources[i];
      }
    }

    _items = merged.values.toList();
    _pageNo = pageNo;
    _pageCount = maxPage;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
