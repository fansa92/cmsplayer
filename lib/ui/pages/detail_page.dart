import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/responsive.dart';
import '../../data/models/play_line.dart';
import '../../data/models/play_record.dart';
import '../../data/models/play_task.dart';
import '../../data/models/vod_item.dart';
import '../../data/models/vod_source.dart';
import '../../data/repository/vod_repository.dart';
import '../../state/favorites_store.dart';
import '../../state/history_store.dart';
import '../actions.dart';
import '../navigation.dart';
import '../widgets/cached_image.dart';

/// 详情页：影片信息 + 多线路多选集 + 收藏 + 续播。
class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.item, required this.source});

  final VodItem item;
  final VodSource source;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late VodItem _item;
  bool _loadingDetail = false;
  String? _error;
  int _lineIndex = 0;
  bool _contentExpanded = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    if (!_item.hasPlayInfo) {
      _loadDetail();
    }
  }

  Future<void> _loadDetail({bool force = false}) async {
    setState(() {
      _loadingDetail = true;
      _error = null;
    });
    try {
      final VodItem detail = await VodRepository.instance.ensureDetail(
        source: widget.source,
        item: _item,
        force: force,
      );
      if (!mounted) return;
      setState(() {
        _item = detail;
        _loadingDetail = false;
        if (!detail.hasPlayInfo) {
          _error = '该资源站没有返回播放地址';
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDetail = false;
        _error = e.toString();
      });
    }
  }

  void _play(int lineIndex, int episodeIndex) {
    final PlayTask task = PlayTask(
      source: widget.source,
      item: _item,
      lineIndex: lineIndex,
      episodeIndex: episodeIndex,
    );
    AppRoutes.openPlayer(context, task: task);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FavoritesStore favorites = context.watch<FavoritesStore>();
    final HistoryStore history = context.watch<HistoryStore>();
    final bool isFavorite = favorites.contains(widget.source.id, _item.id);
    final PlayRecord? record = history.byIds(widget.source.id, _item.id);
    final Map<String, String> headers = widget.source.headers;

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  CachedImage(url: _item.pic, headers: headers),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              child: context.useDetailTwoPane
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: 190,
                          child: _buildSide(
                            theme,
                            isFavorite,
                            favorites,
                            record,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(child: _buildMain(theme, record)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _buildMain(theme, record),
                        const SizedBox(height: 20),
                        _buildSide(theme, isFavorite, favorites, record),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 主内容

  Widget _buildMain(ThemeData theme, PlayRecord? record) {
    final List<PlayLine> lines = _item.playLines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                _item.name.isEmpty ? '未命名' : _item.name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
            if (_item.remarks.isNotEmpty) ...<Widget>[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _item.remarks,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        _MetaChips(item: _item),
        if (_item.director.isNotEmpty || _item.actor.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          if (_item.director.isNotEmpty)
            _InfoLine(label: '导演', value: _item.director),
          if (_item.actor.isNotEmpty)
            _InfoLine(label: '演员', value: _item.actor),
        ],
        if (_item.content.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _contentExpanded = !_contentExpanded),
            child: Text(
              _item.content,
              maxLines: _contentExpanded ? null : 3,
              overflow: _contentExpanded ? null : TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _contentExpanded = !_contentExpanded),
            child: Text(
              _contentExpanded ? '收起' : '展开全部',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _buildEpisodes(theme, lines, record),
        const SizedBox(height: 12),
        Text(
          '内容来自「${widget.source.name}」',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 侧栏

  Widget _buildSide(
    ThemeData theme,
    bool isFavorite,
    FavoritesStore favorites,
    PlayRecord? record,
  ) {
    final bool canResume = record != null &&
        !record.finished &&
        record.positionMs > 0 &&
        _item.hasPlayInfo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: CachedImage(
              url: _item.pic,
              headers: widget.source.headers,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 46),
            textStyle: theme.textTheme.titleSmall,
          ),
          icon: Icon(canResume ? Icons.play_arrow : Icons.movie_filter_outlined),
          label: Text(canResume ? '继续播放' : (_item.hasPlayInfo ? '立即播放' : '暂无可播放内容')),
          onPressed: _item.hasPlayInfo
              ? () {
                  final int li = canResume
                      ? _clamp(record.lineIndex, _item.playLines.length)
                      : (_lineIndex < _item.playLines.length ? _lineIndex : 0);
                  final int ei = canResume ? record.episodeIndex : 0;
                  _play(li, ei);
                }
              : null,
        ),
        if (canResume)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${record.episodeLabel} · ${record.progressLabel}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  size: 18,
                  color: isFavorite ? theme.colorScheme.error : null,
                ),
                label: Text(isFavorite ? '已收藏' : '收藏'),
                onPressed: () async {
                  final bool added = await favorites.toggle(
                    source: widget.source,
                    item: _item,
                  );
                  if (mounted) {
                    AppActions.snack(
                      context,
                      added ? '已加入收藏' : '已取消收藏',
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: '重新加载详情',
              style: IconButton.styleFrom(minimumSize: const Size(42, 42)),
              onPressed:
                  _loadingDetail ? null : () => _loadDetail(force: true),
              icon: _loadingDetail
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 选集

  Widget _buildEpisodes(
    ThemeData theme,
    List<PlayLine> lines,
    PlayRecord? record,
  ) {
    if (_loadingDetail && lines.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    if (_error != null && lines.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '无法获取播放地址',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: () => _loadDetail(force: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (lines.isEmpty) return const SizedBox.shrink();

    final int lineIdx = _lineIndex.clamp(0, lines.length - 1);
    final PlayLine line = lines[lineIdx];
    final bool resumeOnThisLine = record != null && record.lineIndex == lineIdx;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '播放线路',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (lines.length > 1)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (int i = 0; i < lines.length; i++)
                ChoiceChip(
                  label: Text('${lines[i].name} (${lines[i].episodes.length})'),
                  selected: i == lineIdx,
                  onSelected: (_) => setState(() => _lineIndex = i),
                ),
            ],
          ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Text(
              '${line.name} · 共 ${line.episodes.length} 集',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (line.episodes.length > 1)
              TextButton.icon(
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: const Text('从头播放'),
                onPressed: () => _play(lineIdx, 0),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (int i = 0; i < line.episodes.length; i++)
              _EpisodeButton(
                name: line.episodes[i].name,
                selected: resumeOnThisLine && record.episodeIndex == i,
                watched: resumeOnThisLine && i < record.episodeIndex,
                onPressed: () => _play(lineIdx, i),
              ),
          ],
        ),
      ],
    );
  }

  int _clamp(int value, int length) {
    if (length <= 0) return 0;
    return value < 0 ? 0 : (value >= length ? length - 1 : value);
  }
}

// ---------------------------------------------------------------- 子组件

class _EpisodeButton extends StatelessWidget {
  const _EpisodeButton({
    required this.name,
    required this.selected,
    required this.watched,
    required this.onPressed,
  });

  final String name;
  final bool selected;
  final bool watched;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String label = name.length > 12 ? '${name.substring(0, 12)}…' : name;

    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        foregroundColor: selected
            ? theme.colorScheme.onPrimary
            : (watched
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface),
        textStyle: theme.textTheme.labelMedium,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.item});

  final VodItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> parts = <String>[
      if (item.typeName.isNotEmpty) item.typeName,
      if (item.year.isNotEmpty) item.year,
      if (item.area.isNotEmpty) item.area,
      if (item.lang.isNotEmpty) item.lang,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: <Widget>[
        for (final String p in parts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              p,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 42,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
