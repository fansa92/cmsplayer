import 'package:flutter/foundation.dart';

import '../data/models/play_record.dart';
import '../data/repository/record_repository.dart';
import '../data/sync/sync_payload.dart';
import '../data/sync/sync_tombstones.dart';

/// 播放历史 / 续播进度状态。
class HistoryStore extends ChangeNotifier {
  List<PlayRecord> _records = <PlayRecord>[];
  bool _loading = true;
  bool _disposed = false;

  List<PlayRecord> get records => _records;
  bool get loading => _loading;
  bool get isEmpty => _records.isEmpty;

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  /// 本表在墓碑里的类型名。
  ///
  /// 删除本地数据时必须顺手记一条墓碑，否则对方设备下次同步会把这条记录
  /// 又推回来 —— 删除看起来"没生效"。见 [SyncTombstones]。
  static const String tombstoneType = SyncBox.history;

  Future<void> load() async {
    _loading = true;
    _emit();
    try {
      _records = await RecordRepository.loadHistory();
    } finally {
      _loading = false;
      _emit();
    }
  }

  PlayRecord? byKey(String key) {
    for (final PlayRecord r in _records) {
      if (r.key == key) return r;
    }
    return null;
  }

  PlayRecord? byIds(String sourceId, int vodId) => byKey('$sourceId|$vodId');

  List<PlayRecord> forSource(String sourceId) =>
      _records.where((PlayRecord r) => r.sourceId == sourceId).toList();

  List<PlayRecord> recent({int limit = 20}) => _records.take(limit).toList();

  /// 覆盖式写入。调用方负责节流，避免播放中高频落盘。
  Future<void> upsert(PlayRecord record) async {
    final int index = _records.indexWhere((PlayRecord e) => e.key == record.key);
    if (index >= 0) {
      _records[index] = record;
    } else {
      _records.insert(0, record);
    }
    _records.sort((PlayRecord a, PlayRecord b) => b.updatedAt.compareTo(a.updatedAt));
    await _save();
    _emit();
  }

  Future<void> remove(String key) async {
    final int index = _records.indexWhere((PlayRecord e) => e.key == key);
    if (index < 0) return;
    _records.removeAt(index);
    // 先记墓碑再落盘：反过来的话，进程在这中间被杀掉就会留下"数据删了但
    // 墓碑没记"的状态，同步时对方会把记录原样推回来。
    await SyncTombstones.instance.mark(tombstoneType, key);
    await _save();
    _emit();
  }

  Future<void> removeMany(List<String> keys) async {
    final Set<String> set = keys.toSet();
    final List<String> removed = _records
        .where((PlayRecord e) => set.contains(e.key))
        .map((PlayRecord e) => e.key)
        .toList(growable: false);
    if (removed.isEmpty) return;
    _records.removeWhere((PlayRecord e) => set.contains(e.key));
    await SyncTombstones.instance.markMany(tombstoneType, removed);
    await _save();
    _emit();
  }

  Future<void> clear() async {
    // 清空是逐条删除的等价物，所以要把当时存在的每一条都记成墓碑 ——
    // 只清本地的话，其他设备下次同步会把整个列表又推回来。
    final List<String> keys =
        _records.map((PlayRecord e) => e.key).toList(growable: false);
    _records = <PlayRecord>[];
    await SyncTombstones.instance.markMany(tombstoneType, keys);
    await _save();
    _emit();
  }

  Future<void> _save() => RecordRepository.saveHistory(_records);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
