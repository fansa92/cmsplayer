import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/logger.dart';
import '../core/storage/json_store.dart';
import '../core/utils/text_utils.dart';
import '../core/utils/title_match.dart';

/// 某一天的观看时长。
@immutable
class DayUsage {
  const DayUsage({required this.day, required this.seconds});

  final DateTime day;
  final int seconds;
}

/// 某部片的累计观看时长。
@immutable
class TitleUsage {
  const TitleUsage({
    required this.title,
    required this.sourceName,
    required this.seconds,
  });

  final String title;
  final String sourceName;
  final int seconds;
}

/// 某个来源的累计观看时长。
@immutable
class SourceUsage {
  const SourceUsage({
    required this.sourceId,
    required this.sourceName,
    required this.seconds,
  });

  final String sourceId;
  final String sourceName;
  final int seconds;
}

/// 本机观看时长统计。
///
/// 播放记录只记「看到哪儿」，回答不了「这周看了多久」。这里累计**真实播放
/// 过的秒数**（拖动进度条、缓冲、跳集都不算），按天 / 片名 / 来源三种维度
/// 汇总，数据只留在本机。
///
/// 存储是一张扁平的 `日期 + 源 + 片名 + 秒数` 表，三种维度都能从它聚合出来，
/// 不必维护三套计数（也就不会出现三套数字对不上的情况）。
class WatchStatsStore extends ChangeNotifier {
  WatchStatsStore._();

  static final WatchStatsStore instance = WatchStatsStore._();

  /// 每行 = 一天 × 一个源 × 一部片。
  ///
  /// 片名用归一化后的键合并，同一部片在几个源轮流看也只会算成一部；
  /// 保留首次见到的原始片名做展示。
  final Map<String, _Row> _rows = <String, _Row>{};

  bool _loaded = false;
  Future<void>? _loading;
  DateTime _lastFlush = DateTime.fromMillisecondsSinceEpoch(0);

  /// 两次落盘之间的最小间隔。观看时长本身是 30 秒一段攒的，
  /// 这里再挡一层，避免同时开两个窗口看片时写得更频繁。
  static const Duration _flushInterval = Duration(seconds: 20);

  bool get loaded => _loaded;
  bool get isEmpty => _rows.isEmpty;

  int get totalSeconds {
    int sum = 0;
    for (final _Row row in _rows.values) {
      sum += row.seconds;
    }
    return sum;
  }

  /// 有记录的天数。
  int get activeDays =>
      _rows.keys.map((String k) => k.split('|').first).toSet().length;

