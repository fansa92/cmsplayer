import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import '../../state/search_store.dart';
import 'vod_card.dart';

/// 按源分组的搜索结果：每个源一个可折叠的分组标题 + 自己的海报网格。
///
/// 聚合视图会把同一部片并成一条，看不出「哪个站收录得更全」；
/// 分组视图反过来，按源各摊一摊，点标题可以收起不关心的站。
class GroupedVodGrid extends StatefulWidget {
  const GroupedVodGrid({
    super.key,
    required this.hits,
    required this.onTap,
    this.headers = const <String, String>{},
    this.onLoadMore,
    this.canLoadMore = false,
    this.loadingMore = false,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 20),
  });

  final List<SourceHit> hits;
  final void Function(SourceHit hit, int index) onTap;
  final Map<String, String> headers;
  final Future<void> Function()? onLoadMore;
  final bool canLoadMore;
  final bool loadingMore;
  final EdgeInsets padding;

  @override
  State<GroupedVodGrid> createState() => _GroupedVodGridState();
}

class _GroupedVodGridState extends State<GroupedVodGrid> {
  /// 被收起的源 ID。默认全展开 —— 收起是为了"眼不见心不烦"，
  /// 一进来就藏一半结果反而像丢了数据。
  final Set<String> _collapsed = <String>{};

  bool _loadRequested = false;

  void _toggle(String id) {
    setState(() {
      if (!_collapsed.remove(id)) _collapsed.add(id);
    });
  }

  void _maybeLoadMore(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return;
    if (notification is! ScrollUpdateNotification &&
        notification is! OverscrollNotification) {
      return;
    }
    if (notification.metrics.extentAfter > 300) return;
    if (!widget.canLoadMore || widget.loadingMore || _loadRequested) return;
    final Future<void> Function()? callback = widget.onLoadMore;
    if (callback == null) return;
    _loadRequested = true;
    try {
      callback().whenComplete(() => _loadRequested = false);
    } on Object {
      _loadRequested = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final int columns = context.gridColumns;
    final SliverGridDelegate delegate =
        SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: 16,
      crossAxisSpacing: 12,
      childAspectRatio: 0.62,
    );

    final List<Widget> slivers = <Widget>[];
    for (final SourceHit hit in widget.hits) {
      final bool collapsed = _collapsed.contains(hit.source.id);
      slivers.add(
        SliverToBoxAdapter(
          child: _GroupHeader(
            hit: hit,
            collapsed: collapsed,
            onTap: () => _toggle(hit.source.id),
          ),
        ),
      );
      if (collapsed) continue;
      slivers.add(
        SliverPadding(
          padding: widget.padding,
          sliver: SliverGrid.builder(
            gridDelegate: delegate,
            itemCount: hit.items.length,
            itemBuilder: (BuildContext context, int index) => VodCard(
              item: hit.items[index],
              headers: widget.headers,
              onTap: () => widget.onTap(hit, index),
            ),
          ),
        ),
      );
    }

    if (widget.canLoadMore && widget.onLoadMore != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 28, top: 4),
            child: Center(
              child: widget.loadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: '加载更多',
                      onPressed: () {
                        if (_loadRequested) return;
                        _loadRequested = true;
                        widget.onLoadMore!().whenComplete(
                          () => _loadRequested = false,
                        );
                      },
                      icon: const Icon(Icons.expand_more),
                    ),
            ),
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        _maybeLoadMore(notification);
        return false;
      },
      child: CustomScrollView(slivers: slivers),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.hit,
    required this.collapsed,
    required this.onTap,
  });

  final SourceHit hit;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: <Widget>[
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                hit.source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${hit.items.length} 部',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (collapsed)
              Text(
                '已收起',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
