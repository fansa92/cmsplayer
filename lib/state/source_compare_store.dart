import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import '../core/utils/title_match.dart';
import '../data/models/paged_result.dart';
import '../data/models/vod_item.dart';
import '../data/models/vod_source.dart';
import '../data/repository/vod_repository.dart';

/// 单个源在「全源对比」里的查找状态。
enum CompareStatus {
  /// 还没轮到 / 还在排队。
  pending,

  /// 请求进行中。
  loading,

  /// 找到了同一部片子。
  found,

  /// 请求成功，但没有同名结果。
  missing,

  /// 请求失败（超时 / 接口报错）。
  failed,
}

/// 一个源在对比面板里的一行。
@immutable
class CompareEntry {
  const CompareEntry({
    required this.source,
    this.status = CompareStatus.pending,
    this.item,
    this.latencyMs = 0,
    this.error = '',
  });

  final VodSource source;
  final CompareStatus status;

  /// 命中的条目（[CompareStatus.found] 时非空）。
  final VodItem? item;

  /// 这一行从发请求到拿到结果的耗时，包含补详情的那一次。
  final int latencyMs;

  final String error;

  bool get found => status == CompareStatus.found && item != null;

  /// 有播放地址才算「能看」：有的源只返回简介，点进去还是空的。
  bool get playable => found && (item?.hasPlayInfo ?? false);

  int get episodeCount => item?.episodeCount ?? 0;

  int get lineCount => item?.playLines.length ?? 0;

  String get remarks => item?.remarks ?? '';

  String get statusLabel => switch (status) {
        CompareStatus.pending => '排队中',
        CompareStatus.loading => '查找中',
        CompareStatus.found => playable ? '可播放' : '无播放地址',
        CompareStatus.missing => '未找到',
        CompareStatus.failed => '请求失败',
      };

  CompareEntry copyWith({
    CompareStatus? status,
    VodItem? item,
    int? latencyMs,
    String? error,
  }) =>
      CompareEntry(
        source: source,
        status: status ?? this.status,
        item: item ?? this.item,
        latencyMs: latencyMs ?? this.latencyMs,
        error: error ?? this.error,
      );
}

/// 全源对比：拿一个片名到所有启用的源里各搜一遍，把集数、线路、更新时间
/// 摆在一起，让用户自己挑一个能看、集数全的源。
///
/// 和搜索页的「多源搜索」不是一回事：那边是**合并**同名结果只显示一条；
/// 这边刻意**不合并** —— 用户要看的正是各源之间的差异（谁更新得快、
/// 谁少几集、谁的播放地址真的能用）。
class SourceCompareStore extends ChangeNotifier {
  String _title = '';
  String _year = '';
  List<CompareEntry> _entries = const <CompareEntry>[];
  bool _running = false;

  /// 对比轮次。旧轮次的迟到结果直接丢掉，避免切页面/重新对比后串台。
  int _run = 0;

  bool _disposed = false;

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  String get title => _title;
  String get year => _year;
  List<CompareEntry> get entries => List<CompareEntry>.unmodifiable(_entries);
  bool get running => _running;
  bool get isEmpty => _entries.isEmpty;

  /// 有同名结果的源数量。
  int get foundCount => _entries.where((CompareEntry e) => e.found).length;

  /// 有播放地址的源数量。
  int get playableCount => _entries.where((CompareEntry e) => e.playable).length;

  int get failedCount =>
      _entries.where((CompareEntry e) => e.status == CompareStatus.failed).length;

  /// 集数最多、且有播放地址的那一行。都没有时返回 null。
  CompareEntry? get best {
    CompareEntry? top;
    for (final CompareEntry e in _entries) {
      if (!e.playable) continue;
      if (top == null || e.episodeCount > top.episodeCount) top = e;
    }
    return top;
  }

