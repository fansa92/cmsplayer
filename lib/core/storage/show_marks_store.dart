import 'package:flutter/foundation.dart';

import '../constants.dart';
import 'json_store.dart';

/// 一部剧的片头 / 片尾标记（毫秒）。
///
/// 0 表示没标记。两个都为 0 时整条记录会被删掉，不留空壳。
@immutable
class ShowSkipMarks {
  const ShowSkipMarks({
    required this.introMs,
    required this.outroMs,
    required this.updatedAt,
  });

  final int introMs;
  final int outroMs;
  final int updatedAt;

  bool get isEmpty => introMs <= 0 && outroMs <= 0;

  Map<String, dynamic> toJson(String key) => <String, dynamic>{
        'key': key,
        'introMs': introMs,
        'outroMs': outroMs,
        'updatedAt': updatedAt,
      };

  static ShowSkipMarks? fromJson(Map<String, dynamic> json) {
    final int intro = (json['introMs'] as num?)?.toInt() ?? 0;
    final int outro = (json['outroMs'] as num?)?.toInt() ?? 0;
    if (intro <= 0 && outro <= 0) return null;
    return ShowSkipMarks(
      introMs: intro,
      outroMs: outro,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 按**片名**记住的片头片尾，跨源共享。
///
/// 播放记录里的 introMs / outroMs 有两个短板：换一个资源站就换了一条记录，
/// 清空历史也会一起没。追剧的人往往同一部片在几个站之间跳，标记应当跟着
/// 片名走，所以单独存一份。
///
/// 内存缓存 + 整文件写回，和项目里其它存储一致；启动时 [ensureLoaded] 一次，
/// 播放器读标记是同步的，不能等磁盘。
class ShowMarksStore {
  ShowMarksStore._();

  static final ShowMarksStore instance = ShowMarksStore._();

  final Map<String, ShowSkipMarks> _marks = <String, ShowSkipMarks>{};
  bool _loaded = false;
  Future<void>? _loading;

  /// 只保留最近这么多部，避免文件无限长。
  static const int maxEntries = 400;

  /// 片名归一化：忽略大小写、空格、括号里的年份 / 版本说明。
  ///
  /// 不抹掉「第二季」这类季数，否则同系列会互相覆盖。
  static String keyOf(String title) {
    String s = title.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'[\s\u3000]+'), '');
    s = s.replaceAll(RegExp(r'[\(（\[【].*?[\)）\]】]'), '');
    s = s.replaceAll(RegExp(r'(国语版|粤语版|中字版|高清版)$'), '');
    return s.isEmpty ? title.trim().toLowerCase() : s;
  }

  bool get loaded => _loaded;

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final List<Map<String, dynamic>> raw =
          await JsonStore.readList(K.boxShowMarks);
      _marks.clear();
      for (final Map<String, dynamic> row in raw) {
        final String key = (row['key'] as String?)?.trim() ?? '';
        if (key.isEmpty) continue;
        final ShowSkipMarks? marks = ShowSkipMarks.fromJson(row);
        if (marks != null) _marks[key] = marks;
      }
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  /// 同步读取。启动时没加载完就返回 null，下次打开自然就有了。
  ShowSkipMarks? find(String title) => _marks[keyOf(title)];

  /// 写入（合并）一部剧的标记。[null] 表示该字段保持不变。
  Future<void> save(String title, {int? introMs, int? outroMs}) async {
    await ensureLoaded();
    final String key = keyOf(title);
    final ShowSkipMarks? old = _marks[key];
    final int intro = introMs ?? old?.introMs ?? 0;
    final int outro = outroMs ?? old?.outroMs ?? 0;
    if (intro <= 0 && outro <= 0) {
      _marks.remove(key);
    } else {
      _marks[key] = ShowSkipMarks(
        introMs: intro,
        outroMs: outro,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    await _flush();
  }

  Future<void> clear(String title) async {
    await ensureLoaded();
    if (_marks.remove(keyOf(title)) == null) return;
    await _flush();
  }

  Future<void> _flush() async {
    final List<MapEntry<String, ShowSkipMarks>> rows = _marks.entries.toList()
      ..sort((MapEntry<String, ShowSkipMarks> a,
              MapEntry<String, ShowSkipMarks> b) =>
          b.value.updatedAt.compareTo(a.value.updatedAt));
    if (rows.length > maxEntries) {
      for (final MapEntry<String, ShowSkipMarks> row
          in rows.sublist(maxEntries)) {
        _marks.remove(row.key);
      }
    }
    await JsonStore.writeList(
      K.boxShowMarks,
      <Map<String, dynamic>>[
        for (final MapEntry<String, ShowSkipMarks> e in _marks.entries)
          e.value.toJson(e.key),
      ],
    );
  }

  @visibleForTesting
  void resetForTest() {
    _marks.clear();
    _loaded = false;
    _loading = null;
  }

  @visibleForTesting
  void seedForTest(String title, {int introMs = 0, int outroMs = 0}) {
    _marks[keyOf(title)] = ShowSkipMarks(
      introMs: introMs,
      outroMs: outroMs,
      updatedAt: DateTime(2026).millisecondsSinceEpoch,
    );
    _loaded = true;
  }
}
