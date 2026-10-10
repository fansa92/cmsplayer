import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/vod_category.dart';
import '../../data/models/vod_item.dart';
import '../../data/models/vod_source.dart';
import '../../state/browse_store.dart';
import '../../state/history_store.dart';
import '../navigation.dart';
import '../widgets/empty_state.dart';
import '../widgets/vod_grid.dart';

/// 首页：当前资源站的推荐内容 + 快捷分类。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final BrowseStore browse = context.watch<BrowseStore>();
    final VodSource? source = browse.source;
    final HistoryStore history = context.watch<HistoryStore>();

    if (source == null) {
      return const PageLoading(label: '正在准备…');
    }

    final Map<String, String> headers = source.headers;

    if (browse.loading && browse.items.isEmpty) {
      return const PageLoading();
    }

    if (browse.error != null && browse.items.isEmpty) {
      return ErrorState(
        message: browse.error!,
        onRetry: () => browse.refresh(force: true),
      );
    }

    if (browse.items.isEmpty) {
      return EmptyState(
        icon: Icons.live_tv_outlined,
        title: '这个资源站暂时没有内容',
        subtitle: '可以切换其它资源站，或到「资源站管理」里添加新的接口。',
        actionLabel: '重新加载',
        onAction: () => browse.refresh(force: true),
      );
    }

    return RefreshIndicator(
      onRefresh: () => browse.refresh(force: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(
            title: '为你推荐',
            subtitle: '${browse.categoryTitle} · 共 ${browse.total} 部',
            onRefresh: () => browse.refresh(force: true),
          ),
          if (browse.categories.isNotEmpty)
            _CategoryChips(browse: browse),
          const SizedBox(height: 4),
          Expanded(
            child: VodGrid(
              items: browse.items,
              headers: headers,
              canLoadMore: browse.canLoadMore,
              loadingMore: browse.loadingMore,
              onLoadMore: browse.loadMore,
              progressOf: (VodItem item) => _progressOf(history, source, item),
              onTap: (VodItem item) => AppRoutes.openDetail(
                context,
                item: item,
                source: source,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _progressOf(
    HistoryStore history,
    VodSource source,
    VodItem item,
  ) {
    return history.byIds(source.id, item.id)?.progress ?? 0;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.onRefresh,
  });

  final String title;
  final String subtitle;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.browse});

  final BrowseStore browse;

  @override
  Widget build(BuildContext context) {
    final List<VodCategory> categories =
        browse.categories.take(14).toList();
    if (categories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('全部'),
              selected: browse.typeId == 0,
              onSelected: (_) => browse.selectCategory(0),
            ),
          ),
          for (final VodCategory c in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c.name),
                selected: browse.typeId == c.id,
                onSelected: (_) => browse.selectCategory(c.id),
              ),
            ),
        ],
      ),
    );
  }
}

/// 首页"最近观看"入口，供历史页复用。
class RecentlyWatchedStrip extends StatelessWidget {
  const RecentlyWatchedStrip({super.key, required this.onOpen});

  final void Function() onOpen;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.history),
      title: const Text('继续观看'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onOpen,
    );
  }
}
