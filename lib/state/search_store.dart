import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import '../core/utils/title_match.dart';
import '../data/models/paged_result.dart';
import '../data/models/vod_item.dart';
import '../data/models/vod_source.dart';
import '../data/repository/record_repository.dart';
import '../data/repository/vod_repository.dart';

/// 一个源在本轮搜索里命中了哪些条目。
///
/// 聚合视图只留"代表条目"，看不出哪个站收录得全；按源分组时要用原始的
/// 逐源结果，所以另外存一份。
class SourceHit {
  const SourceHit({required this.source, required this.items});

  final VodSource source;
  final List<VodItem> items;
}

/// 搜索状态。支持单源搜索与多源并发搜索。
class SearchStore extends ChangeNotifier {
  String _query = '';
  List<VodItem> _items = <VodItem>[];

  /// 聚合键 → 出现过的源。多源搜索时同一个片名会命中多个源，界面只显示
  /// 一条，但要能说清「这条结果有哪几个源有」。
  final Map<String, List<VodSource>> _groupSources =
      <String, List<VodSource>>{};
  bool _loading = false;
  String? _error;
  int _pageNo = 1;
  int _pageCount = 1;
  bool _multiSource = false;
  List<String> _history = <String>[];
  List<String> _suggestions = <String>[];

  /// 每个源本轮命中的原始条目（按源分组用）。
  final Map<String, List<VodItem>> _bySource = <String, List<VodItem>>{};
  final Map<String, VodSource> _sourceById = <String, VodSource>{};

  /// 是否只保留片名完全一致的结果。
  bool _exact = false;

  /// 结果是否按源分组展示。
  bool _groupBySource = false;

  /// 最近一次联想请求的令牌，防止慢回来的旧结果盖掉新输入的结果。
  String _suggestToken = '';
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
  List<String> get suggestions => _suggestions;
  bool get exact => _exact;
  bool get groupBySource => _groupBySource;

  /// 逐源命中的结果，条数多的排前面。
  List<SourceHit> get sourceHits {
    final List<SourceHit> hits = <SourceHit>[];
    _bySource.forEach((String id, List<VodItem> items) {
      final VodSource? source = _sourceById[id];
      if (source == null || items.isEmpty) return;
      hits.add(SourceHit(source: source, items: List<VodItem>.unmodifiable(items)));
    });
    hits.sort((SourceHit a, SourceHit b) {
      final int byCount = b.items.length.compareTo(a.items.length);
      if (byCount != 0) return byCount;
      return a.source.name.compareTo(b.source.name);
    });
    return hits;
  }

  /// 结果条目所属的源（多源搜索时用于展示来源标签）。
  ///
  /// 聚合后一条结果可能对应多个源，这里给的是「代表条目」所在的源。
  VodSource? sourceOf(VodItem item) {
    final List<VodSource>? list = _groupSources[_groupKey(item)];
    if (list == null || list.isEmpty) return null;
    return list.first;
  }

  /// 这条结果命中过多少个源。1 表示只有当前源有。
  int sourceCountOf(VodItem item) =>
      _groupSources[_groupKey(item)]?.length ?? 0;

  /// 所有结果的来源列表分组，供调试与测试观察。
  @visibleForTesting
  Map<String, List<VodSource>> get groupSources =>
      Map<String, List<VodSource>>.unmodifiable(_groupSources);

  static String _groupKey(VodItem item) =>
      '${_normalizeName(item.name)}|${item.year.trim()}';

  /// 归一化片名，用于跨源聚合。
  ///
  /// 同一部片在不同源里的名字常带尾巴：全角空格、`(2024)`、「国语版」。
  /// 只做低成本的收敛，不碰繁简转换（要一张对照表，收益也不够明显）。
  static String _normalizeName(String raw) {
    String s = raw.toLowerCase();
    s = s.replaceAll(RegExp(r'[\s\u3000]+'), '');
    s = s.replaceAll(RegExp(r'[\(（\[【][^\)）\]】]*[\)）\]】]'), '');
    s = s.replaceAll(
      RegExp(r'(国语|粤语|英语|日语|韩语|中字|高清|蓝光|完整|未删减)(版)?$'),
      '',
    );
    s = s.replaceAll(RegExp(r'(hd|bd|tc|web-dl)$'), '');
    return s;
  }

  /// 同一部片在多个源里出现时，选哪条当代表。
  ///
  /// 有播放地址 > 集数多，剩下的交给先后顺序（即 `all` 里的源顺序）。
  static bool _preferOver(VodItem candidate, VodItem current) {
    if (candidate.hasPlayInfo != current.hasPlayInfo) {
      return candidate.hasPlayInfo;
    }
    return candidate.episodeCount > current.episodeCount;
  }

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  void setMultiSource(bool value) {
    if (_multiSource == value) return;
    _multiSource = value;
    _emit();
  }

