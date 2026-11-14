import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/play_record.dart';
import '../../state/history_store.dart';
import '../../state/watch_stats_store.dart';
import '../widgets/empty_state.dart';

/// 观看统计。
///
/// 数据来自播放器累计的真实播放秒数（见 [WatchStatsStore]），不是拿播放
/// 记录里的进度去估算 —— 看了 5 分钟和「拖到第 5 分钟」是两回事。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, this.store});

  /// 统计容器（测试注入点）；为 null 时用全局单例。
  final WatchStatsStore? store;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late final WatchStatsStore _store = widget.store ?? WatchStatsStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_store.ensureLoaded());
  }

  Future<void> _confirmClear() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清空观看统计？'),
        content: const Text('只删除本机的观看时长统计，观看记录与收藏不受影响。'),
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
    if (ok != true || !mounted) return;
    await _store.clear();
  }

  @override
  Widget build(BuildContext context) {
    final HistoryStore history = context.watch<HistoryStore>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('观看统计'),
        actions: <Widget>[
          IconButton(
            tooltip: '清空统计',
            onPressed: _store.isEmpty ? null : _confirmClear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (BuildContext context, _) => _buildBody(context, history),
      ),
    );
  }

  Widget _buildBody(BuildContext context, HistoryStore history) {
    final ThemeData theme = Theme.of(context);

    if (_store.isEmpty) {
      return const EmptyState(
        icon: Icons.insights_outlined,
        title: '还没有观看时长',
        subtitle: '播放影片时会在本机累计真实播放的时长，这里会按天、按片、'
            '按来源汇总。统计只存在本机，不会上传。',
      );
    }

    final List<DayUsage> days = _store.recentDays(14);
    final List<TitleUsage> tops = _store.topTitles(limit: 5);
    final List<SourceUsage> sources = _store.bySource();
    final int watching = history.records
        .where((PlayRecord r) => !r.finished && r.positionMs > 0)
        .length;
    final int finished = history.records
        .where((PlayRecord r) => r.finished)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: <Widget>[
        _OverviewCard(store: _store),
        const SizedBox(height: 22),
        _SectionTitle(
          title: '近 14 天',
          trailing: '日均 ${_human(_store.weekSeconds() ~/ 7)}',
        ),
        const SizedBox(height: 10),
        _DayChart(days: days),
        const SizedBox(height: 22),
        const _SectionTitle(title: '常看片单'),
        const SizedBox(height: 6),
        if (tops.isEmpty)
          Text(
            '还没有足够的播放记录',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (int i = 0; i < tops.length; i++)
            _RankRow(
              index: i + 1,
              title: tops[i].title,
              subtitle: tops[i].sourceName,
              label: _human(tops[i].seconds),
              ratio: tops[i].seconds / math.max(1, tops.first.seconds),
            ),
        const SizedBox(height: 22),
        const _SectionTitle(title: '按来源'),
        const SizedBox(height: 6),
        for (final SourceUsage s in sources)
          _RankRow(
            title: s.sourceName.isEmpty ? '未知来源' : s.sourceName,
            label: _human(s.seconds),
            ratio: s.seconds / math.max(1, sources.first.seconds),
          ),
        const SizedBox(height: 22),
        const _SectionTitle(title: '追剧概况'),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(child: _StatTile(label: '在追', value: '$watching 部')),
            const SizedBox(width: 10),
            Expanded(child: _StatTile(label: '已看完', value: '$finished 部')),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(label: '有记录', value: '${_store.activeDays} 天'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '统计只在使用本机播放时累计；拖动进度、缓冲与自动跳集不计入。'
          '清空观看记录不会清空这里的统计。',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// 顶部概览卡。
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.store});

  final WatchStatsStore store;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color fg = theme.colorScheme.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.primaryContainer,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '本周观看',
            style: theme.textTheme.labelLarge?.copyWith(
              color: fg.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _human(store.weekSeconds()),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '今日 ${_human(store.secondsOn(DateTime.now()))} · '
            '连续 ${store.streakDays()} 天',
            style: theme.textTheme.bodySmall?.copyWith(
              color: fg.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: fg.withValues(alpha: 0.15)),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _MiniStat(
                  label: '累计',
                  value: _human(store.totalSeconds),
                  color: fg,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: '看过的片',
                  value: '${store.titleCount} 部',
                  color: fg,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: '有记录',
                  value: '${store.activeDays} 天',
                  color: fg,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 近 N 天的柱状图。没有引图表库：14 根柱子用 Row + Expanded 就够了。
class _DayChart extends StatelessWidget {
  const _DayChart({required this.days});

  final List<DayUsage> days;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    int maxSeconds = 0;
    for (final DayUsage d in days) {
      maxSeconds = math.max(maxSeconds, d.seconds);
    }
    final DateTime today = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 108,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (final DayUsage day in days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        Container(
                          height: _barHeight(day.seconds, maxSeconds),
                          decoration: BoxDecoration(
                            color: isToday(day.day)
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primary
                                    .withValues(alpha: 0.35),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${day.day.day}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            color: isToday(day.day)
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          maxSeconds > 0
              ? '单日最多 ${_human(maxSeconds)} · 今天在最后一根'
              : '最近 14 天还没有观看记录',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  double _barHeight(int seconds, int maxSeconds) {
    if (seconds <= 0 || maxSeconds <= 0) return 2;
    // 最少 4px：有记录但很短的柱子也要看得见，不然会被误认为空白。
    return math.max(4, 88 * seconds / maxSeconds);
  }
}

/// 带排名与比例条的一行（常看片单 / 按来源共用）。
class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.title,
    required this.label,
    required this.ratio,
    this.index,
    this.subtitle = '',
  });

  final String title;
  final String label;
  final double ratio;
  final int? index;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (index != null)
                SizedBox(
                  width: 22,
                  child: Text(
                    '$index',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (subtitle.isNotEmpty) ...<Widget>[
                const SizedBox(width: 8),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio.isNaN ? 0 : ratio.clamp(0.02, 1.0),
              minHeight: 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing = ''});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (trailing.isNotEmpty)
          Text(
            trailing,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// 秒数转人话：`2 小时 15 分` / `45 分钟` / `30 秒`。
String _human(int seconds) {
  if (seconds <= 0) return '0 分钟';
  if (seconds < 60) return '$seconds 秒';
  final int totalMinutes = seconds ~/ 60;
  final int hours = totalMinutes ~/ 60;
  final int minutes = totalMinutes % 60;
  if (hours <= 0) return '$minutes 分钟';
  if (minutes == 0) return '$hours 小时';
  return '$hours 小时 $minutes 分';
}
