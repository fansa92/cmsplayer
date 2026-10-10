import 'vod_category.dart';
import 'vod_item.dart';

/// 一页结果。
class PagedResult<T> {
  const PagedResult({
    required this.items,
    this.page = 1,
    this.pageCount = 1,
    this.total = 0,
  });

  final List<T> items;
  final int page;
  final int pageCount;
  final int total;

  bool get hasNext => page < pageCount;
  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  PagedResult<T> merge(PagedResult<T> next) => PagedResult<T>(
        items: <T>[...items, ...next.items],
        page: next.page,
        pageCount: next.pageCount,
        total: next.total,
      );
}

/// 一页 VOD 结果，附带该站点的分类表。
class VodPage extends PagedResult<VodItem> {
  const VodPage({
    required super.items,
    super.page,
    super.pageCount,
    super.total,
    this.categories = const <VodCategory>[],
  });

  final List<VodCategory> categories;

  /// 空页。多源搜索时用于吞掉单个源的失败。
  static VodPage empty() => const VodPage(items: <VodItem>[]);
}