  /// 开始一轮对比。[sources] 传空时只清空结果。
  Future<void> compare({
    required String title,
    String year = '',
    required List<VodSource> sources,
  }) async {
    final int run = ++_run;
    _title = title.trim();
    _year = year.trim();
    _running = sources.isNotEmpty && _title.isNotEmpty;
    _entries = sources
        .map((VodSource s) => CompareEntry(
              source: s,
              status: CompareStatus.loading,
            ))
        .toList();
    _emit();

    if (!_running) {
      _running = false;
      _emit();
      return;
    }

    await Future.wait<void>(<Future<void>>[
      for (int i = 0; i < _entries.length; i++) _runOne(run, i),
    ]);
    if (run != _run) return;

    _entries = List<CompareEntry>.of(_entries)..sort(_compareOrder);
    _running = false;
    _emit();
  }

  /// 单行查询。每个源各自兜底，一个站挂了不影响其它行。
  Future<void> _runOne(int run, int index) async {
    if (run != _run || index >= _entries.length) return;
    final CompareEntry entry = _entries[index];
    final Stopwatch watch = Stopwatch()..start();
    CompareEntry next;
    try {
      final VodPage page = await VodRepository.instance.query(
        source: entry.source,
        keyword: searchTitle(_title),
        pageSize: 20,
        detail: true,
        // 对比要的就是「现在到底有多少集」，缓存里的十分钟前数据会误导。
        force: true,
      );
      VodItem? best;
      for (final VodItem item in page.items) {
        if (!sameTitle(item.name, _title)) continue;
        if (!yearCompatible(item.year, _year)) continue;
        if (best == null || item.episodeCount > best.episodeCount) best = item;
      }

      if (best == null) {
        next = entry.copyWith(
          status: CompareStatus.missing,
          latencyMs: watch.elapsedMilliseconds,
        );
      } else {
        VodItem detail = best;
        if (!detail.hasPlayInfo) {
          // 有的站 list 模式不返回播放地址，补一次详情才能判断「能不能看」。
          try {
            detail = await VodRepository.instance.ensureDetail(
              source: entry.source,
              item: detail,
            );
          } on Object catch (e) {
            AppLog.d('Compare', 'detail ${entry.source.name} failed: $e');
          }
        }
        next = entry.copyWith(
          status: CompareStatus.found,
          item: detail,
          latencyMs: watch.elapsedMilliseconds,
        );
      }
    } on Object catch (e) {
      AppLog.d('Compare', 'search ${entry.source.name} failed: $e');
      next = entry.copyWith(
        status: CompareStatus.failed,
        latencyMs: watch.elapsedMilliseconds,
        error: e.toString(),
      );
    }

    if (run != _run) return;
    final List<CompareEntry> list = List<CompareEntry>.of(_entries);
    list[index] = next;
    _entries = list;
    _emit();
  }

  /// 排序：能播的在前（集数多的优先），其次没播放地址的、没找到的、失败的。
  ///
  /// 行在查找过程中保持源顺序不动，全部回来后才重排 —— 否则每回来一行
  /// 列表就跳一次，正在看的那一行会跑掉。
  static int _compareOrder(CompareEntry a, CompareEntry b) {
    final int ra = _rank(a);
    final int rb = _rank(b);
    if (ra != rb) return ra.compareTo(rb);
    if (a.episodeCount != b.episodeCount) {
      return b.episodeCount.compareTo(a.episodeCount);
    }
    return a.latencyMs.compareTo(b.latencyMs);
  }

  static int _rank(CompareEntry e) {
    if (e.playable) return 0;
    return switch (e.status) {
      CompareStatus.found => 1,
      CompareStatus.missing => 2,
      CompareStatus.failed => 3,
      CompareStatus.loading || CompareStatus.pending => 4,
    };
  }

  /// 离开页面时调用：让在途结果失效，避免回来后看到上一部片的数据。
  void cancel() {
    _run++;
    _running = false;
    _entries = const <CompareEntry>[];
    _title = '';
    _year = '';
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _run++;
    super.dispose();
  }
}
