import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/favorite_item.dart';
import '../../data/models/vod_item.dart';
import '../../data/models/vod_source.dart';
import '../../state/favorites_store.dart';
import '../../state/source_store.dart';
import '../actions.dart';
import '../widgets/empty_state.dart';
import '../widgets/vod_grid.dart';

/// 收藏页。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  bool _onlyCurrentSource = true;

  /// 只看有更新的。
  bool _onlyUpdated = false;

  /// 更新检查只在本页第一次拿到数据时触发一次。
  bool _checkRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkRequested) return;
    final FavoritesStore favorites = context.watch<FavoritesStore>();
    if (favorites.loading) return;
    _checkRequested = true;
    final List<VodSource> sources = context.read<SourceStore>().sources;
    // checkUpdates 会立刻 notify，不能在 build/didChangeDependencies 阶段同步调，
    // 推到帧尾。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) favorites.checkUpdates(sources: sources);
    });
  }

  @override
  Widget build(BuildContext context) {
    final FavoritesStore favorites = context.watch<FavoritesStore>();
    final SourceStore sourceStore = context.watch<SourceStore>();

    if (favorites.loading) return const PageLoading();

    final VodSource? active = sourceStore.active;
    final List<FavoriteItem> all = favorites.items;
    final List<FavoriteItem> scoped = _onlyCurrentSource && active != null
        ? all.where((FavoriteItem e) => e.sourceId == active.id).toList()
        : all;
    final List<FavoriteItem> visible = _onlyUpdated
        ? scoped.where((FavoriteItem e) => favorites.hasUpdate(e.key)).toList()
        : scoped;

    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.favorite_border,
        title: '还没有收藏',
        subtitle: '在详情页点一下心形按钮，就能把影片加到这里。',
      );
    }

    final Map<int, FavoriteItem> byVodId = <int, FavoriteItem>{
      for (final FavoriteItem f in visible)
        if (int.tryParse(f.vodId) != null) int.parse(f.vodId): f,
    };

    if (visible.isEmpty) {
      return Column(
        children: <Widget>[
          _Toolbar(
            total: all.length,
            updated: favorites.updatedCount,
            onlyUpdated: _onlyUpdated,
            onlyCurrentSource: _onlyCurrentSource,
            checking: favorites.checking,
            onChanged: (bool v) => setState(() => _onlyCurrentSource = v),
            onOnlyUpdated: (bool v) => setState(() => _onlyUpdated = v),
            onCheck: () => favorites.checkUpdates(
              sources: sourceStore.sources,
              force: true,
            ),
            onClear: () => _confirmClear(context, favorites, all.length),
          ),
          Expanded(
            child: EmptyState(
              icon: _onlyUpdated
                  ? Icons.check_circle_outline
                  : Icons.favorite_border,
              title: _onlyUpdated ? '没有需要追的更新' : '当前资源站没有收藏',
              subtitle: _onlyUpdated
                  ? '关掉「有更新」筛选，可以看到全部收藏。'
                  : '关掉上面的筛选开关，可以查看其它源的收藏。',
            ),
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        _Toolbar(
          total: all.length,
          updated: favorites.updatedCount,
          onlyUpdated: _onlyUpdated,
          onlyCurrentSource: _onlyCurrentSource,
          checking: favorites.checking,
          onChanged: (bool v) => setState(() => _onlyCurrentSource = v),
          onOnlyUpdated: (bool v) => setState(() => _onlyUpdated = v),
          onCheck: () => favorites.checkUpdates(
            sources: sourceStore.sources,
            force: true,
          ),
          onClear: () => _confirmClear(context, favorites, all.length),
        ),
        Expanded(
          child: VodGrid(
            items: visible.map(_toItem).toList(),
            sourceLabelOf: (VodItem item) =>
                _sourceNameOf(sourceStore, byVodId[item.id]?.sourceId ?? ''),
            updateLabelOf: (VodItem item) {
              final FavoriteItem? fav = byVodId[item.id];
              if (fav == null || !favorites.hasUpdate(fav.key)) return null;
              final int? latest = favorites.latestEpisodesOf(fav.key);
              return latest == null ? '有更新' : '更新至 $latest 集';
            },
            onTap: (VodItem item) async {
              final FavoriteItem? fav = byVodId[item.id];
              final VodSource? source =
                  fav == null ? null : _sourceById(sourceStore, fav.sourceId);
              if (source == null) {
                AppActions.snack(context, '对应的资源站已被删除');
                return;
              }
              if (fav != null) {
                // 点开就算看过了：基线推进到最新集数，角标消失。
                await favorites.markSeen(fav.key);
              }
              if (!context.mounted) return;
              AppActions.openMinimalItem(
                context,
                source: source,
                vodId: item.id,
                vodName: item.name,
                vodPic: item.pic,
              );
            },
          ),
        ),
      ],
    );
  }

  VodItem _toItem(FavoriteItem f) {
    return VodItem(
      id: int.tryParse(f.vodId) ?? 0,
      name: f.vodName,
      pic: f.vodPic,
      typeName: f.typeName,
      remarks: f.remarks,
    );
  }

  VodSource? _sourceById(SourceStore store, String sourceId) {
    for (final VodSource s in store.sources) {
      if (s.id == sourceId) return s;
    }
    return null;
  }

  String _sourceNameOf(SourceStore store, String sourceId) =>
      _sourceById(store, sourceId)?.name ?? '';

  Future<void> _confirmClear(
    BuildContext context,
    FavoritesStore favorites,
    int count,
  ) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清空收藏？'),
        content: Text('将清空全部 $count 条收藏记录，此操作不可撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await favorites.clear();
    if (context.mounted) AppActions.snack(context, '已清空收藏');
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.total,
    required this.updated,
    required this.onlyUpdated,
    required this.onlyCurrentSource,
    required this.checking,
    required this.onChanged,
    required this.onOnlyUpdated,
    required this.onCheck,
    required this.onClear,
  });

  final int total;
  final int updated;
  final bool onlyUpdated;
  final bool onlyCurrentSource;
  final bool checking;
  final ValueChanged<bool> onChanged;
  final ValueChanged<bool> onOnlyUpdated;
  final VoidCallback onCheck;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  updated > 0 ? '共 $total 部 · $updated 部有更新' : '共 $total 部',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: '检查更新',
                visualDensity: VisualDensity.compact,
                onPressed: checking ? null : onCheck,
                icon: checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, size: 20),
              ),
              IconButton(
                tooltip: '清空收藏',
                visualDensity: VisualDensity.compact,
                onPressed: onClear,
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: <Widget>[
              FilterChip(
                label: const Text('仅当前源'),
                selected: onlyCurrentSource,
                onSelected: onChanged,
              ),
              if (updated > 0)
                FilterChip(
                  label: Text('有更新 $updated'),
                  selected: onlyUpdated,
                  onSelected: onOnlyUpdated,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