  /// 看过的影片数（同名跨源算一部）。
  int get titleCount =>
      _rows.keys.map((String k) => k.split('|').last).toSet().length;

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final List<Map<String, dynamic>> raw =
          await JsonStore.readList(K.boxWatchStats);
      _rows.clear();
      for (final Map<String, dynamic> json in raw) {
        final String date = strOf(json['date']);
        final String sourceId = strOf(json['sourceId']);
        final String title = strOf(json['title']);
        final int seconds = intOf(json['seconds']);
        if (date.isEmpty || title.isEmpty || seconds <= 0) continue;
        _rows['$date|$sourceId|${normalizeTitle(title)}'] = _Row(
          date: date,
          sourceId: sourceId,
          sourceName: strOf(json['sourceName']),
          title: title,
          seconds: seconds,
        );
      }
      _prune(DateTime.now());
    } on Object catch (e, s) {
      AppLog.e('WatchStats', 'load failed: $e', s);
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  /// 记一段观看时长。
  ///
  /// [watched] 是这一段实际播放的时长，调用方负责只在「真的在播」时累计。
  /// 单段太短（不足 1 秒）直接丢掉，避免拖动、连点时写入一堆 0 秒行。
  Future<void> add({
    required String title,
    required String sourceId,
    required String sourceName,
    required Duration watched,
    DateTime? at,
  }) async {
    final int seconds = watched.inSeconds;
    if (seconds <= 0 || title.trim().isEmpty) return;
    await ensureLoaded();
    final DateTime when = at ?? DateTime.now();
    final String date = _dayKey(when);
    final String key = '$date|$sourceId|${normalizeTitle(title)}';
    final _Row? existing = _rows[key];
    if (existing == null) {
      _rows[key] = _Row(
        date: date,
        sourceId: sourceId,
        sourceName: sourceName,
        title: title.trim(),
        seconds: seconds,
      );
    } else {
      existing.seconds += seconds;
      if (sourceName.isNotEmpty) existing.sourceName = sourceName;
    }
    // 始终以「现在」为基准裁剪：拿事件时间去裁的话，补一条很旧的记录
    // 会把 cutoff 一起推回去，旧数据反而永远清不掉。
    _prune(DateTime.now());
    notifyListeners();
    await _maybeFlush();
  }

  /// 立即落盘（播放器退出时调用，别把最后半分钟丢了）。
  Future<void> flush() async {
    if (!_loaded || _rows.isEmpty) return;
    _lastFlush = DateTime.now();
    await JsonStore.writeList(
      K.boxWatchStats,
      <Map<String, dynamic>>[
        for (final _Row row in _rows.values) row.toJson(),
      ],
    );
  }

  Future<void> _maybeFlush() async {
    if (DateTime.now().difference(_lastFlush) < _flushInterval) return;
    await flush();
  }

  // ---------------------------------------------------------------- 聚合

  /// 某天的观看秒数。
  int secondsOn(DateTime day) {
    final String date = _dayKey(day);
    int sum = 0;
    for (final _Row row in _rows.values) {
      if (row.date == date) sum += row.seconds;
    }
    return sum;
  }

  /// 最近 [count] 天（含今天），从早到晚排好，缺的天补 0。
  List<DayUsage> recentDays(int count, {DateTime? now}) {
    final DateTime today = _dateOnly(now ?? DateTime.now());
    return <DayUsage>[
      for (int i = count - 1; i >= 0; i--)
        DayUsage(
          day: today.subtract(Duration(days: i)),
          seconds: secondsOn(today.subtract(Duration(days: i))),
        ),
    ];
  }

  /// 本周（最近 7 天）观看秒数。
  int weekSeconds({DateTime? now}) {
    final List<DayUsage> days = recentDays(7, now: now);
    return days.fold<int>(0, (int sum, DayUsage d) => sum + d.seconds);
  }

  /// 连续观看天数。
  ///
  /// 今天还没看不算断：从昨天往回数，避免用户在早上打开统计页时看到
  /// 「连续 0 天」这种自我否定。真断了才归零。
  int streakDays({DateTime? now}) {
    final DateTime today = _dateOnly(now ?? DateTime.now());
    DateTime cursor = today;
    if (secondsOn(cursor) <= 0) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (secondsOn(cursor) <= 0) return 0;
    }
    int streak = 0;
    while (secondsOn(cursor) > 0) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// 看得最多的片（跨源合并）。
  List<TitleUsage> topTitles({int limit = 5}) {
    final Map<String, _TitleAcc> acc = <String, _TitleAcc>{};
    for (final _Row row in _rows.values) {
      final String key = normalizeTitle(row.title);
      final _TitleAcc? item = acc[key];
      if (item == null) {
        acc[key] = _TitleAcc(row.title, row.sourceName, row.seconds);
      } else {
        item.seconds += row.seconds;
        if (item.sourceName.isEmpty) item.sourceName = row.sourceName;
      }
    }
    final List<_TitleAcc> list = acc.values.toList()
      ..sort((_TitleAcc a, _TitleAcc b) => b.seconds.compareTo(a.seconds));
    return <TitleUsage>[
      for (final _TitleAcc a in list.take(limit))
        TitleUsage(
          title: a.title,
          sourceName: a.sourceName,
          seconds: a.seconds,
        ),
    ];
  }

  /// 按来源汇总，从多到少。
  List<SourceUsage> bySource() {
    final Map<String, _SourceAcc> acc = <String, _SourceAcc>{};
    for (final _Row row in _rows.values) {
      final _SourceAcc? item = acc[row.sourceId];
      if (item == null) {
        acc[row.sourceId] = _SourceAcc(row.sourceName, row.seconds);
      } else {
        item.seconds += row.seconds;
        if (row.sourceName.isNotEmpty) item.sourceName = row.sourceName;
      }
    }
    final List<SourceUsage> list = <SourceUsage>[
      for (final MapEntry<String, _SourceAcc> e in acc.entries)
        SourceUsage(
          sourceId: e.key,
          sourceName: e.value.sourceName,
          seconds: e.value.seconds,
        ),
    ]..sort((SourceUsage a, SourceUsage b) => b.seconds.compareTo(a.seconds));
    return list;
  }

  /// 清空统计。观看记录是另一份数据，不受影响。
  Future<void> clear() async {
    if (_rows.isEmpty) return;
    _rows.clear();
    await JsonStore.deleteFile(K.boxWatchStats);
    notifyListeners();
  }

  // ---------------------------------------------------------------- 内部

  void _prune(DateTime now) {
    final DateTime cutoff =
        _dateOnly(now).subtract(const Duration(days: K.watchStatsKeepDays));
    final String cutoffKey = _dayKey(cutoff);
    _rows.removeWhere((String _, _Row row) => row.date.compareTo(cutoffKey) < 0);
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  @visibleForTesting
  void resetForTest() {
    _rows.clear();
    _loaded = false;
    _loading = null;
    _lastFlush = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class _Row {
  _Row({
    required this.date,
    required this.sourceId,
    required this.sourceName,
    required this.title,
    required this.seconds,
  });

  final String date;
  final String sourceId;
  String sourceName;
  final String title;
  int seconds;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'date': date,
        'sourceId': sourceId,
        'sourceName': sourceName,
        'title': title,
        'seconds': seconds,
      };
}

class _TitleAcc {
  _TitleAcc(this.title, this.sourceName, this.seconds);

  final String title;
  String sourceName;
  int seconds;
}

class _SourceAcc {
  _SourceAcc(this.sourceName, this.seconds);

  String sourceName;
  int seconds;
}
