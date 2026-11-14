import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/vod_item.dart';
import '../../data/models/vod_source.dart';
import '../../state/source_compare_store.dart';
import '../../state/source_store.dart';
import '../navigation.dart';
import '../widgets/empty_state.dart';

/// 全源对比面板。
///
/// 一部片在一个源里有、另一个源里没有，或者一边 13 集一边 10 集 —— 这些
/// 差异在普通的搜索页里被「合并去重」抹平了。这个页面反过来，把每个源
/// 各查一遍后**并排**摆出来，谁集数全、谁更新得快、谁的播放地址真的能用，
/// 一眼就能看出来。
class SourceComparePage extends StatefulWidget {
  const SourceComparePage({
    super.key,
    required this.title,
    this.year = '',
    this.store,
  });

  /// 要比对的片名。
  final String title;

  /// 年代。源里普遍不填，填了的话用来排除同名翻拍。
  final String year;

  /// 状态容器（测试注入点）；为 null 时页面自己建一个。
  final SourceCompareStore? store;

  @override
  State<SourceComparePage> createState() => _SourceComparePageState();
}

class _SourceComparePageState extends State<SourceComparePage> {
  late final SourceCompareStore _store = widget.store ?? SourceCompareStore();
  late final bool _ownsStore = widget.store == null;

  @override
  void initState() {
    super.initState();
    final List<VodSource> sources = context.read<SourceStore>().enabledSources;
    // 一个源无从对比，页面会直接显示引导，不必白打一轮请求。
    if (sources.length < 2) return;
    unawaited(_store.compare(
      title: widget.title,
      year: widget.year,
      sources: sources,
    ));
  }

  @override
  void dispose() {
    if (_ownsStore) _store.dispose();
    super.dispose();
  }

  Future<void> _restart() async {
    final List<VodSource> sources = context.read<SourceStore>().enabledSources;
    if (sources.length < 2) return;
    await _store.compare(
      title: widget.title,
      year: widget.year,
      sources: sources,
    );
  }

  void _open(CompareEntry entry) {
    final VodItem? item = entry.item;
    if (item == null) return;
    AppRoutes.openDetail(context, item: item, source: entry.source);
  }

  @override
  Widget build(BuildContext context) {
    final SourceStore sources = context.watch<SourceStore>();

    if (sources.enabledSources.length < 2) {
      return Scaffold(
        appBar: AppBar(title: const Text('全源对比')),
        body: const EmptyState(
          icon: Icons.compare_arrows,
          title: '至少需要两个启用的资源站',
          subtitle: '全源对比用来比较同一部片在不同源里的集数与播放地址，'
              '先到资源站管理里启用更多源。',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('全源对比'),
        actions: <Widget>[
          IconButton(
            tooltip: '重新对比',
            onPressed: _store.running ? null : _restart,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (BuildContext context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<CompareEntry> entries = _store.entries;

    if (entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final CompareEntry? best = _store.best;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: <Widget>[
        Text(
          _store.title.isEmpty ? widget.title : _store.title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _store.running
              ? '正在 ${entries.length} 个源里查找…'
              : '${entries.length} 个源 · ${_store.foundCount} 个有资源 · '
                  '${_store.playableCount} 个可播放',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (_store.running)
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: const LinearProgressIndicator(minHeight: 3),
          )
        else if (best != null)
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.play_circle_outline, size: 20),
            label: Text(
              '打开「${best.source.name}」· ${best.episodeCount} 集',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () => _open(best),
          ),
        const SizedBox(height: 14),
        for (final CompareEntry entry in entries)
          _CompareCard(
            entry: entry,
            isBest: best != null && identical(best, entry),
            onTap: entry.found ? () => _open(entry) : null,
          ),
        const SizedBox(height: 8),
        Text(
          '只对比已启用的资源站；结果不做缓存，每次打开都会重新查。',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({
    required this.entry,
    required this.isBest,
    this.onTap,
  });

  final CompareEntry entry;
  final bool isBest;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color dotColor = switch (entry.status) {
      CompareStatus.found => entry.playable
          ? AppTheme.successOn(theme.brightness)
          : theme.colorScheme.tertiary,
      CompareStatus.missing => theme.colorScheme.outline,
      CompareStatus.failed => theme.colorScheme.error,
      _ => theme.colorScheme.primary,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.source.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isBest)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _Tag(
                          text: '集数最多',
                          background: theme.colorScheme.primaryContainer,
                          foreground: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    _StatusChip(entry: entry),
                  ],
                ),
                if (entry.found) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      _Tag(
                        text: '${entry.episodeCount} 集',
                        background: theme.colorScheme.surfaceContainerHighest,
                        foreground: theme.colorScheme.onSurface,
                      ),
                      if (entry.lineCount > 0)
                        _Tag(
                          text: '${entry.lineCount} 条线路',
                          background: theme.colorScheme.surfaceContainerHighest,
                          foreground: theme.colorScheme.onSurfaceVariant,
                        ),
                      if (entry.remarks.isNotEmpty)
                        _Tag(
                          text: entry.remarks,
                          background: theme.colorScheme.surfaceContainerHighest,
                          foreground: theme.colorScheme.onSurfaceVariant,
                        ),
                      if ((entry.item?.scoreLabel ?? '').isNotEmpty)
                        _Tag(
                          text: '评分 ${entry.item!.scoreLabel}',
                          background: theme.colorScheme.surfaceContainerHighest,
                          foreground: theme.colorScheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    <String>[
                      if (entry.latencyMs > 0) '${entry.latencyMs} ms',
                      entry.source.origin.replaceFirst('https://', ''),
                      if (!entry.playable) '该源没有返回播放地址',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    switch (entry.status) {
                      CompareStatus.failed => entry.error.isEmpty
                          ? '请求失败，可能是超时或接口已失效'
                          : entry.error,
                      CompareStatus.missing => '这个源里没有找到同名影片',
                      CompareStatus.loading => '正在搜索…',
                      _ => '排队中',
                    },
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.entry});

  final CompareEntry entry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (Color bg, Color fg) = switch (entry.status) {
      CompareStatus.found when entry.playable => (
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
        ),
      CompareStatus.found => (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
        ),
      CompareStatus.failed => (
          theme.colorScheme.errorContainer,
          theme.colorScheme.onErrorContainer,
        ),
      _ => (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (entry.status == CompareStatus.loading ||
              entry.status == CompareStatus.pending) ...<Widget>[
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            entry.statusLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
            ),
      ),
    );
  }
}
