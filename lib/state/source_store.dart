import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import '../core/storage/settings_store.dart';
import '../core/utils/collections.dart';
import '../data/api/maccms_api.dart';
import '../data/api/source_importer.dart';
import '../data/models/vod_source.dart';
import '../data/repository/source_repository.dart';
import '../data/repository/vod_repository.dart';
import '../data/sync/sync_payload.dart';
import '../data/sync/sync_tombstones.dart';

/// 资源站列表的状态：增删改查、排序、启用、连通性测试、JSON 导入导出。
class SourceStore extends ChangeNotifier {
  SourceStore(this._settings);

  final SettingsStore _settings;

  List<VodSource> _sources = <VodSource>[];
  String _activeId = '';
  bool _loading = true;
  bool _busy = false;
  String? _testingId;
  String? _lastError;
  bool _disposed = false;

  bool get loading => _loading;
  bool get busy => _busy;
  String? get testingId => _testingId;
  String? get lastError => _lastError;

  List<VodSource> get sources => List<VodSource>.unmodifiable(_sources);

  List<VodSource> get enabledSources =>
      _sources.where((VodSource s) => s.enabled).toList();

  String get activeId => _activeId;

  /// 当前激活的源。若被停用则自动回退到第一个启用的源。
  VodSource? get active {
    final VodSource? exact = _sources.firstWhereOrNull(
      (VodSource s) => s.id == _activeId && s.enabled,
    );
    if (exact != null) return exact;
    final List<VodSource> enabled = enabledSources;
    return enabled.isEmpty ? null : enabled.first;
  }

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  // ---------------------------------------------------------------- 生命周期

  /// 本表在墓碑里的类型名。
  ///
  /// 删除本地数据时必须顺手记一条墓碑，否则对方设备下次同步会把这条源
  /// 又推回来 —— 删除看起来"没生效"。见 [SyncTombstones]。
  static const String tombstoneType = SyncBox.sources;

  Future<void> load() async {
    _loading = true;
    _emit();
    try {
      _sources = await SourceRepository.load();
      final String preferred = _settings.activeSourceId;
      final bool usable = _sources.any(
        (VodSource s) => s.id == preferred && s.enabled,
      );
      _activeId = usable
          ? preferred
          : (_sources.firstWhereOrNull((VodSource s) => s.enabled)?.id ?? '');
      _lastError = null;
    } on Object catch (e, s) {
      AppLog.e('SourceStore', 'load failed: $e', s);
      _lastError = '读取资源站失败：$e';
    } finally {
      _loading = false;
      _emit();
    }
  }

  Future<void> _persist() async {
    await SourceRepository.save(_sources);
  }

  // ---------------------------------------------------------------- 增删改

  Future<void> setActive(VodSource source) async {
    if (_activeId == source.id) return;
    _activeId = source.id;
    await _settings.setActiveSourceId(source.id);
    _emit();
  }

  Future<void> add(VodSource source) async {
    final int index = _sources.indexWhere((VodSource s) => s.id == source.id);
    if (index >= 0) {
      _sources[index] = _sources[index].copyWith(
        name: source.name,
        api: source.api,
        note: source.note,
        parseApi: source.parseApi,
        referer: source.referer,
        userAgent: source.userAgent,
      );
    } else {
      _sources.add(source.copyWith(sort: _nextSort()));
    }
    await _persist();
    _ensureActive();
    _emit();
  }

  /// 批量添加 / 合并。已存在的（同名同接口）只更新字段，不产生重复项。
  Future<int> addMany(List<VodSource> incoming) async {
    if (incoming.isEmpty) return 0;
    int added = 0;
    for (final VodSource source in incoming) {
      final int index =
          _sources.indexWhere((VodSource s) => s.id == source.id);
      if (index >= 0) {
        final VodSource old = _sources[index];
        _sources[index] = old.copyWith(
          name: source.name,
          note: source.note.isNotEmpty ? source.note : old.note,
          parseApi: source.parseApi.isNotEmpty ? source.parseApi : old.parseApi,
          referer: source.referer.isNotEmpty ? source.referer : old.referer,
          userAgent:
              source.userAgent.isNotEmpty ? source.userAgent : old.userAgent,
        );
      } else {
        _sources.add(source.copyWith(sort: _nextSort() + added));
        added++;
      }
    }
    await _persist();
    _ensureActive();
    _emit();
    return added;
  }

  Future<void> update(VodSource source) async {
    final int index =
        _sources.indexWhere((VodSource s) => s.id == source.id);
    if (index < 0) return;
    _sources[index] = source;
    await _persist();
    _ensureActive();
    _emit();
  }

