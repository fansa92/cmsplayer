import 'package:flutter/material.dart';

import '../../data/models/paged_result.dart';
import '../../data/models/vod_item.dart';
import '../../data/models/vod_source.dart';
import '../../data/repository/vod_repository.dart';
import '../navigation.dart';
import '../widgets/empty_state.dart';
import '../widgets/poster_skeleton.dart';
import '../widgets/vod_grid.dart';

/// 关键词 / 分类结果页。
///
/// 详情页里点演员、点导演、点分类都走这里。**刻意不复用全局 `SearchStore`**：
/// 那是搜索 tab 的状态，从详情页跳出去再回来会把用户原来的搜索结果顶掉，
/// 点两次「返回」还会看到一串互相覆盖的历史。这里自己维护一份一次性结果，
/// 退出即销毁，互不干扰。
///
/// 两种条件二选一：给 [keyword] 走 `wd` 搜索，给 [typeId] 走分类浏览。
class KeywordPage extends StatefulWidget {
  const KeywordPage({
    super.key,
    required this.source,
    required this.title,
    this.keyword,
    this.typeId = 0,
  }) : assert(
          keyword != null || typeId > 0,
          'keyword 与 typeId 至少要给一个',
        );

  final VodSource source;

  /// 顶栏标题，通常是演员名或分类名。
  final String title;

  final String? keyword;
  final int typeId;

  @override
  State<KeywordPage> createState() => _KeywordPageState();
}

class _KeywordPageState extends State<KeywordPage> {
  List<VodItem> _items = <VodItem>[];
  int _pageNo = 1;
  int _pageCount = 1;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  Future<void> _load(int pageNo, {bool force = false}) async {
    if (_loading || _loadingMore) return;
    setState(() {
      if (pageNo <= 1) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final VodPage page = await VodRepository.instance.query(
        source: widget.source,
        pageNo: pageNo,
        keyword: widget.keyword,
        typeId: widget.typeId,
        detail: true,
        force: force,
      );
      if (!mounted) return;
      setState(() {
        _items = pageNo <= 1 ? page.items : <VodItem>[..._items, ...page.items];
        _pageNo = page.page;
        _pageCount = page.pageCount;
        _total = page.total;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canLoadMore = _pageNo < _pageCount;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_total > 0)
              Text(
                '${widget.source.name} · 共 $_total 部',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: () => _load(1, force: true),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(canLoadMore),
    );
  }

  Widget _buildBody(bool canLoadMore) {
    if (_loading && _items.isEmpty) return const PosterGridSkeleton();

    if (_error != null && _items.isEmpty) {
      return ErrorState(
        message: _error!,
        onRetry: () => _load(1, force: true),
      );
    }

    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: '没有找到相关内容',
        subtitle: widget.keyword == null
            ? '这个分类下暂时没有影片，换个分类再看看。'
            : '「${widget.keyword}」在 ${widget.source.name} 里没有结果。',
        actionLabel: '重新加载',
        onAction: () => _load(1, force: true),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(1, force: true),
      child: VodGrid(
        items: _items,
        headers: widget.source.headers,
        canLoadMore: canLoadMore,
        loadingMore: _loadingMore,
        onLoadMore: () => _load(_pageNo + 1),
        onTap: (VodItem item) => AppRoutes.openDetail(
          context,
          item: item,
          source: widget.source,
        ),
      ),
    );
  }
}
