import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/logger.dart';
import '../core/storage/json_store.dart';
import '../data/api/maccms_api.dart';
import '../data/models/source_health.dart';
import '../data/models/vod_source.dart';

/// 资源站测速结果的存储与执行。
///
/// 「连通性测试」只回答能不能连上；真正常用的是**快不快** —— 同一部片在
/// 几个站都有，慢站要转十几秒才出列表。这里把每个源一次请求的往返耗时
/// 记下来，界面上标出档位，并支持按测速结果重排源顺序。
///
/// 结果落盘（`source_health.json`），重启后仍然能看到上次测的数字。
class SourceHealthStore extends ChangeNotifier {
  SourceHealthStore._();

  static final SourceHealthStore instance = SourceHealthStore._();

  /// 单次测速最多同时打几个源。
  ///
  /// 太大会把本机带宽和资源站的并发限制一起打满，反而让每个源都变慢；
  /// 5 个是「几十个源几十秒内测完」和「数字基本反映真实速度」之间的折中。
  static const int defaultConcurrency = 5;

  final Map<String, SourceHealth> _health = <String, SourceHealth>{};

  bool _loaded = false;
  bool _probing = false;
  Future<void>? _loading;

  bool get loaded => _loaded;
  bool get probing => _probing;
  bool get isEmpty => _health.isEmpty;

  /// 测速实现（测试注入点）。返回往返毫秒数，-1 表示没测通。
  ///
  /// 默认真的去请求一次列表接口；测试里换成可控实现即可覆盖并发、
  /// 排序、落盘等逻辑，不需要起 HTTP 服务。
  static Future<int> Function(VodSource source) prober = _probeOnce;

  static Future<int> _probeOnce(VodSource source) async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      final bool ok = await MacCmsApi(source).ping();
      watch.stop();
      return ok ? watch.elapsedMilliseconds : -1;
    } on Object catch (e) {
      AppLog.d('SourceHealth', 'probe ${source.name} failed: $e');
      watch.stop();
      return -1;
    }
  }

  static void resetProber() {
    prober = _probeOnce;
  }

  SourceHealth? of(String sourceId) => _health[sourceId];

  /// 全部结果，按延迟从快到慢、不可用的排最后。
  List<SourceHealth> get ranked {
    final List<SourceHealth> list = _health.values.toList();
    list.sort((SourceHealth a, SourceHealth b) {
      if (a.ok != b.ok) return a.ok ? -1 : 1;
      return a.latencyMs.compareTo(b.latencyMs);
    });
    return list;
  }

  /// 最近一次测速时刻（所有结果里最新的那个）。
  DateTime? get lastCheckedAt {
    DateTime? latest;
    for (final SourceHealth h in _health.values) {
      if (latest == null || h.checkedAt.isAfter(latest)) latest = h.checkedAt;
    }
    return latest;
  }

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final List<Map<String, dynamic>> rows =
          await JsonStore.readList(K.boxSourceHealth);
      _health.clear();
      for (final Map<String, dynamic> row in rows) {
        final SourceHealth health = SourceHealth.fromJson(row);
        if (health.sourceId.isEmpty) continue;
        _health[health.sourceId] = health;
      }
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  /// 并发测速一组源。每测完一个就通知界面刷新，数字逐个出现。
  Future<Map<String, SourceHealth>> probeAll(
    List<VodSource> sources, {
    int concurrency = defaultConcurrency,
  }) async {
    final List<VodSource> queue =
        sources.where((VodSource s) => s.isUsable).toList(growable: true);
    if (queue.isEmpty) return <String, SourceHealth>{};

    _probing = true;
    notifyListeners();

    final Map<String, SourceHealth> result = <String, SourceHealth>{};
    final int limit = concurrency.clamp(1, 8);
    final int workers = limit < queue.length ? limit : queue.length;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final VodSource source = queue.removeAt(0);
        int latency = -1;
        try {
          latency = await prober(source);
        } on Object catch (e) {
          AppLog.d('SourceHealth', 'probe ${source.name} threw: $e');
        }
        final SourceHealth health = SourceHealth(
          sourceId: source.id,
          latencyMs: latency < 0 ? -1 : latency,
          checkedAt: DateTime.now(),
        );
        _health[source.id] = health;
        result[source.id] = health;
        notifyListeners();
      }
    }

    try {
      await Future.wait(<Future<void>>[
        for (int i = 0; i < workers; i++) worker(),
      ]);
      await _flush();
    } finally {
      _probing = false;
      notifyListeners();
    }
    return result;
  }

  /// 测一个源并落盘（单条「测速」按钮用）。
  Future<SourceHealth> probeOne(VodSource source) async {
    int latency = -1;
    try {
      latency = await prober(source);
    } on Object catch (e) {
      AppLog.d('SourceHealth', 'probe ${source.name} threw: $e');
    }
    final SourceHealth health = SourceHealth(
      sourceId: source.id,
      latencyMs: latency < 0 ? -1 : latency,
      checkedAt: DateTime.now(),
    );
    _health[source.id] = health;
    notifyListeners();
    await _flush();
    return health;
  }

  /// 按给定的源顺序给出排好的 ID 列表。
  ///
  /// 有结果的按延迟升序，没有结果的按调用方给的原始顺序排最后 ——
  /// 一次没测过的源不该因为「不知道」被扔到最前面。
  List<String> orderBySpeed(List<VodSource> sources) {
    final List<VodSource> copy = List<VodSource>.of(sources);
    copy.sort((VodSource a, VodSource b) {
      final SourceHealth? ha = _health[a.id];
      final SourceHealth? hb = _health[b.id];
      final bool oka = ha?.ok ?? false;
      final bool okb = hb?.ok ?? false;
      if (oka != okb) return oka ? -1 : 1;
      if (oka && okb) return ha!.latencyMs.compareTo(hb!.latencyMs);
      return 0;
    });
    return copy.map((VodSource s) => s.id).toList(growable: false);
  }

  /// 删除已经不存在的源的结果，避免文件越攒越大。
  Future<void> pruneTo(Iterable<String> sourceIds) async {
    final Set<String> keep = sourceIds.toSet();
    final int before = _health.length;
    _health.removeWhere((String id, SourceHealth _) => !keep.contains(id));
    if (_health.length != before) await _flush();
  }

  Future<void> clear() async {
    if (_health.isEmpty) return;
    _health.clear();
    await JsonStore.deleteFile(K.boxSourceHealth);
    notifyListeners();
  }

  Future<void> _flush() => JsonStore.writeList(
        K.boxSourceHealth,
        <Map<String, dynamic>>[
          for (final SourceHealth h in _health.values) h.toJson(),
        ],
      );

  @visibleForTesting
  void resetForTest() {
    _health.clear();
    _loaded = false;
    _loading = null;
    _probing = false;
  }

  @visibleForTesting
  void seedForTest(Iterable<SourceHealth> health) {
    for (final SourceHealth h in health) {
      _health[h.sourceId] = h;
    }
    _loaded = true;
  }
}
