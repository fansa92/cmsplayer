import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/responsive.dart';
import '../../data/models/play_record.dart';
import '../../data/models/vod_category.dart';
import '../../data/models/vod_item.dart';
import '../../data/models/vod_source.dart';
import '../../state/browse_store.dart';
import '../../state/history_store.dart';
import '../../state/source_store.dart';
import '../actions.dart';
import '../navigation.dart';
import '../shell/app_shell.dart';
import '../widgets/empty_state.dart';
import '../widgets/poster_skeleton.dart';
import '../widgets/vod_card.dart';
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

    // 只有冷启动（既没有内容、分类条也还不存在）才整页加载。切分类时
    // 必须保留头部与分类条：整页换成加载态会把横向滚动的分类条卸掉，
    // 加载完重建后滚动位置归零，选中靠后的分类就会"跳回"最前面几个。
    if (browse.loading &&
        browse.items.isEmpty &&
        browse.selectableCategories.isEmpty) {
      return const PosterGridSkeleton();
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
          if (browse.selectableCategories.isNotEmpty)
            _CategoryChips(browse: browse),
          const SizedBox(height: 4),
          Expanded(
            child: _buildBody(context, browse, source, headers, history),
          ),
        ],
      ),
    );
  }

  /// 网格区域的状态切换：加载 / 出错 / 空 / 正常。
  ///
  /// 与分类页保持一致，只换这一块，不整页替换。
  Widget _buildBody(
    BuildContext context,
    BrowseStore browse,
    VodSource source,
    Map<String, String> headers,
    HistoryStore history,
  ) {
    if (browse.loading && browse.items.isEmpty) {
      return const PosterGridSkeleton();
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

    return VodGrid(
      items: browse.items,
      headers: headers,
      canLoadMore: browse.canLoadMore,
      loadingMore: browse.loadingMore,
      onLoadMore: browse.loadMore,
      header: const ContinueWatchingStrip(),
      progressOf: (VodItem item) => _progressOf(history, source, item),
      onTap: (VodItem item) => AppRoutes.openDetail(
        context,
        item: item,
        source: source,
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
        browse.selectableCategories.take(14).toList();
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

/// 首页「继续观看」横条。
///
/// 列出最近没看完的记录，点卡片直接续播；右上角「全部」切到历史页。
///
/// 之前这里只有一个没人引用的 `RecentlyWatchedStrip` 占位（注释写着
/// "供历史页复用"，但历史页用的是网格），这次把它接成真正的横条。
class ContinueWatchingStrip extends StatelessWidget {
  const ContinueWatchingStrip({super.key});

  /// 最多显示几张卡片。
  static const int _maxItems = 12;

  @override
  Widget build(BuildContext context) {
    final HistoryStore history = context.watch<HistoryStore>();
    final SourceStore sources = context.watch<SourceStore>();

    // 已看完的不再占位置 —— "继续观看"要的是没看完的那些。
    final List<PlayRecord> pending = history.records
        .where((PlayRecord r) => !r.finished)
        .take(_maxItems)
        .toList();
    if (pending.isEmpty) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    final bool wide = context.isExpanded;
    final double cardWidth = wide ? 132 : 118;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: <Widget>[
              Text(
                '继续观看',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    ShellTabs.maybeOf(context)?.select(ShellTabs.historyIndex),
                child: const Text('全部'),
              ),
            ],
          ),
        ),
        SizedBox(
          // 卡片高 = 海报（宽 × 1.5）+ 标题 + 副标题。
          height: cardWidth * 1.5 + 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: pending.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int index) {
              final PlayRecord record = pending[index];
              final VodSource? source = _sourceOf(sources, record.sourceId);
              return SizedBox(
                width: cardWidth,
                child: HistoryCard(
                  pic: record.vodPic,
                  title: record.vodName,
                  subtitle: record.episodeLabel,
                  progressLabel: record.progressLabel,
                  progress: record.progress,
                  headers: source?.headers ?? const <String, String>{},
                  onTap: () => _resume(context, record, source),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  VodSource? _sourceOf(SourceStore store, String sourceId) {
    for (final VodSource s in store.sources) {
      if (s.id == sourceId) return s;
    }
    return null;
  }

  void _resume(BuildContext context, PlayRecord record, VodSource? source) {
    if (source == null) {
      AppActions.snack(context, '该记录所属的资源站已不存在');
      return;
    }
    AppActions.resumeFromRecord(
      context,
      source: source,
      vodId: int.tryParse(record.vodId) ?? 0,
      vodName: record.vodName,
      vodPic: record.vodPic,
      lineIndex: record.lineIndex,
      episodeIndex: record.episodeIndex,
    );
  }
}
