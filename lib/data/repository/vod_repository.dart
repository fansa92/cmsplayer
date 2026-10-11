import '../../core/constants.dart';
import '../api/maccms_api.dart';
import '../models/paged_result.dart';
import '../models/vod_category.dart';
import '../models/vod_item.dart';
import '../models/vod_source.dart';

/// 带 TTL 内存缓存的 VOD 数据访问层。
///
/// 缓存只做内存级，不做磁盘缓存：资源站内容更新频繁，磁盘缓存反而容易
/// 让用户看到过期数据。刷新按钮会绕过缓存。
class VodRepository {
  VodRepository._();

  static final VodRepository instance = VodRepository._();

  final Map<String, _CacheEntry<VodPage>> _pages = <String, _CacheEntry<VodPage>>{};
  final Map<String, _CacheEntry<List<VodCategory>>> _categories =
      <String, _CacheEntry<List<VodCategory>>>{};

  // ---------------------------------------------------------------- 分类

  /// 取某站点的分类表。
  Future<List<VodCategory>> categories(VodSource source) {
    final String key = 'cat|${source.id}';
    return _memo<List<VodCategory>>(
      _categories,
      key,
      false,
      () async {
        final VodPage page =
            await MacCmsApi(source).query(pageSize: 1, detail: false);
        return page.categories;
      },
    );
  }

  Future<List<VodCategory>> refreshCategories(VodSource source) {
    final String key = 'cat|${source.id}';
    return _memo<List<VodCategory>>(
      _categories,
      key,
      true,
      () async {
        final VodPage page =
            await MacCmsApi(source).query(pageSize: 1, detail: false);
        return page.categories;
      },
    );
  }

  // ---------------------------------------------------------------- 列表

  Future<VodPage> query({
    required VodSource source,
    int pageNo = 1,
    int pageSize = K.defaultPageSize,
    int typeId = 0,
    String? keyword,
    String? year,
    String? area,
    String? lang,
    String? sortBy,
    bool detail = true,
    bool force = false,
  }) {
    final String key = _key(source, <String, Object?>{
      'pg': pageNo,
      'ps': pageSize,
      't': typeId,
      'wd': keyword,
      'year': year,
      'area': area,
      'lang': lang,
      'by': sortBy,
      'ac': detail ? 'd' : 'l',
    });

    return _memo<VodPage>(
      _pages,
      key,
      force,
      () async {
        final VodPage page = await MacCmsApi(source).query(
          page: pageNo,
          pageSize: pageSize,
          typeId: typeId,
          keyword: keyword,
          year: year,
          area: area,
          lang: lang,
          sortBy: sortBy,
          detail: detail,
        );
        _absorbCategories(source, page.categories);
        return page;
      },
    );
  }

  Future<VodPage> hot({
    required VodSource source,
    int pageNo = 1,
    int pageSize = K.defaultPageSize,
    bool force = false,
  }) {
    final String key = _key(source, <String, Object?>{
      'kind': 'hot',
      'pg': pageNo,
      'ps': pageSize,
    });
    return _memo<VodPage>(
      _pages,
      key,
      force,
      () async {
        final VodPage page = await MacCmsApi(source)
            .hot(page: pageNo, pageSize: pageSize);
        _absorbCategories(source, page.categories);
        return page;
      },
    );
  }

  /// 拉完整详情（`list` 模式返回的条目没有播放地址时用它补齐）。
  Future<VodItem> ensureDetail({
    required VodSource source,
    required VodItem item,
    bool force = false,
  }) async {
    if (item.hasPlayInfo && !force) return item;
    final String key = _key(source, <String, Object?>{'kind': 'detail', 'id': item.id});
    final _CacheEntry<VodPage>? cached = _pages[key];
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.at) < K.listCacheTtl &&
        cached.value.items.isNotEmpty) {
      return cached.value.items.first;
    }

    final VodPage page = await _memo<VodPage>(
      _pages,
      key,
      force,
      () async {
        final VodItem? detail =
            await MacCmsApi(source).detail(item.id);
        return VodPage(
          items: detail == null ? const <VodItem>[] : <VodItem>[detail],
          page: 1,
          pageCount: 1,
          total: detail == null ? 0 : 1,
        );
      },
    );

    if (page.items.isEmpty) {
      // 接口没返回详情就退化为原始条目，至少还能看到信息。
      return item;
    }
    final VodItem full = page.items.first;
    // 保留接口没给全的字段。
    return full.copyWith(
      remarks: full.remarks.isEmpty ? item.remarks : full.remarks,
    );
  }

  /// 重试当前失败的请求（清空该源的缓存）。
  void invalidateSource(String sourceId) {
    _pages.removeWhere((String k, _CacheEntry<VodPage> v) => k.startsWith('$sourceId|'));
    _categories.removeWhere((String k, _CacheEntry<List<VodCategory>> v) => k.startsWith('$sourceId|'));
  }

  void clearAll() {
    _pages.clear();
    _categories.clear();
  }

  // ---------------------------------------------------------------- 内部

  void _absorbCategories(VodSource source, List<VodCategory> cats) {
    if (cats.isEmpty) return;
    _categories['cat|${source.id}'] =
        _CacheEntry<List<VodCategory>>(cats, DateTime.now());
  }

  String _key(VodSource source, Map<String, Object?> params) {
    final StringBuffer buf = StringBuffer(source.id)..write('|');
    params.forEach((String k, Object? v) {
      if (v == null) return;
      if (v is String && v.isEmpty) return;
      buf.write('$k=$v&');
    });
    return buf.toString();
  }

  Future<T> _memo<T>(
    Map<String, _CacheEntry<T>> cache,
    String key,
    bool force,
    Future<T> Function() fetch,
  ) async {
    if (!force) {
      final _CacheEntry<T>? entry = cache[key];
      if (entry != null &&
          DateTime.now().difference(entry.at) < K.listCacheTtl) {
        return entry.value;
      }
    }
    final T value = await fetch();
    cache[key] = _CacheEntry<T>(value, DateTime.now());
    while (cache.length > K.maxCacheEntries) {
      cache.remove(cache.keys.first);
    }
    return value;
  }
}

class _CacheEntry<T> {
  const _CacheEntry(this.value, this.at);

  final T value;
  final DateTime at;
}
