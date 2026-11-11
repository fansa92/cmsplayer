import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/vod_item.dart';
import '../../data/models/vod_source.dart';
import '../../state/history_store.dart';
import '../../state/rank_store.dart';
import '../../state/source_store.dart';
import '../navigation.dart';
import '../widgets/empty_state.dart';
import '../widgets/poster_skeleton.dart';
import '../widgets/vod_grid.dart';

/// 榜单页：按「最多播放 / 最高评分 / 最新更新」看当前资源站的头几名。
///
/// 独立成页的理由很简单 —— 这些排序在 macCMS 里本来就是一个 `by` 参数，
/// 之前只能藏在分类页的筛选抽屉里，顺手做成榜单几乎零成本。
class RankPage extends StatefulWidget {
  const RankPage({super.key});

  @override
  State<RankPage> createState() => _RankPageState();
}

class _RankPageState extends State<RankPage> {
  /// 当前绑定的源 id，用来判断要不要重新 attach。
  String? _sourceId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final VodSource? active = context.watch<SourceStore>().active;
    if (active == null || active.id == _sourceId) return;
    _sourceId = active.id;
    // didChangeDependencies 可能在 build 期间被调用，attach 会立刻 notify，
    // 统一推到帧尾，避免「在 build 里 setState」。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RankStore>().attach(active);
    });
  }

  @override
  Widget build(BuildContext context) {
    final RankStore rank = context.watch<RankStore>();
    final VodSource? source = rank.source;
    final HistoryStore history = context.watch<HistoryStore>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('榜单'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: () => rank.refresh(force: true),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SortBar(rank: rank, source: source),
          Expanded(
            child: _buildBody(context, rank, source, history),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    RankStore rank,
    VodSource? source,
    HistoryStore history,
  ) {
    if (source == null) return const PageLoading(label: '正在准备…');

    if (rank.loading && rank.items.isEmpty) {
      return const PosterGridSkeleton();
    }

    if (rank.error != null && rank.items.isEmpty) {
      return ErrorState(
        message: rank.error!,
        onRetry: () => rank.refresh(force: true),
      );
    }

    if (rank.items.isEmpty) {
      return EmptyState(
        icon: Icons.leaderboard_outlined,
        title: '这个榜单暂时是空的',
        subtitle: '换一种排序，或切换其它资源站再看看。',
        actionLabel: '重新加载',
        onAction: () => rank.refresh(force: true),
      );
    }

    return RefreshIndicator(
      onRefresh: () => rank.refresh(force: true),
      child: VodGrid(
        items: rank.items,
        headers: source.headers,
        canLoadMore: rank.canLoadMore,
        loadingMore: rank.loadingMore,
        onLoadMore: rank.loadMore,
        progressOf: (VodItem item) =>
            history.byIds(source.id, item.id)?.progress ?? 0,
        onTap: (VodItem item) =>
            AppRoutes.openDetail(context, item: item, source: source),
      ),
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({required this.rank, required this.source});

  final RankStore rank;
  final VodSource? source;

  static const Map<String, IconData> _icons = <String, IconData>{
    'hits': Icons.local_fire_department_outlined,
    'score': Icons.star_outline,
    'time': Icons.new_releases_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (source != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${source!.name} · ${rank.sortLabel}'
                '${rank.total > 0 ? ' · 共 ${rank.total} 部' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: RankStore.sorts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (BuildContext context, int index) {
                final String key = RankStore.sorts[index];
                return ChoiceChip(
                  avatar: Icon(
                    _icons[key] ?? Icons.list,
                    size: 18,
                  ),
                  label: Text(_labelOf(key)),
                  selected: rank.sortBy == key,
                  onSelected: (_) => rank.setSort(key),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _labelOf(String key) {
    switch (key) {
      case 'hits':
        return '最多播放';
      case 'score':
        return '最高评分';
      default:
        return '最新更新';
    }
  }
}
