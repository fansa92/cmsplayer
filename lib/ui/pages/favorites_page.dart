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

  @override
  Widget build(BuildContext context) {
    final FavoritesStore favorites = context.watch<FavoritesStore>();
    final SourceStore sourceStore = context.watch<SourceStore>();

    if (favorites.loading) return const PageLoading();

    final VodSource? active = sourceStore.active;
    final List<FavoriteItem> all = favorites.items;
    final List<FavoriteItem> visible = _onlyCurrentSource && active != null
        ? all.where((FavoriteItem e) => e.sourceId == active.id).toList()
        : all;

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
            onlyCurrentSource: _onlyCurrentSource,
            onChanged: (bool v) => setState(() => _onlyCurrentSource = v),
            onClear: () => _confirmClear(context, favorites, all.length),
          ),
          const Expanded(
            child: EmptyState(
              icon: Icons.favorite_border,
              title: '当前资源站没有收藏',
              subtitle: '关掉上面的筛选开关，可以查看其它源的收藏。',
            ),
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        _Toolbar(
          total: all.length,
          onlyCurrentSource: _onlyCurrentSource,
          onChanged: (bool v) => setState(() => _onlyCurrentSource = v),
          onClear: () => _confirmClear(context, favorites, all.length),
        ),
        Expanded(
          child: VodGrid(
            items: visible.map(_toItem).toList(),
            sourceLabelOf: (VodItem item) =>
                _sourceNameOf(sourceStore, byVodId[item.id]?.sourceId ?? ''),
            onTap: (VodItem item) {
              final FavoriteItem? fav = byVodId[item.id];
              final VodSource? source =
                  fav == null ? null : _sourceById(sourceStore, fav.sourceId);
              if (source == null) {
                AppActions.snack(context, '对应的资源站已被删除');
                return;
              }
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
    required this.onlyCurrentSource,
    required this.onChanged,
    required this.onClear,
  });

  final int total;
  final bool onlyCurrentSource;
  final ValueChanged<bool> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
      child: Row(
        children: <Widget>[
          Text(
            '共 $total 部',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          FilterChip(
            label: const Text('仅当前源'),
            selected: onlyCurrentSource,
            onSelected: onChanged,
          ),
          IconButton(
            tooltip: '清空收藏',
            visualDensity: VisualDensity.compact,
            onPressed: onClear,
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}
