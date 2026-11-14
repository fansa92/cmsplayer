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
import '../navigation.dart';
import '../widgets/empty_state.dart';
import '../widgets/vod_card.dart';

/// 播放历史 / 续播页。
///
/// 支持多选删除：长按任意卡片进入多选，或点工具栏的「多选」。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  /// 是否处于多选模式。
  bool _selecting = false;

  /// 已选记录的 `sourceId|vodId`。
  ///
  /// 只当缓存用：真正的有效选择在 [build] 里与当前记录取交集，
  /// 这样同步拉下来的删除不会留下指向已消失记录的「幽灵选中项」。
  final Set<String> _selected = <String>{};

  void _enterSelection(String key) {
    setState(() {
      _selecting = true;
      _selected.add(key);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggle(String key) {
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
    });
  }

  void _toggleAll(List<String> keys) {
    setState(() {
      final bool all = keys.every(_selected.contains);
      _selected.clear();
      if (!all) _selected.addAll(keys);
    });
  }

  Future<void> _deleteSelected(List<String> keys) async {
    if (keys.isEmpty) return;
    final int count = keys.length;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('删除 $count 条观看记录？'),
        content: const Text('这些记录的续播进度会一并删除，此操作不可撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await context.read<HistoryStore>().removeMany(keys);
    if (!mounted) return;
    _exitSelection();
    AppActions.snack(context, '已删除 $count 条记录');
  }

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

    final List<String> keys =
        records.map((PlayRecord e) => e.key).toList(growable: false);
    final Set<String> selected = _selected.intersection(keys.toSet());

    return Column(
      children: <Widget>[
        _Toolbar(
          count: records.length,
          selecting: _selecting,
          selectedCount: selected.length,
          allSelected: selected.length == keys.length,
          onEnterSelection: () => setState(() => _selecting = true),
          onExitSelection: _exitSelection,
          onToggleAll: () => _toggleAll(keys),
          onDelete: () => _deleteSelected(selected.toList()),
          onClear: () => _confirmClear(context, history),
          onStats: () => AppRoutes.openStats(context),
        ),
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
              final Map<String, String> headers =
                  source?.headers ?? const <String, String>{};
              final bool isSelected = selected.contains(record.key);

              return Dismissible(
                key: ValueKey<String>(record.key),
                // 多选模式下关掉滑动删除：两个删除入口同时存在容易误触。
                direction: _selecting
                    ? DismissDirection.none
                    : DismissDirection.endToStart,
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
                  subtitle:
                      '${record.episodeLabel} · ${formatRelativeTime(record.updatedAt)}',
                  progressLabel: record.progressLabel,
                  progress: record.progress,
                  headers: headers,
                  selecting: _selecting,
                  selected: isSelected,
                  onLongPress:
                      _selecting ? null : () => _enterSelection(record.key),
                  onTap: () {
                    if (_selecting) {
                      _toggle(record.key);
                      return;
                    }
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
  const _Toolbar({
    required this.count,
    required this.selecting,
    required this.selectedCount,
    required this.allSelected,
    required this.onEnterSelection,
    required this.onExitSelection,
    required this.onToggleAll,
    required this.onDelete,
    required this.onClear,
    required this.onStats,
  });

  final int count;
  final bool selecting;
  final int selectedCount;
  final bool allSelected;
  final VoidCallback onEnterSelection;
  final VoidCallback onExitSelection;
  final VoidCallback onToggleAll;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final VoidCallback onStats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (selecting) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 2),
        child: Row(
          children: <Widget>[
            IconButton(
              onPressed: onExitSelection,
              icon: const Icon(Icons.close),
              tooltip: '退出多选',
            ),
            Text(
              selectedCount == 0 ? '请选择记录' : '已选 $selectedCount 条',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onToggleAll,
              child: Text(allSelected ? '取消全选' : '全选'),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: selectedCount == 0 ? null : onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('删除'),
            ),
          ],
        ),
      );
    }

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
          IconButton(
            tooltip: '观看统计',
            onPressed: onStats,
            icon: const Icon(Icons.insights_outlined),
          ),
          TextButton.icon(
            onPressed: count > 1 ? onEnterSelection : null,
            icon: const Icon(Icons.checklist, size: 18),
            label: const Text('多选'),
          ),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmClear(BuildContext context, HistoryStore history) async {
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