  void setExact(bool value) {
    if (_exact == value) return;
    _exact = value;
    _emit();
  }

  void setGroupBySource(bool value) {
    if (_groupBySource == value) return;
    _groupBySource = value;
    _emit();
  }

  void clearResult() {
    _query = '';
    _items = <VodItem>[];
    _groupSources.clear();
    _bySource.clear();
    _sourceById.clear();
    _suggestions = <String>[];
    _suggestToken = '';
    _error = null;
    _pageNo = 1;
    _pageCount = 1;
    _emit();
  }

  // ---------------------------------------------------------------- 联想词

  void clearSuggestions() {
    if (_suggestions.isEmpty && _suggestToken.isEmpty) return;
    _suggestions = <String>[];
    _suggestToken = '';
    _emit();
  }

  /// 拉一批联想词。失败一律静默：联想不出来不该让搜索框报错。
  ///
  /// 去抖放在页面层；这里的令牌负责挡住「输入 A 的慢请求回来时用户已经
  /// 敲到 ABC」这类乱序，避免展示一串和当前输入无关的词。
  Future<void> suggest(String keyword, VodSource? source) async {
    final String q = keyword.trim();
    if (q.isEmpty || source == null) {
      clearSuggestions();
      return;
    }
    final String token = '${source.id}|$q';
    _suggestToken = token;
    List<String> words = <String>[];
    try {
      words = await VodRepository.instance.suggest(source: source, keyword: q);
    } on Object catch (e) {
      AppLog.d('Search', 'suggest failed: $e');
    }
    if (_disposed || _suggestToken != token) return;
    _suggestions = words;
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
    bool exact = false,
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
    _exact = exact;
    _loading = true;
    _error = null;
    // 已经按回车搜索了，联想条就该收起来；同时让在途的联想请求失效。
    _suggestions = <String>[];
    _suggestToken = '$q|submitted';
    if (pageNo <= 1) {
      _items = <VodItem>[];
      _groupSources.clear();
      _bySource.clear();
      _sourceById.clear();
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
      exact: _exact,
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
    _mergeIncoming(page.items, source, exact: _exact, query: q);
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

    int maxPage = 1;
    for (int i = 0; i < pages.length; i++) {
      final VodPage page = pages[i];
      if (page.pageCount > maxPage) maxPage = page.pageCount;
      _mergeIncoming(page.items, sources[i], exact: _exact, query: q);
    }

    _pageNo = pageNo;
    _pageCount = maxPage;
  }

  /// 把一批结果并进当前列表，按「规范片名 + 年代」聚合。
  ///
  /// 原来的键是 `id|name`，而同一部片在不同资源站的 id 完全不同，多源搜索
  /// 时一部片会并排出现三四条。现在同名的只留一条，并把命中的源记下来，
  /// 界面上标「共 N 个源」。
  void _mergeIncoming(
    List<VodItem> incoming,
    VodSource source, {
    required bool exact,
    required String query,
  }) {
    final Map<String, int> index = <String, int>{
      for (int i = 0; i < _items.length; i++) _groupKey(_items[i]): i,
    };
    final String wanted = normalizeTitle(query);

    for (final VodItem item in incoming) {
      // 精确模式：片名归一化后必须完全相等才算命中。
      // 资源站的 `wd` 是模糊匹配，只靠它做不到"只要这一部"。
      if (exact && normalizeTitle(item.name) != wanted) continue;
      _record(source, item);
      final String key = _groupKey(item);
      final int? at = index[key];
      if (at == null) {
        index[key] = _items.length;
        _items.add(item);
        _groupSources[key] = <VodSource>[source];
        continue;
      }

      final List<VodSource> owners = _groupSources.putIfAbsent(
        key,
        () => <VodSource>[],
      );
      final bool known =
          owners.any((VodSource e) => e.id == source.id);
      if (!known) owners.add(source);

      // 代表条目可能换成播放信息更全的那条，但聚合键不变，位置也不动。
      if (_preferOver(item, _items[at])) {
        _items[at] = item;
        // 代表换了，把它所在的源挪到最前，[sourceOf] 返回的才和界面对得上。
        owners.removeWhere((VodSource e) => e.id == source.id);
        owners.insert(0, source);
      }
    }
  }

  /// 记一条逐源结果，按条目 ID 去重（翻页时同一条可能再回来）。
  void _record(VodSource source, VodItem item) {
    _sourceById[source.id] = source;
    final List<VodItem> list =
        _bySource.putIfAbsent(source.id, () => <VodItem>[]);
    final int at = list.indexWhere((VodItem e) => e.id == item.id);
    if (at >= 0) {
      list[at] = item;
    } else {
      list.add(item);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
