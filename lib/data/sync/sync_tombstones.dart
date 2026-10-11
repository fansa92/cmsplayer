import '../../core/constants.dart';
import '../../core/storage/json_store.dart';
import 'sync_payload.dart';

/// 删除墓碑的持久化。
///
/// 每次删除收藏 / 记录 / 源时记一条 `key -> 删除时刻`。同步时拿这个时刻和
/// 条目自身的时刻比，新的赢 —— 否则"我在手机上取消的收藏"会被电脑上的
/// 旧条目复活。
///
/// 存成 `[{"c":集合,"k":key,"t":毫秒}]` 而不是一个大 map，是为了复用
/// [JsonStore] 现成的列表读写，不必为同步单开一套文件 API。
class SyncTombstones {
  SyncTombstones._();

  /// 单例：删除入口分散在三个 Store 里，各自持有一份会各记各的。
  static final SyncTombstones instance = SyncTombstones._();

  /// 墓碑保留期。一年没再碰过的删除早就尘埃落定，留着只是白白膨胀。
  static const Duration keepFor = Duration(days: 365);

  /// 保留下限之外再设一个绝对上限，防止异常情况下无限增长。
  static const int maxEntries = 4000;

  final Map<String, Map<String, int>> _by = <String, Map<String, int>>{};
  bool _loaded = false;

  /// 读取当前墓碑的深拷贝。调用方拿到的是副本，改它不会影响本类。
  Future<Map<String, Map<String, int>>> load() async {
    if (!_loaded) {
      final List<Map<String, dynamic>> raw =
          await JsonStore.readList(K.boxSyncTombstones);
      for (final Map<String, dynamic> e in raw) {
        final String box = '${e['c'] ?? ''}';
        final Object? key = e['k'];
        final Object? ts = e['t'];
        if (box.isEmpty || key == null || ts is! num) continue;
        (_by[box] ??= <String, int>{})[key.toString()] = ts.toInt();
      }
      _loaded = true;
      _prune();
    }
    return _view();
  }

  /// 记一次删除。删除操作本身已经够慢了，这里必须等落盘完成 ——
  /// 否则应用在这中间被杀掉，墓碑丢失，下次同步又把条目拉回来。
  Future<void> mark(String collection, String key) =>
      markMany(collection, <String>[key]);

  Future<void> markMany(String collection, Iterable<String> keys) async {
    if (keys.isEmpty) return;
    final Map<String, int> inner = _by[collection] ??= <String, int>{};
    final int now = DateTime.now().millisecondsSinceEpoch;
    for (final String k in keys) {
      if (k.isEmpty) continue;
      inner[k] = now;
    }
    _prune();
    await _persist();
  }

  /// 用合并结果整体覆盖（写本地数据时调用）。
  Future<void> replaceAll(Map<String, Map<String, int>> value) async {
    _by
      ..clear()
      ..addAll(SyncPayload.pruneTombstones(value, keepFor: keepFor,
          maxEntries: maxEntries));
    _loaded = true;
    await _persist();
  }

  Future<void> clearAll() async {
    _by.clear();
    _loaded = true;
    await _persist();
  }

  // ---------------------------------------------------------------- 内部

  Map<String, Map<String, int>> _view() => <String, Map<String, int>>{
        for (final MapEntry<String, Map<String, int>> e in _by.entries)
          e.key: Map<String, int>.of(e.value),
      };

  void _prune() {
    final Map<String, Map<String, int>> pruned =
        SyncPayload.pruneTombstones(_by, keepFor: keepFor, maxEntries: maxEntries);
    _by
      ..clear()
      ..addAll(pruned);
  }

  Future<void> _persist() async {
    final List<Map<String, dynamic>> raw = <Map<String, dynamic>>[];
    _by.forEach((String box, Map<String, int> items) {
      items.forEach((String key, int ts) {
        raw.add(<String, dynamic>{'c': box, 'k': key, 't': ts});
      });
    });
    if (raw.isEmpty) {
      await JsonStore.deleteFile(K.boxSyncTombstones);
      return;
    }
    await JsonStore.writeList(K.boxSyncTombstones, raw);
  }

  /// 测试用：换一个不落盘的干净实例。
  static SyncTombstones isolated() => SyncTombstones._();
}
