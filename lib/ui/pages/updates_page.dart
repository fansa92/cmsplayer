import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatter.dart';
import '../../data/models/favorite_item.dart';
import '../../data/models/vod_source.dart';
import '../../state/favorites_store.dart';
import '../../state/source_store.dart';
import '../actions.dart';
import '../widgets/cached_image.dart';
import '../widgets/empty_state.dart';

/// 追剧更新中心。
///
/// 收藏页的「有更新 N」筛选只能看卡片角标，这里把「哪部、从几集到几集、
/// 属于哪个源、多久前查的」摊开，适合一次追很多部的时候扫一眼。
class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    final FavoritesStore favorites = context.watch<FavoritesStore>();
    if (favorites.loading) return;
    _requested = true;
    final List<VodSource> sources = context.read<SourceStore>().sources;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) favorites.checkUpdates(sources: sources);
    });
  }

  @override
  Widget build(BuildContext context) {
    final FavoritesStore favorites = context.watch<FavoritesStore>();
    final SourceStore sourceStore = context.watch<SourceStore>();

    final List<FavoriteItem> updated = favorites.items
        .where((FavoriteItem e) => favorites.hasUpdate(e.key))
        .toList()
      ..sort((FavoriteItem a, FavoriteItem b) {
        final int da = (favorites.latestEpisodesOf(a.key) ?? a.episodes) -
            a.episodes;
        final int db = (favorites.latestEpisodesOf(b.key) ?? b.episodes) -
            b.episodes;
        return db.compareTo(da);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('追剧更新'),
        actions: <Widget>[
          if (updated.isNotEmpty)
            TextButton(
              onPressed: () async {
                for (final FavoriteItem e in List<FavoriteItem>.of(updated)) {
                  await favorites.markSeen(e.key);
                }
                if (context.mounted) AppActions.snack(context, '已全部标为已读');
              },
              child: const Text('全部已读'),
            ),
          IconButton(
            tooltip: '检查更新',
            onPressed: favorites.checking
                ? null
                : () => favorites.checkUpdates(
                      sources: sourceStore.sources,
                      force: true,
                    ),
            icon: favorites.checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: favorites.loading
          ? const Center(child: CircularProgressIndicator())
          : updated.isEmpty
              ? EmptyState(
                  icon: Icons.notifications_none,
                  title: '暂时没有新集',
                  subtitle: favorites.lastCheckAt == null
                      ? '点右上角刷新，检查收藏里有没有更新。'
                      : '上次检查于 ${formatRelativeTime(favorites.lastCheckAt!)}，'
                          '有新集时会出现在这里。',
                )
              : Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '${updated.length} 部有更新',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (favorites.lastCheckAt != null)
                            Text(
                              '检查于 ${formatRelativeTime(favorites.lastCheckAt!)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: updated.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 4),
                        itemBuilder: (BuildContext ctx, int i) {
                          final FavoriteItem fav = updated[i];
                          return _UpdateRow(
                            favorite: fav,
                            latest: favorites.latestEpisodesOf(fav.key),
                            source: _sourceById(sourceStore, fav.sourceId),
                            onTap: () => _open(favorites, sourceStore, fav),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Future<void> _open(
    FavoritesStore favorites,
    SourceStore sourceStore,
    FavoriteItem fav,
  ) async {
    final VodSource? source = _sourceById(sourceStore, fav.sourceId);
    if (source == null) {
      AppActions.snack(context, '对应的资源站已被删除');
      return;
    }
    await favorites.markSeen(fav.key);
    if (!mounted) return;
    await AppActions.openMinimalItem(
      context,
      source: source,
      vodId: int.tryParse(fav.vodId) ?? 0,
      vodName: fav.vodName,
      vodPic: fav.vodPic,
    );
  }

  static VodSource? _sourceById(SourceStore store, String sourceId) {
    for (final VodSource s in store.sources) {
      if (s.id == sourceId) return s;
    }
    return null;
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({
    required this.favorite,
    required this.latest,
    required this.source,
    required this.onTap,
  });

  final FavoriteItem favorite;
  final int? latest;
  final VodSource? source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int from = favorite.episodes;
    final int to = latest ?? from;
    final int added = to - from;
    final String progress = from > 0 && to > from
        ? '$from → $to 集'
        : (to > 0 ? '共 $to 集' : '有更新');

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 46,
                  height: 64,
                  child: CachedImage(
                    url: favorite.vodPic,
                    headers: source?.headers ?? const <String, String>{},
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      favorite.vodName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progress,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        if (source != null) source!.name,
                        if (added > 0) '新增 $added 集',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
