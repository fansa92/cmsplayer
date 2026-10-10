import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/utils/responsive.dart';
import '../../data/models/vod_item.dart';
import 'vod_card.dart';

/// 海报网格 + 无限滚动加载。
class VodGrid extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final int columns = context.gridColumns;

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (!canLoadMore || loadingMore || onLoadMore == null) return false;
        final ScrollMetrics metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 300) {
          onLoadMore!();
        }
        return false;
      },
      child: GridView.builder(
        padding: padding,
        scrollCacheExtent: const ScrollCacheExtent.pixels(600),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          childAspectRatio: 0.62,
        ),
        itemCount: items.length + (canLoadMore ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (index >= items.length) {
            return Center(
              child: loadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const SizedBox.shrink(),
            );
          }
          final VodItem item = items[index];
          return VodCard(
            item: item,
            headers: headers,
            onTap: () => onTap(item),
            progress: progressOf == null ? 0 : progressOf!(item),
            sourceLabel: sourceLabelOf == null ? null : sourceLabelOf!(item),
          );
        },
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