  Future<void> remove(String id) async {
    _sources.removeWhere((VodSource s) => s.id == id);
    // 先记墓碑再落盘：反过来的话，进程在这中间被杀掉就会留下"数据删了但
    // 墓碑没记"的状态，同步时对方会把这条源原样推回来。
    await SyncTombstones.instance.mark(tombstoneType, id);
    await _persist();
    _ensureActive();
    _emit();
  }

  Future<void> removeMany(List<String> keys) async {
    final Set<String> set = keys.toSet();
    final List<String> removed = _sources
        .where((VodSource s) => set.contains(s.id))
        .map((VodSource s) => s.id)
        .toList(growable: false);
    if (removed.isEmpty) return;
    _sources.removeWhere((VodSource s) => set.contains(s.id));
    await SyncTombstones.instance.markMany(tombstoneType, removed);
    await _persist();
    _ensureActive();
    _emit();
  }

  Future<void> toggleEnabled(String id) async {
    final int index = _sources.indexWhere((VodSource s) => s.id == id);
    if (index < 0) return;
    _sources[index] = _sources[index].copyWith(enabled: !_sources[index].enabled);
    await _persist();
    _ensureActive();
    _emit();
  }

  Future<void> move(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _sources.length) return;
    final int target = newIndex.clamp(0, _sources.length - 1);
    final VodSource item = _sources.removeAt(oldIndex);
    _sources.insert(target, item);
    for (int i = 0; i < _sources.length; i++) {
      _sources[i] = _sources[i].copyWith(sort: i);
    }
    await _persist();
    _emit();
  }

  void _ensureActive() {
    if (_sources.isEmpty) {
      _activeId = '';
      return;
    }
    final bool usable = _sources.any(
      (VodSource s) => s.id == _activeId && s.enabled,
    );
    if (!usable) {
      _activeId =
          _sources.firstWhereOrNull((VodSource s) => s.enabled)?.id ?? '';
    }
  }

  int _nextSort() => _sources.isEmpty
      ? 0
      : _sources.map((VodSource s) => s.sort).reduce((int a, int b) => a > b ? a : b) + 1;

  // ---------------------------------------------------------------- 测试

  Future<bool> test(VodSource source) async {
    _testingId = source.id;
    _emit();
    try {
      return await MacCmsApi(source).ping();
    } finally {
      _testingId = null;
      _emit();
    }
  }

  /// 并发测试多个源，返回通过的 ID 集合。
  Future<Set<String>> testMany(List<VodSource> targets) async {
    final List<Future<bool>> futures = targets
        .map((VodSource s) => MacCmsApi(s).ping())
        .toList();
    final List<bool> results = await Future.wait(futures);
    final Set<String> ok = <String>{};
    for (int i = 0; i < targets.length; i++) {
      if (results[i]) ok.add(targets[i].id);
    }
    return ok;
  }

  // ---------------------------------------------------------------- 导入导出

  /// 从 JSON 文本导入。返回新增条数。
  Future<int> importFromText(String text) async {
    _busy = true;
    _lastError = null;
    _emit();
    try {
      final List<VodSource> parsed = SourceImporter.parse(text);
      return await addMany(parsed);
    } on Object catch (e) {
      _lastError = e.toString();
      rethrow;
    } finally {
      _busy = false;
      _emit();
    }
  }

  /// 从 URL 导入。返回新增条数。
  Future<int> importFromUrl(String url) async {
    _busy = true;
    _lastError = null;
    _emit();
    try {
      final String text = await SourceImporter.fetchText(url);
      return await addMany(SourceImporter.parse(text));
    } on Object catch (e) {
      _lastError = e.toString();
      rethrow;
    } finally {
      _busy = false;
      _emit();
    }
  }

  String exportJson() => SourceImporter.export(_sources);

  /// 重置回内置示例源。
  Future<void> resetToBuiltin() async {
    _sources = SourceRepository.builtin();
    await _persist();
    _ensureActive();
    _emit();
  }

  /// 清空所有源。
  Future<void> clearAll() async {
    // 清空是逐条删除的等价物，要把当时存在的每一条都记成墓碑 —— 只清本地
    // 的话，其他设备下次同步会把整个源列表又推回来。
    final List<String> ids =
        _sources.map((VodSource s) => s.id).toList(growable: false);
    _sources = <VodSource>[];
    _activeId = '';
    await SyncTombstones.instance.markMany(tombstoneType, ids);
    await _persist();
    VodRepository.instance.clearAll();
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
