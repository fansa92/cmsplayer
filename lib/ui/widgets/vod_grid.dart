import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/utils/responsive.dart';
import '../../data/models/vod_item.dart';
import 'vod_card.dart';

/// 海报网格 + 无限滚动加载。
class VodGrid extends StatefulWidget {
  const VodGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.headers = const <String, String>{},
    this.onLoadMore,
    this.canLoadMore = false,
    this.loadingMore = false,
    this.progressOf,
    this.sourceLabelOf,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
    this.header,
  });

  final List<VodItem> items;
  final void Function(VodItem item) onTap;
  final Map<String, String> headers;
  final Future<void> Function()? onLoadMore;
  final bool canLoadMore;
  final bool loadingMore;
  final double Function(VodItem item)? progressOf;
  final String Function(VodItem item)? sourceLabelOf;
  final EdgeInsets padding;

  /// 网格上方的附加内容（例如首页的「继续观看」横条）。
  ///
  /// 给了它就会改用 CustomScrollView 承载，这样它跟着内容一起滚走；
  /// 留在外层固定区的话会一直占着屏幕高度，首页首屏就被吃掉了。
  final Widget? header;

  @override
  State<VodGrid> createState() => _VodGridState();
}

class _VodGridState extends State<VodGrid> {
  /// 一次只放一个 loadMore 在飞。
  ///
  /// 原来每收到一个滚动通知都判断一次 `pixels >= maxScrollExtent - 300`，
  /// 而父级 store 的 `loadingMore` 是在 `await` 之后才置位的，中间那一两帧里
  /// 连续几个 ScrollUpdateNotification 会把同一页请求打好几次，结果列表里
  /// 出现重复影片。这里在组件侧自己加一道闸。
  bool _loadRequested = false;

  void _requestLoadMore() {
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

  void _maybeLoadMore(ScrollNotification notification) {
    // 首页「继续观看」是横向列表，它的滚动通知也会冒泡到这里 ——
    // 只看主轴，免得划一下横条就误触发翻页。
    if (notification.metrics.axis != Axis.vertical) return;
    if (notification is! ScrollUpdateNotification &&
        notification is! OverscrollNotification) {
      return;
    }
    // extentAfter 是「还剩多少能滚」，比 pixels/maxScrollExtent 更直接；
    // 内容不满一屏时它是 0，正好自动把首屏补满。
    if (notification.metrics.extentAfter > 300) return;
    _requestLoadMore();
  }

  @override
  Widget build(BuildContext context) {
    final int columns = context.gridColumns;
    final Widget? header = widget.header;

    final SliverGridDelegate delegate =
        SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: 16,
      crossAxisSpacing: 12,
      childAspectRatio: 0.62,
    );
    final bool showFooter = widget.canLoadMore && widget.onLoadMore != null;
    final int itemCount = widget.items.length + (showFooter ? 1 : 0);

    Widget itemBuilder(BuildContext context, int index) {
      if (index >= widget.items.length) {
        return Center(
          child: widget.loadingMore
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: '加载更多',
                  onPressed: _requestLoadMore,
                  icon: const Icon(Icons.expand_more),
                ),
        );
      }
      final VodItem item = widget.items[index];
      return VodCard(
        item: item,
        headers: widget.headers,
        onTap: () => widget.onTap(item),
        progress: widget.progressOf == null ? 0 : widget.progressOf!(item),
        sourceLabel:
            widget.sourceLabelOf == null ? null : widget.sourceLabelOf!(item),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        _maybeLoadMore(notification);
        return false;
      },
      child: header == null
          ? GridView.builder(
              padding: widget.padding,
              scrollCacheExtent: const ScrollCacheExtent.pixels(600),
              gridDelegate: delegate,
              itemCount: itemCount,
              itemBuilder: itemBuilder,
            )
          : CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(child: header),
                SliverPadding(
                  padding: widget.padding,
                  sliver: SliverGrid.builder(
                    gridDelegate: delegate,
                    itemCount: itemCount,
                    itemBuilder: itemBuilder,
                  ),
                ),
              ],
            ),
    );
  }
}

/// 横向滚动的一行海报（首页推荐位用）。
class VodRow extends StatelessWidget {
  const VodRow({
    super.key,
    required this.items,
    required this.onTap,
    this.headers = const <String, String>{},
    this.itemWidth = 120,
  });

  final List<VodItem> items;
  final void Function(VodItem item) onTap;
  final Map<String, String> headers;
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: itemWidth / 0.62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (BuildContext context, int index) {
          final VodItem item = items[index];
          return SizedBox(
            width: itemWidth,
            child: VodCard(
              item: item,
              headers: headers,
              onTap: () => onTap(item),
            ),
          );
        },
      ),
    );
  }
}
