import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/logger.dart';
import '../data/api/source_importer.dart';
import '../data/models/subscription.dart';
import '../data/models/vod_source.dart';
import '../data/repository/subscription_repository.dart';
import 'source_store.dart';

/// 订阅：一个地址拉回一批资源站。
///
/// 与「从 JSON 导入」的区别不在解析，而在**维护关系**：
///  * 记住这条订阅上次带来了哪些源；
///  * 刷新时新增的补进来、已有的更新字段；
///  * 订阅里消失的只停用不删除；
///  * 启动时按 [K.subscriptionAutoRefresh] 自动保鲜，不用用户惦记。
class SubscriptionStore extends ChangeNotifier {
  SubscriptionStore(this._sources);

  final SourceStore _sources;

  List<Subscription> _items = <Subscription>[];
  bool _busy = false;
  String? _lastError;
  bool _disposed = false;

  List<Subscription> get items => List<Subscription>.unmodifiable(_items);
  bool get busy => _busy;
  String? get lastError => _lastError;
  bool get isEmpty => _items.isEmpty;
  int get enabledCount => _items.where((Subscription s) => s.enabled).length;

  /// 拉取实现（测试注入点）：默认真的发 HTTP。
  static Future<String> Function(String url) fetcher = SourceImporter.fetchText;

  static void resetFetcher() {
    fetcher = SourceImporter.fetchText;
  }

  /// 取时间的实现（测试注入点），用来构造"多久没刷新"这类场景。
  static DateTime Function() clock = DateTime.now;

  static void resetClock() {
    clock = DateTime.now;
  }

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> load() async {
    try {
      _items = await SubscriptionRepository.load();
      _lastError = null;
    } on Object catch (e, s) {
      AppLog.e('SubscriptionStore', 'load failed: $e', s);
      _lastError = '读取订阅失败：$e';
    }
    _emit();
  }

  Future<void> _persist() => SubscriptionRepository.save(_items);

  Future<Subscription> add({required String name, required String url}) async {
    final Subscription sub = Subscription.create(name: name, url: url);
    if (!sub.isUsable) throw ArgumentError('订阅地址无效');
    final int at = _items.indexWhere((Subscription s) => s.id == sub.id);
    if (at >= 0) {
      // 同地址重复添加视作"更新名字并启用"，不产生第二条。
      _items[at] = _items[at].copyWith(name: sub.name, enabled: true);
      await _persist();
      _emit();
      return _items[at];
    }
    _items.add(sub);
    await _persist();
    _emit();
    return sub;
  }

  Future<void> remove(String id) async {
    final int before = _items.length;
    _items.removeWhere((Subscription s) => s.id == id);
    if (_items.length == before) return;
    await _persist();
    _emit();
  }

  Future<void> setEnabled(String id, bool value) async {
    final int at = _items.indexWhere((Subscription s) => s.id == id);
    if (at < 0) return;
    _items[at] = _items[at].copyWith(enabled: value);
    await _persist();
    _emit();
  }

  /// 刷新一条订阅。失败时把原因写进这条订阅并原样抛出，调用方决定怎么提示。
  Future<SubscribeResult> refresh(Subscription sub) async {
    _busy = true;
    _emit();
    try {
      final String text = await fetcher(sub.url);
      final List<VodSource> parsed = SourceImporter.parse(text);
      final int added = await _sources.addMany(parsed);

      final List<String> incoming =
          parsed.map((VodSource s) => s.id).toList(growable: false);
      final Set<String> alive = incoming.toSet();
      final List<String> gone = sub.sourceIds
          .where((String id) => !alive.contains(id))
          .toList(growable: false);
      final int offline = await _sources.disableMissing(gone);

      final Subscription updated = sub.copyWith(
        lastFetchedAt: clock(),
        sourceCount: parsed.length,
        sourceIds: incoming,
        lastError: '',
      );
      _replace(updated);
      await _persist();
      return SubscribeResult(
        subscription: updated,
        added: added,
        updated: parsed.length - added,
        offline: offline,
      );
    } on Object catch (e) {
      final Subscription failed = sub.copyWith(lastError: '$e');
      _replace(failed);
      await _persist();
      AppLog.d('SubscriptionStore', 'refresh ${sub.url} failed: $e');
      rethrow;
    } finally {
      _busy = false;
      _emit();
    }
  }

  /// 刷新全部启用的订阅，返回成功条数。单条失败不影响其它条。
  Future<int> refreshAll() async {
    int ok = 0;
    for (final Subscription sub in List<Subscription>.of(_items)) {
      if (!sub.enabled) continue;
      try {
        await refresh(sub);
        ok++;
      } on Object {
        // 失败原因已经写进那一条，循环继续。
      }
    }
    return ok;
  }

  /// 启动时调用：只刷新"太久没拉"的订阅，避免每次开应用都打一轮请求。
  ///
  /// 返回实际尝试刷新的条数（0 表示都是新鲜的）。
  Future<int> refreshStale({Duration maxAge = K.subscriptionAutoRefresh}) async {
    final DateTime now = clock();
    final List<Subscription> stale = _items.where((Subscription s) {
      if (!s.enabled) return false;
      final Duration? age = s.ageFrom(now);
      return age == null || age > maxAge;
    }).toList(growable: false);
    if (stale.isEmpty) return 0;
    for (final Subscription sub in stale) {
      try {
        await refresh(sub);
      } on Object {
        // 网络不通时静默失败，界面上那条订阅会显示红色提示。
      }
    }
    return stale.length;
  }

  void _replace(Subscription sub) {
    final int at = _items.indexWhere((Subscription s) => s.id == sub.id);
    if (at < 0) return;
    _items[at] = sub;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
