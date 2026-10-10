import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatter.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/play_record.dart';
import '../../data/models/vod_source.dart';
import '../../state/history_store.dart';
import '../../state/source_store.dart';
import '../actions.dart';
import '../widgets/empty_state.dart';
import '../widgets/vod_card.dart';

/// 播放历史 / 续播页。
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final HistoryStore history = context.watch<HistoryStore>();
    final SourceStore sourceStore = context.watch<SourceStore>();

    if (history.loading) return const PageLoading();

    final List<PlayRecord> records = history.records;
    if (records.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: '还没有观看记录',
        subtitle: '播放过的影片会出现在这里，并自动记住你看到的位置。',
      );
    }

    return Column(
      children: <Widget>[
        _Toolbar(count: records.length, history: history),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            scrollCacheExtent: const ScrollCacheExtent.pixels(600),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: context.gridColumns,
              mainAxisSpacing: 16,
              crossAxisSpacing: 12,
              childAspectRatio: 0.62,
            ),
            itemCount: records.length,
            itemBuilder: (BuildContext context, int index) {
              final PlayRecord record = records[index];
              final VodSource? source = _sourceOf(sourceStore, record.sourceId);
              final Map<String, String> headers = source?.headers ??
                  const <String, String>{};

              return Dismissible(
                key: ValueKey<String>(record.key),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                onDismissed: (_) => history.remove(record.key),
                child: HistoryCard(
                  pic: record.vodPic,
                  title: record.vodName,
                  subtitle: '${record.episodeLabel} · ${formatRelativeTime(record.updatedAt)}',
                  progressLabel: record.progressLabel,
                  progress: record.progress,
                  headers: headers,
                  onTap: () {
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
                  },
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
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.count, required this.history});

  final int count;
  final HistoryStore history;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
      child: Row(
        children: <Widget>[
          Text(
            '共 $count 条记录',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _confirmClear(context),
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('清空'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清空观看记录？'),
        content: const Text('将删除全部播放记录与续播进度，此操作不可撤销。'),
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
    if (ok != true || !context.mounted) return;
    await history.clear();
    if (context.mounted) AppActions.snack(context, '已清空观看记录');
  }
}
